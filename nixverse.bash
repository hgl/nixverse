cmd_node_state() {
	local name=$1
	local filter=${2:-.}

	local flake fn
	flake=$(locate_flake)
	fn=$(
		cat <<-EOF
			flake:
			let
				lib = flake.inputs.nixpkgs-unstable.lib;
				lib' = flake.inputs.nixverse.lib;
				releases = lib'.concatMapAttrsToList (os: releases: releases) lib'.releaseGroups;
				nodes = lib'.loadNodes flake releases;
				node = lib.findFirst (n: n.name == "$name") null (
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
				"Unknown node $name\n" | halt_error(1)
			else
				. | $filter
			end
		EOF
	)
	nix eval --json --no-warn-dirty --impure "$flake#self" --apply "$fn" |
		jq --raw-output "$filter"
}

cmd_group_state() {
	local name=$1
	local filter=${2:-.}

	local flake fn
	flake=$(locate_flake)
	fn=$(
		cat <<-EOF
			flake:
			let
				lib = flake.inputs.nixpkgs-unstable.lib;
				lib' = flake.inputs.nixverse.lib;
				releases = lib'.concatMapAttrsToList (os: releases: releases) lib'.releaseGroups;
				nodes = lib'.loadNodes flake releases;
				node = lib.findFirst (ns: (lib.elemAt ns 0).group == "$name") null (
					lib.concatMap (n: if n ? nodes then [ n.nodes ] else [ ]) nodes
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
				"Unknown group $name\n" | halt_error(1)
			else
				. | $filter
			end
		EOF
	)
	nix eval --json --no-warn-dirty --impure "$flake#self" --apply "$fn" |
		jq --raw-output "$filter"
}

locate_flake() {
	dir=$PWD
	while true; do
		f=$dir/flake.nix
		if [[ -e $f ]]; then
			echo "$dir"
			return
		fi
		if [[ $dir = / ]]; then
			echo >&2 "not in a flake directory: $dir"
			return 1
		fi
		dir=$(dirname "$dir")
	done
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
