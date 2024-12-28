#!@shell@
set -euo pipefail

PATH=@path@:$PATH
flake_dir='@flake@'
node_name='@node_name@'
node_os='@node_os@'

cmd_reload() {
	case $node_os in
	nixos)
		nixos-rebuild switch \
			--flake "$flake_dir#$node_name" \
			--show-trace
		;;
	darwin)
		darwin-rebuild switch \
			--flake "$flake_dir#$node_name" \
			--show-trace
		;;
	*)
		echo >&2 "Unknown OS: $node_os"
		return 1
		;;
	esac
}

cmd_update() {
	pushd "$flake_dir" >/dev/null
	nix flake update
	popd >/dev/null

	cmd_reload
}

cmd_clean() {
	nix-collect-garbage --delete-old
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
