PATH=@PATH@:$PATH

cmd_node_build() {
	local node_name=$1
	shift

	find_flake_dir
	find_node
	build_node "$@"
}

cmd_node_bootstrap() {
	local mk_hwconf=''
	OPTIND=1
	while getopts 'uc' opt; do
		case $opt in
		c) mk_hwconf=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local node_name=$1
	local dst=${2-}

	find_flake_dir
	find_node
	build_node
	local use_disko=''
	local f
	if f=$(find_node_file -g partition.bash) && [[ -n $f ]]; then
		#shellcheck disable=SC2029
		ssh "$dst" "$(<"$f")"
	elif f=$(find_node_file -g disk-config.nix) && [[ -n $f ]]; then
		use_disko=1
	else
		local boot_type boot_device root_format
		IFS=, read -r boot_type boot_device root_format < <(
			jq --raw-output '"\(.boot.type),\(.boot.device.path),\(.boot.device.root.format)"' <<<"$node_json"
		)
		#shellcheck disable=SC2029
		ssh "$dst" "
			BOOT_TYPE='$boot_type'
			BOOT_DEVICE='$boot_device'
			ROOT_FORMAT='$root_format'
			$(<@out@/share/nixverse/partition)
		"
	fi
	local node_dir=$flake_dir/nodes/$node_release/${node_group:+$node_group/}$node_name
	args=()
	if [[ -n $mk_hwconf ]]; then
		args+=(
			--generate-hardware-config
			nixos-generate-config
			"$node_dir/hardware-configuration.nix"
		)
	fi
	local node_build_dir=$flake_dir/build/${node_group:+$node_group/}$node_name
	if [[ -d $node_build_dir/fs ]]; then
		args+=(--extra-files "$node_build_dir/fs")
	fi
	if [[ -z $use_disko ]]; then
		args+=(--phases 'install,reboot')
	fi
	nixos-anywhere \
		--flake "$flake_dir#$node_name" \
		"${args[@]}" \
		"$dst"
}

cmd_node_state() {
	local node_name=$1
	local filter=${2:-.}
	node_json "$filter"
}

cmd_group_state() {
	local node_group=$1
	local filter=${2:-.}

	find_flake_dir
	local fn
	fn=$(
		cat <<-EOF
			flake:
			let
				lib = flake.inputs.nixpkgs-unstable.lib;
				lib' = flake.inputs.nixverse.lib;
				releases = lib'.concatMapAttrsToList (os: releases: releases) lib'.releaseGroups;
				nodes = lib'.loadNodes flake releases;
				group = lib.findFirst (ns: (lib.elemAt ns 0).group == "$node_group") null (
					lib.concatMap (n: if n ? nodes then [ n.nodes ] else [ ]) nodes
				);
			in
			{
				flakePath = toString flake;
				nodes = lib'.filterRecursive
					(n: v: !(lib.isFunction v))
					group;
			}
		EOF
	)
	filter=$(
		cat <<-EOF
			if . == null then
				"Unknown group $node_group\n" | halt_error(1)
			else
				. | $filter
			end
		EOF
	)
	nix eval --json --no-warn-dirty --impure "$flake_dir#self" --apply "$fn" |
		jq --raw-output "$filter"
}

find_flake_dir() {
	flake_dir=$PWD
	local f
	while true; do
		f=$flake_dir/flake.nix
		if [[ -e $f ]]; then
			return
		fi
		if [[ $flake_dir = / ]]; then
			echo >&2 "not in a flake directory: $PWD"
			return 1
		fi
		flake_dir=$(dirname "$flake_dir")
	done
}

find_node() {
	node_json=$(node_json .)
	IFS=, read -r node_release node_os node_channel node_group < <(
		jq --raw-output '"\(.release),\(.os),\(.channel),\(.group)"' <<<"$node_json"
	)
}

find_node_file() {
	OPTIND=1
	local look_group=''
	while getopts 'g' opt; do
		case $opt in
		g) look_group=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local file=$1
	local files=()
	if [[ -z $node_group ]]; then
		scripts+=("$flake_dir/nodes/$node_release/$node_name/$file")
	else
		scripts+=("$flake_dir/nodes/$node_release/$node_group/$node_name/$file")
		if [[ -n $look_group ]]; then
			scripts+=("$flake_dir/nodes/$node_release/$node_group/$file")
		fi
	fi
	local f
	for f in "${files[@]}"; do
		if [[ -e $f ]]; then
			echo "$f"
			return
		fi
	done
	echo ''
}

node_json() {
	local filter=$1
	find_flake_dir
	local fn
	fn=$(
		cat <<-EOF
			flake:
			let
				lib = flake.inputs.nixpkgs-unstable.lib;
				lib' = flake.inputs.nixverse.lib;
				releases = lib'.concatMapAttrsToList (os: releases: releases) lib'.releaseGroups;
				nodes = lib'.loadNodes flake releases;
				node = lib.findFirst (n: n.name == "$node_name") null (
					lib.concatMap (n: n.nodes or [ n.node ]) nodes
				);
			in
			lib'.filterRecursive
				(n: v: !(lib.isFunction v))
				node
		EOF
	)
	filter=$(
		cat <<-EOF
			if . == null then
				"Unknown node $node_name\n" | halt_error(1)
			else
				. | $filter
			end
		EOF
	)
	nix eval --json --no-warn-dirty --impure "$flake_dir#self" --apply "$fn" |
		jq --raw-output "$filter"
}

build_node() {
	f=$(find_node_file -g Makefile)
	if [[ -z $f ]]; then
		if [[ -e $flake_dir/Makefile ]]; then
			f=$flake_dir/Makefile
		else
			return
		fi
	fi
	local dir
	dir=$(dirname "$f")
	NODE_RELEASE=$node_release \
		NODE_OS=$node_os \
		NODE_CHANNEL=$node_channel \
		NODE_NAME=$node_name \
		NODE_GROUP=$node_group \
		make \
		-C "$dir" \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
}

HELP=''
COMMAND=${1-}
if [[ $COMMAND = help ]]; then
	shift
	COMMAND=${1-}
	HELP=1
fi
SUBCOMMAND=${2-}
cmd=cmd${HELP:+_help}_${COMMAND}_${SUBCOMMAND}
if [[ -n $COMMAND ]] && [[ -n $SUBCOMMAND ]] && [[ $(type -t "$cmd") = function ]]; then
	shift 2
	"$cmd" "$@"
	exit
fi
cmd=cmd${HELP:+_help}_$COMMAND
if [[ -n $COMMAND ]] && [[ $(type -t "$cmd") = function ]]; then
	shift
	"$cmd" "$@"
	exit
fi
if [[ -n $COMMAND ]]; then
	cat >&2 <<-EOF
		Unknown command: $COMMAND${SUBCOMMAND:+ $SUBCOMMAND}
		Use "nixverse help" to find out usage.
	EOF
	exit 1
fi
cmd_help
