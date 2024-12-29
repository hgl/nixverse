#!@shell@
# shellcheck shell=bash
set -euo pipefail

PATH=@path@:$PATH
node_name='@node_name@'

cmd_reload() {
	nixverse node deploy "$node_name"
}

cmd_update() {
	nixverse node update "$node_name"
}

cmd_rollback() {
	nixverse node rollback "$node_name"
}

cmd_clean() {
	nixverse node clean "$node_name"
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
