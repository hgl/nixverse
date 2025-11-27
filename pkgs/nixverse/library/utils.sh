# shellcheck shell=bash
set -euo pipefail

secrets_nix=build/secrets.nix

secrets_json() {
	local flake=$1
	local sops_config=$2
	local secrets_yaml=$3
	local out=$4

	decrypt_to_secrets_nix "$sops_config" "$secrets_yaml"
	local dir
	dir=$(
		umask a=,u=rw
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse) lib getSecrets;
  secrets = getSecrets ($(<"$secrets_nix"));
in
{
  "secrets.json" = builtins.toJSON secrets.config;
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	mv "$dir/secrets.json" "$out"
}

build_node_secrets_json() {
	local flake=$1
	local sops_config=$2
	local secrets_yaml=$3
	local node_names=$4

	decrypt_to_secrets_nix "$sops_config" "$secrets_yaml"
	local dir
	dir=$(
		umask a=,u=rw
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse) lib getSecrets getNodesSecrets;
  nodeNames = lib.splitString " " "$node_names";
  secrets = getSecrets ($(<"$secrets_nix"));
in
{
  nodes = getNodesSecrets secrets.config nodeNames;
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	local f
	for f in "$dir"/nodes/*/secrets.json; do
		mv "$f" "build${f#"$dir"}"
	done
}

fs_makefile() {
	local node_name node_dir group_names group_name entries entry dir fs_dir \
		src out ssh_host_key files secrets subdirs subdir
	declare -A files secrets subdirs
	while IFS=, read -r node_name node_dir group_names; do
		entries=("$node_dir")
		for group_name in $group_names; do
			entries+=("nodes/$group_name/common")
		done

		files=()
		secrets=()
		subdirs=()
		for entry in "${entries[@]}"; do
			read -r dir <<<"$entry"
			for fs_dir in "private/$dir/secrets/fs" "$dir/secrets/fs"; do
				if [[ ! -d "$fs_dir" ]]; then
					continue
				fi
				while read -r src; do
					out=build/nodes/$node_name/fs${src#"$fs_dir"}
					ssh_host_key=build/nodes/$node_name/fs/etc/ssh/ssh_host_ed25519_key
					if [[ $out = "$ssh_host_key" ]]; then
						continue
					fi
					if [[ -z ${secrets[$out]-} ]]; then
						secrets[$out]=$src
						echo "nodes/$node_name: $out"
						subdir=$(dirname "$out")
						if [[ $subdir != build/nodes/$node_name/fs/etc/ssh ]]; then
							subdirs[$subdir]=1
						fi
						echo "$out: $src build/nodes/$node_name/age.key | $subdir"
						echo -e '\tumask a=,u=rw'
						# shellcheck disable=SC2016
						echo -e '\tSOPS_AGE_KEY=$$(< $(word 2,$^)) sops --config "$$SOPS_CONFIG" --decrypt --output $@ $<'
					fi
				done < <(
					if [[ $fs_dir = private/* ]]; then
						git -C private ls-files "${fs_dir#private/}" | sed 's,^,private/,'
					else
						git ls-files "$fs_dir"
					fi
				)
			done
			for fs_dir in "private/$dir/fs" "$dir/fs"; do
				if [[ ! -d "$fs_dir" ]]; then
					continue
				fi
				while read -r src; do
					out=build/nodes/$node_name/fs${src#"$fs_dir"}
					if [[ -z ${secrets[$out]-} && -z ${files[$out]-} ]]; then
						files[$out]=$src
						subdir=$(dirname "$out")
						if [[ $subdir != build/nodes/$node_name/fs/etc/ssh ]]; then
							subdirs[$subdir]=1
						fi
						echo "nodes/$node_name: $out"
						echo "$out: $src | $subdir"
						echo -e '\tcp -p $< $@'
					fi
				done < <(
					if [[ $fs_dir = private/* ]]; then
						git -C private ls-files "${fs_dir#private/}" |
							sed 's,^,private/,'
					else
						git ls-files "$fs_dir"
					fi
				)
			done
		done
		for subdir in "${!subdirs[@]}"; do
			echo "$subdir:"
			echo -e '\tmkdir -p $@'
		done
	done
}

rsync_fs() {
	local addr=$1
	local dir=$2

	if [[ ! -d $dir ]]; then
		return
	fi

	local empty
	empty=$(find "$dir" -prune -empty -printf 1)
	if [[ -n $empty ]]; then
		return
	fi

	rsync --recursive --links --perms --times \
		"$dir/" "$addr:/"
}

eval_flake() {
	local args
	args=$(getopt -o '' --long 'write,impure' -- "$@")
	eval set -- "$args"

	local write=''
	local impure=''
	while true; do
		case $1 in
		--write)
			write=1
			shift
			;;
		--impure)
			impure=1
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo >&2 "Unhandled flag $1"
			return 1
			;;
		esac
	done

	args=()
	if [[ -z $write ]]; then
		args+=(--raw)
	else
		local dir
		dir=${TMPDIR:-/tmp}
		if [[ $dir = */ ]]; then
			dir+=$(uuidgen)
		else
			dir+=/$(uuidgen)
		fi
		args+=(--write-to "$dir")
	fi

	if [[ -n $impure ]]; then
		args+=(--impure)
	fi

	local flake=$1
	local expr
	expr=$(
		cat <<EOF
flake:
assert if flake ? nixverse then
  true
else
  throw "Not inside a flake with nixverse loaded";
$(cat)
EOF
	)
	shift

	nix eval \
		--no-warn-dirty \
		--apply "$expr" \
		--show-trace \
		"${args[@]}" \
		"$flake?submodules=1#."

	if [[ -n $write ]]; then
		echo "$dir"
	fi
}

