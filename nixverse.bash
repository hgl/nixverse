cmd_node_state() {
	local name=$1
	local filter=${2:-.}

	local state
	# shellcheck disable=SC2154
	state=$(
		jq --raw-output --arg name "$name" '
			first(
				.[] |
				if .group == "" then
					select(.node.name == $name) | . as $node | del(.node) + .node
				else
					. as $g | .nodes[] | select(.name == $name) |
					. as $node | $g | del(.nodes) + $node
				end
			)
		'"| $filter" "$entitiesPath"
	)
	if [[ -z $state ]]; then
		echo >&2 "Unknown node $name"
		exit 1
	fi
	echo "$state"
}

cmd_group_state() {
	local name=$1
	local filter=${2:-.}

	local state
	state=$(
		jq --raw-output --arg name "$name" '
			first(
				.[] |
				if .group == "" then
					empty
				else
					select(.group == $name)
				end
			)
		'"| $filter" "$entitiesPath"
	)
	if [[ -z $state ]]; then
		echo >&2 "Unknown group $name"
		exit 1
	fi
	echo "$state"
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
