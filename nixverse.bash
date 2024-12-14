#!@shell@
set -euo pipefail

PATH=@PATH@:$PATH

cmd_node() {
	cmd "$@"
}

cmd_node_build() {
	local node_name=$1
	shift

	find_node
	build_node "$@"
}

cmd_node_bootstrap() {
	local update=''
	local mk_hwconf=''
	OPTIND=1
	while getopts 'uc' opt; do
		case $opt in
		u) update=1 ;;
		c) mk_hwconf=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local node_name=$1
	local dst=${2-}

	find_node
	UPDATE=$update build_node
	local use_disko=''
	local f
	if f=$(find_node_file partition.bash) && [[ -n $f ]]; then
		#shellcheck disable=SC2029
		ssh "$dst" "$(<"$f")"
	elif f=$(find_node_file disk-config.nix) && [[ -n $f ]]; then
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
	args=()
	f=$(find_node_file hardware-configuration.nix)
	if [[ -z "$f" ]] || [[ -n $mk_hwconf ]]; then
		args+=(
			--generate-hardware-config
			nixos-generate-config
			"$node_dir/hardware-configuration.nix"
		)
	fi
	decrypt_ssh_host_keys
	#shellcheck disable=SC2064
	trap "rm '$node_dir/fs/etc/ssh'/ssh_host_*_key" EXIT
	args+=(--extra-files "$node_dir/fs")
	if [[ -z $use_disko ]]; then
		args+=(--phases 'install,reboot')
	fi
	nixos-anywhere \
		--flake "$flake#$node_name" \
		"${args[@]}" \
		"$dst"
}

cmd_test() {
	local node_name=$1
	find_node
	decrypt_ssh_host_keys
}

cmd_node_deploy() {
	local update=''
	OPTIND=1
	while getopts 'u' opt; do
		case $opt in
		u) update=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local node_name=$1
	local dst=${2-}

	find_node
	UPDATE=$update build_node

	local args=()
	if [[ -n $dst ]]; then
		args+=(
			--target-host "$dst"
			--use-remote-sudo
			--fast
		)
	fi
	nixos-rebuild switch \
		--flake "$flake#$node_name" \
		--show-trace \
		"${args[@]}"
	local dirs
	dirs=$(find_node_file -acr fs)
	if [[ -z $dirs ]]; then
		echo >&2 'fs directory not found'
		return 1
	fi
	readarray -t dirs <<<"$dirs"
	rsync \
		--quiet \
		--recursive \
		--perms \
		--times \
		"${dirs[@]/%//}" \
		"${dst:+$dst:}/"
}

cmd_node_rollback() {
	local node_name=$1
	local dst=${2-}

	find_flake

	local args=()
	if [[ -n $dst ]]; then
		args+=(
			--target-host "$dst"
			--use-remote-sudo
			--fast
		)
	fi
	nixos-rebuild switch \
		--flake "$flake#$node_name" \
		"${args[@]}" \
		--rollback
}

cmd_cleanup() {
	local dst=${1-}

	ssh "$dst" nix-collect-garbage --delete-old
}

cmd_node_state() {
	local node_name=$1
	local filter=${2:-.}
	node_json "$filter"
}

cmd_secrets() {
	cmd "$@"
}

cmd_secrets_edit() {
	local node_name=$1
	local secrets_name=${2:-main.yaml}

	find_node
	local base_secrets=$node_base_dir/secrets.yaml
	local node_secrets=$node_dir/secrets/main.yaml
	if [[ $secrets_name = main.yaml ]]; then
		local new=''
		if [[ ! -e $base_secrets ]]; then
			new=1
			local recipients
			recipients=$(master_age_recipients)
			(
				umask a=,u=rw
				cat <<EOF >"$base_secrets"
common:
  # secrets for all nodes
  name: value
${node_name}:
  # secrets for this node only, overrides those in common
  name: value
EOF
			)
			sops encrypt --age "$recipients" --in-place "$base_secrets"
		fi
		if sops --indent 2 "$base_secrets"; then
			:
		elif [[ $? = 200 ]]; then
			if [[ -z $new ]] && [[ -e $node_secrets ]]; then
				return
			fi
		else
			return 1
		fi
		local tmp
		tmp=$(mktemp)
		#shellcheck disable=SC2016
		sops decrypt "$base_secrets" |
			yq --yaml-output --indent 2 --arg n "$node_name" '(.common // {}) * (.[$n] // {})' >"$tmp"
		#shellcheck disable=SC2064
		trap "rm -f '$tmp'" EXIT

		f=
		if [[ ! -e $node_secrets ]]; then
			local recipient
			recipient=$(node_age_recipient)
			(
				umask a=,u=rw
				sops encrypt --age "$recipient" --filename-override "$node_secrets" --output "$node_secrets" "$tmp"
			)
		else
			local key
			key=$(node_age_key)
			EDITOR="mv $tmp" SOPS_AGE_KEY=$key sops edit "$node_secrets"
		fi
	fi
}