find_flake() {
	if [[ -n ${FLAKE-} ]]; then
		if [[ ! -e $FLAKE/flake.nix ]]; then
			echo >&2 "FLAKE is not a flake directory: $FLAKE"
			return 1
		fi
		flake=$FLAKE
		return
	fi
	flake=$PWD
	while true; do
		if [[ -e $flake/flake.nix ]]; then
			echo "$flake"
			return
		fi
		if [[ $flake = / ]]; then
			echo >&2 "not in a flake directory: $PWD"
			return 1
		fi
		flake=$(dirname "$flake")
	done
}

find_sops_config() {
	local flake=$1

	local sops_config=''
	if [[ -e $flake/.sops.yaml ]]; then
		sops_config=$flake/.sops.yaml
	fi
	if [[ -e $flake/private/.sops.yaml ]]; then
		if [[ -n $sops_config ]]; then
			echo >&2 "Both $flake/.sops.yaml and $flake/private/.sops.yaml exist, only one is allowed"
		fi
		sops_config=$flake/private/.sops.yaml
	fi
	if [[ -z $sops_config ]]; then
		echo >&2 "Missing the .sops.yaml file"
		return 1
	fi
	echo "$sops_config"
}

find_secrets_yaml() {
	local ignore_nonexist=''
	if [[ $1 == -i ]]; then
		ignore_nonexist=1
		shift
	fi
	local flake=$1

	local secrets_yaml=''
	if [[ -e $flake/secrets.yaml ]]; then
		secrets_yaml=$flake/secrets.yaml
	fi
	if [[ -e $flake/private/secrets.yaml ]]; then
		if [[ -n $secrets_yaml ]]; then
			echo >&2 "Both $secrets_yaml and $flake/private/secrets.yaml exist, only one is allowed"
			return 1
		fi
		secrets_yaml=$flake/private/secrets.yaml
	elif [[ -n $secrets_yaml && -d $flake/private ]]; then
		secrets_yaml=$flake/private/secrets.yaml
		mv "$flake/secrets.yaml" "$secrets_yaml"
		if git rev-parse --is-inside-work-tree >/dev/null; then
			git add --intent-to-add --force "$secrets_yaml"
		fi
	fi
	if [[ -z $ignore_nonexist && -z $secrets_yaml ]]; then
		echo >&2 "No secrets file exist, edit to create one"
		return 1
	fi
	echo "$secrets_yaml"
}

decrypt_to_secrets_nix() {
	local args
	args=$(getopt -n nixverse -o '' --long 'flake:' -- "$@")
	eval set -- "$args"
	unset args

	local flake=''
	while true; do
		case $1 in
		--flake)
			flake=$2
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo >&2 "Unhandled flag $1"
			return 1
			;;
		esac
	done

	local sops_config=$1
	local secrets_yaml=${2-}

	if [[ -z $secrets_yaml ]]; then
		secrets_yaml=$(find_secrets_yaml "$flake")
	fi

	mkdir -p "$(dirname "$secrets_nix")"
	(
		umask a=,u=rw
		sops --config "$sops_config" --decrypt --output-type binary \
			--output "$secrets_nix" "$secrets_yaml"
	)
}

trap_add() {
	local cmd=$1
	shift
	local sig
	for sig; do
		cmd=$(
			# shellcheck disable=SC2317
			extract() { echo "${3-}"; }
			existing=$(trap -p "$sig")
			eval "extract $existing"
			echo "$cmd"
		)
		trap -- "$cmd" "$sig"
	done
}

make() {
	command make \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
}

nix() {
	command nix --extra-experimental-features 'nix-command flakes' "$@"
}

cmd() {
	local cmd=cmd
	if [[ ${1-} = help ]]; then
		cmd+=_help
		shift
	fi
	case ${1-} in
	'')
		case ${2-} in
		'')
			if [[ $cmd = cmd_help ]]; then
				cmd_help ''
				return
			else
				cmd_help '' >&2
				return 1
			fi
			;;
		help)
			if [[ $cmd != cmd_help ]]; then
				shift 2
				cmd help '' "$@"
				return
			fi
			;;
		*)
			shift
			local args
			args=$(getopt -n nixverse -o '+h' --long 'help' -- "$@")
			eval set -- "$args"
			unset args

			while true; do
				case $1 in
				-h | --help)
					if [[ $cmd = cmd_help ]]; then
						cmd help '' help
					else
						cmd_help ''
					fi
					return
					;;
				--)
					shift
					break
					;;
				*)
					echo >&2 "Unhandled flag $1"
					return 1
					;;
				esac
			done
			set -- '' "$@"
			;;
		esac
		;;
	*)
		case ${2-} in
		'')
			cmd help '' "$1" >&2
			return 1
			;;
		*)
			local first=$1
			shift

			local args
			args=$(getopt -n nixverse -o '+h' --long 'help' -- "$@")
			eval set -- "$args"
			unset args

			while true; do
				case $1 in
				-h | --help)
					cmd help '' "$first"
					return
					;;
				--)
					shift
					break
					;;
				*)
					echo >&2 "Unhandled flag $1"
					return 1
					;;
				esac
			done
			set -- "$first" "$@"
			unset first
			;;
		esac
		;;
	esac
	cmd+=${1:+_$1}_$2
	if [[ $(type -t "$cmd") = function ]]; then
		shift 2
		set -- "$cmd" "$@"
		unset cmd
		"$@"
	else
		if [[ $cmd = cmd_help_* ]]; then
			cat >&2 <<-EOF
				Unknown help topic $2
				Run "nixverse help${1:+ $1}".
			EOF
		else
			cat >&2 <<-EOF
				Unknown command $2
				Use "nixverse help${1:+ $1}" to find out usage.
			EOF
		fi
		return 1
	fi
}