cmd_group_state() {
	local node_group=$1
	local filter=${2:-.}

	find_flake
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
			lib'.filterRecursive
				(n: v: !(lib.isFunction v))
				group
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
	nix eval --json --no-warn-dirty --impure "$flake#self" --apply "$fn" |
		jq --raw-output "$filter"
}

find_flake() {
	flake=$PWD
	local f
	while true; do
		f=$flake/flake.nix
		if [[ -e $f ]]; then
			return
		fi
		if [[ $flake = / ]]; then
			echo >&2 "not in a flake directory: $PWD"
			return 1
		fi
		flake=$(dirname "$flake")
	done
}

find_node() {
	node_json=$(node_json .)
	IFS=, read -r node_release node_os node_channel node_group < <(
		jq --raw-output '"\(.release),\(.os),\(.channel),\(.group)"' <<<"$node_json"
	)
	if [[ -z ${flake-} ]]; then
		find_flake
	fi
	if [[ -z $node_group ]]; then
		node_base_dir=$flake/nodes/$node_release/$node_name
		node_dir=$node_base_dir
	else
		node_base_dir=$flake/nodes/$node_release/$node_group
		node_dir=$node_base_dir/$node_name
	fi
}

find_node_file() {
	local all=''
	local use_common=''
	local reverse=''
	OPTIND=1
	while getopts 'acr' opt; do
		case $opt in
		a) all=1 ;;
		c) use_common=1 ;;
		r) reverse=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local name=$1
	local files=("$node_dir/$name")
	if [[ -n $node_group ]]; then
		local dir
		if [[ -n $use_common ]]; then
			dir=$node_base_dir/common
		else
			dir=$node_base_dir
		fi
		if [[ -z $reverse ]]; then
			files+=("$dir/$name")
		else
			files=("$dir/$name" "${files[@]}")
		fi
	fi
	local f
	for f in "${files[@]}"; do
		if [[ -e $f ]]; then
			echo "$f"
			if [[ -z $all ]]; then
				return
			fi
		fi
	done
	echo ''
}

node_json() {
	local filter=$1
	find_flake
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
	nix eval --json --no-warn-dirty --impure "$flake#self" --apply "$fn" |
		jq --raw-output "$filter"
}

master_age_recipients() {
	local recipients
	if [[ ! -e $flake/config.yaml ]]; then
		echo >&2 "config.yaml not found in $flake"
		return 1
	fi
	recipients=$(yq --raw-output '[.["master-age-recipients"] // empty] | flatten(1) | join(",")' "$flake/config.yaml")
	if [[ -z $recipients ]]; then
		echo >&2 "Missing master-age-recipient in $flake/config.yaml"
		return 1
	fi
	echo "$recipients"
}

node_age_recipient() {
	ssh-to-age -i "$node_dir/fs/etc/ssh/ssh_host_ed25519_key.pub"
}

node_age_key() {
	sops decrypt "$node_dir/secrets/ssh_host_ed25519_key" | ssh-to-age -private-key
}

build_node() {
	f=$(find_node_file -r Makefile)
	if [[ -z $f ]]; then
		if [[ -e $flake/Makefile ]]; then
			f=$flake/Makefile
		else
			return
		fi
	fi
	local dir
	dir=$(dirname "$f")
	local recipients
	recipients=$(master_age_recipients)

	NODE_RELEASE=$node_release \
		NODE_OS=$node_os \
		NODE_CHANNEL=$node_channel \
		NODE_NAME=$node_name \
		NODE_GROUP=$node_group \
		MASTER_AGE_RECIPIENTS=$recipients \
		make \
		-C "$dir" \
		-f @out@/share/nixverse/Makefile \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
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

decrypt_ssh_host_keys() {
	(
		umask a=,u=rw
		for f in "$node_dir/secrets"/ssh_host_*_key; do
			sops decrypt --output "$node_dir/fs/etc/ssh/$(basename "$f")" "$f"
		done
	)
}

cmd() {
	COMMANDS="${COMMANDS:+$COMMANDS }$1"
	shift
	local cmd=cmd${HELP:+_help}_${COMMANDS// /_}

	if [[ $(type -t "$cmd") = function ]]; then
		"$cmd" "$@"
	else
		cat >&2 <<-EOF
			Unknown command: $COMMANDS
			Use "nixverse help" to find out usage.
		EOF
		return 1
	fi
}

HELP=''
if [[ ${1-} = help ]]; then
	shift
	HELP=1
fi
cmd "$@"
