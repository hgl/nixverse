#!@shell@
# shellcheck shell=bash
set -xeuo pipefail

PATH=@path@:$PATH

cmd_help() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse <command> [ARGUMENT]...

Commands:
  node         manage nodes
  secrets      encrypt or decrypt secrets
  help         show help for a command

Use "nixverse <command> --help" for more information about a command.
EOF
	else
		cmd help "$@"
	fi
}

cmd_help_node() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse node <command> [ARGUMENT]...

Manage nodes

Commands:
  deploy       manage nodes
  value        print value specified in node.nix or group.nix

Use "nixverse node <command> --help" for more information about a command.
EOF
	else
		cmd help node "$@"
	fi
}

cmd_help_node_deploy() {
	cat <<EOF
Usage: nixverse node deploy [OPTION]... <NODE>...

Deploy one or more nodes
EOF
}

cmd_help_secrets() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse secrets <command> [ARGUMENT]...

Manage secrets

Commands:
  edit         edit an encrytped file
  encrypt      encrypt a file
  decrypt      decrypt a file

Use "nixverse secrets <command> --help" for more information about a command.
EOF
	else
		cmd help secrets "$@"
	fi
}

cmd_help_secrets_edit() {
	cat <<EOF
Usage: nixverse secrets edit [OPTION]... [FILE]

Edit an encrytped file.
With no FILE, edit top secrets.yaml.

Options:
  -h, --help    show this help
EOF
}

cmd_help_secrets_encrypt() {
	cat <<EOF
Usage: nixverse secrets encrypt [OPTION]... [FILE] [OUTPUT]

Encrypt a file.
With no FILE or FILE is -, encrypt standard input.
With no OUTPUT or OUTPUT is -, output to standard output.

Options:
  -i, --in-place      encrypt the file in-place
  -h, --help          show this help
EOF
}

cmd_help_secrets_decrypt() {
	cat <<EOF
Usage: nixverse secrets decrypt [OPTION]... [FILE] [OUTPUT]

Decrypt a file.
With no FILE or FILE is -, decrypt standard input.
With no OUTPUT or OUTPUT is -, output to standard output.

Options:
  -i, --in-place      decrypt the file in-place
  -h, --help          show this help
EOF
}

cmd_help_help() {
	cat <<EOF
Usage: nixverse help <command>

Show help for the command
EOF
}

cmd_node() {
	cmd node "$@"
}

cmd_node_build() {
	local node_name=$1
	shift

	build_node
}

cmd_node_bootstrap() {
	local remote_build=''
	OPTIND=1
	while getopts 'r' opt; do
		case $opt in
		r) remote_build=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local node_name=$1
	local ssh_dst=${2-}

	local use_disko=''
	local f
	if f=$(find_node_file partition.bash) && [[ -n $f ]]; then
		#shellcheck disable=SC2029
		ssh "$ssh_dst" "$(<"$f")"
	elif f=$(find_node_file disk-config.nix) && [[ -n $f ]]; then
		use_disko=1
	else
		local boot_type boot_device root_format
		IFS=, read -r boot_type boot_device root_format < <(
			jq --raw-output '"\(.boot.type),\(.boot.device.path),\(.boot.device.root.format)"' <<<"$node_json"
		)
		#shellcheck disable=SC2029
		ssh "$ssh_dst" "
			BOOT_TYPE='$boot_type'
			BOOT_DEVICE='$boot_device'
			ROOT_FORMAT='$root_format'
			$(<@out@/libexec/nixverse/partition)
		"
	fi
	args=(
		--generate-hardware-config
		nixos-generate-config
		"$node_dir/hardware-configuration.nix"
	)

	if [[ -z $use_disko ]]; then
		args+=(--phases 'install')
	else
		args+=(--phases 'disko,install')
	fi
	if [[ -n $remote_build ]]; then
		args+=(--build-on-remote)
	fi
	nixos-anywhere \
		--flake "$flake#$node_name" \
		"${args[@]}" \
		"$ssh_dst"
	ssh "$ssh_dst" nix-env -iA nixos.rsync
	rsync_fs /mnt
}

cmd_node_deploy() {
	local args
	args=$(getopt -n nixverse -o 'h' --long '--help' -- "$@")
	eval set -- "$args"
	unset args

	while true; do
		case $1 in
		-h | --help)
			cmd help node deploy
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

	if [[ $# = 0 ]]; then
		cmd help node deploy >&2
		return 1
	fi

	local flake
	flake=$(find_flake)

	eval_nix "$flake" "nixverse.loadNodeDeployData (lib.splitString \" \" \"$*\")" | deploy
}

deploy_node() {
	local flake=$1
	local node_name=$2
	local node_os=$3
	local target_host=$4
	local build_host=$5
	local sudo=$6
	local ssh_opts=$7

	build_node

	case $node_os in
	nixos)
		local args=()
		args+=(

		)
		if [[ -n $target_host ]]; then
			args+=(--target-host "$target_host")
		fi
		if [[ -n $build_host ]]; then
			args+=(
				--build-host "$build_host"
				--fast
			)
		fi
		if [[ -n $sudo ]]; then
			args+=(--use-remote-sudo)
		fi
		NIX_SSHOPTS=$ssh_opts nixos-rebuild switch \
			--flake "$flake?submodules=1#$node_name" \
			--show-trace \
			"${args[@]}"
		;;
	darwin)
		args+=(
			darwin-rebuild switch
			--flake "$flake?submodules=1#$node_name"
			--show-trace
		)
		;;
	*)
		echo >&2 "Unknown node OS: $node_os"
		return 1
		;;
	esac
}
export -f deploy_node

cmd_node_rollback() {
	local node_name=$1
	local ssh_dst=${2-}

	find_flake

	local args=()
	if [[ -n $ssh_dst ]]; then
		args+=(
			--target-host "$ssh_dst"
			--use-remote-sudo
			--fast
		)
	fi
	nixos-rebuild switch \
		--flake "$flake#$node_name" \
		"${args[@]}" \
		--rollback
}

cmd_node_clean() {
	local node_name=$1
	local ssh_dst=${2-}

	if [[ -n $ssh_dst ]]; then
		set -- ssh "$ssh_dst"
	fi
	"$@" nix-collect-garbage --delete-old
}

cmd_node_update() {
	find_flake

	pushd "$flake" >/dev/null
	nix flake update
	popd >/dev/null

	cmd_node_deploy "$@"
}

cmd_node_value() {
	local args
	args=$(getopt -n nixverse -o 'h' --long '--help' -- "$@")
	eval set -- "$args"
	unset args

	while true; do
		case $1 in
		-h | --help)
			cmd help node value
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

	if [[ $# = 0 ]]; then
		cmd help node value >&2
		return 1
	fi

	local flake
	flake=$(find_flake)

	eval_nix "$flake" "nixverse.loadNodeValueData (lib.splitString \" \" \"$*\")"
}

cmd_secrets() {
	local f flake
	local private_dir=''
	local force=''

	local action=${1-}
	case $action in
	encrypt | decrypt)
		shift
		local args
		args=$(getopt -n nixverse -o 'hif' --long '--help,--in-place,--force' -- "$@")
		eval set -- "$args"
		unset args

		local in_place=''
		while true; do
			case $1 in
			-i | --in-place)
				shift
				in_place=1
				;;
			-f | --force)
				shift
				force=1
				;;
			-h | --help)
				cmd help secrets "$action"
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

		f=${1:--}
		local output=${2:-}
		flake=$(find_flake)

		if [[ $f != - ]]; then
			f=$(realpath --no-symlinks --relative-base "$flake" "$f")
			if [[ $f = /* ]]; then
				echo >&2 "Input file not within the flake directory"
				return 1
			fi
		fi
		if [[ -n $output ]]; then
			if [[ -n $in_place ]]; then
				echo >&2 "Output file must not be specified for --in-place"
				return 1
			fi
		else
			output=-
		fi
		if [[ $output != - ]]; then
			output=$(realpath --no-symlinks --relative-base "$flake" "$output")
			if [[ $output = "$f" ]]; then
				echo >&2 "Output to the same file is not allowed"
				return 1
			fi
		fi
		pushd "$flake" >/dev/null
		if [[ -d private ]]; then
			private_dir=private/
		fi
		;;
	edit)
		shift
		local args
		args=$(getopt -n nixverse -o 'h' --long '--help' -- "$@")
		eval set -- "$args"
		unset args

		while true; do
			case $1 in
			-f | --force)
				shift
				force=1
				;;
			-h | --help)
				cmd help secrets "$action"
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

		f=${1-}
		flake=$(find_flake)

		if [[ -z $f ]]; then
			pushd "$flake" >/dev/null
			if [[ -d private ]]; then
				private_dir=private/
			fi
			f=${private_dir}secrets.yaml
			if [[ -n $private_dir && -e secrets.yaml ]]; then
				if [[ -e $f ]]; then
					echo >&2 "secrets exist in both $flake and $flake/private, delete one and try again"
					return 1
				fi
				mv secrets.yaml "$f"
			fi
		else
			f=$(realpath --no-symlinks --relative-base "$flake" "$f")
			if [[ $f = /* ]]; then
				echo >&2 "Input file not within the flake directory"
				return 1
			fi
			pushd "$flake" >/dev/null
			if [[ -d private ]]; then
				private_dir=private/
			fi
		fi
		;;
	*)
		cmd secrets "$@"
		return
		;;
	esac

	local sops_action=(--indent 2)
	case $action in
	encrypt | decrypt)
		sops_action+=("--$action")
		if [[ -n $in_place ]]; then
			sops_action+=(--in-place)
		elif [[ $output != - ]]; then
			sops_action+=(--output "$output")
		fi
		;;
	esac

	local wo_private=${f#private/}
	if [[ $wo_private = secrets.yaml ]]; then
		case $action in
		encrypt)
			if [[ -z $force ]]; then
				echo >&2 'Specify --force to encrypt top secrets'
				popd >/dev/null
				return 1
			fi
			sops "${sops_action[@]}" "$f"
			return
			;;
		decrypt)
			if [[ -z $force && -n $in_place ]]; then
				echo >&2 'Specify --force to decrypt top secrets in-place'
				popd >/dev/null
				return 1
			fi
			sops "${sops_action[@]}" "$f"
			return
			;;
		esac

		mkdir -p build
		if [[ ! -e $f ]]; then
			(
				umask a=,u=rw
				cat <<EOF >build/secrets.yaml
node:
  name: value
EOF
			)
		else
			sops --decrypt --indent 2 --output build/secrets.yaml "$f"
		fi

		${SOPS_EDITOR:-${EDITOR:-vi}} build/secrets.yaml
		# shellcheck disable=SC2016
		yq --raw-output --slurp --arg f "$f" \
			'if . != [] and (.[0] | type == "object" and all(.[]; type == "object")) then
				""
			else
				"Must be an object of objects: \($f)" | halt_error(1)
			end' \
			build/secrets.yaml
		local entity_names
		entity_names=$(yq --raw-output 'keys | join(" ")' build/secrets.yaml)
		eval_nix "$flake" "nixverse.loadNodeSecretsData (lib.splitString \" \" \"$entity_names\")" |
			jq --raw-output '.[] | join(" ")' |
			(
				echo 'node_names :='
				while read -r node_name node_dir sections; do
					cat <<-EOF
						node_names += $node_name
						node_${node_name}_dir := $node_dir
						node_${node_name}_secrets_sections := $sections
					EOF
				done
			) |
			make -f - -f @out@/lib/nixverse/secrets.mk
		sops --encrypt --indent 2 --output "$f" build/secrets.yaml
		popd >/dev/null
		return
	fi

	if [[ $f = - ]]; then
		sops "${sops_action[@]}" "/dev/stdin"
		popd >/dev/null
		return
	fi

	local wo_nodes=${wo_private#nodes/}
	if [[ -z $wo_nodes ]]; then
		echo >&2 "Invalid secrets file"
		popd >/dev/null
		return 1
	fi
	if [[ $wo_nodes = "$wo_private" ]]; then
		sops "${sops_action[@]}" "$f"
		popd >/dev/null
		return
	fi

	local entity_name=${wo_nodes%%/*}
	local wo_entity_name=${wo_nodes#"$entity_name/"}
	if [[ -z $wo_entity_name ]] || [[ $wo_entity_name = "$wo_nodes" ]]; then
		echo >&2 "Invalid secrets file"
		popd >/dev/null
		return 1
	fi

	local valid=''
	local node_name node_dir wo_node_name
	if [[ -e private/nodes/$entity_name/node.nix ]] || [[ -e nodes/$entity_name/node.nix ]]; then
		valid=1
		# local recipient=nodes/$entity_name/fs/etc/ssh/ssh_host_ed25519_key.pub
		# if [[ -e private/$pubkey ]]; then
		# 	pubkey=private/$pubkey
		# elif [[ -e $pubkey ]]; then
		# 	:
		# else
		# 	pubkey=${private_dir}$pubkey
		# 	make_secrets "$pubkey"
		# fi
		node_name=$entity_name
		node_dir=nodes/$node_name
		wo_node_name=$wo_entity_name
	elif [[ -e private/nodes/$entity_name/group.nix ]] || [[ -e nodes/$entity_name/group.nix ]]; then
		valid=1
		node_name=${wo_entity_name%%/*}
		wo_node_name=${wo_entity_name#"$node_name/"}
		if [[ -z $wo_node_name ]]; then
			echo >&2 "Invalid secrets file"
			popd >/dev/null
			return 1
		fi

		if [[ $wo_node_name = "$wo_entity_name" || $node_name = common ]]; then
			sops "${sops_action[@]}" "$f"
			popd >/dev/null
			return
		fi

		node_dir=nodes/$entity_name/$node_name
	fi
	if [[ -n $valid ]]; then
		case $wo_node_name in
		secrets.yaml)
			if [[ -z $force ]]; then
				case $action in
				encrypt | edit)
					echo >&2 "Specify --force to $action node secrets"
					popd >/dev/null
					return 1
					;;
				decrypt)
					if [[ -n $in_place ]]; then
						echo >&2 'Specify --force to decrypt node secrets in-place'
						popd >/dev/null
						return 1
					fi
					;;
				esac
			fi
			;;
		ssh_host_*_key)
			if [[ -z $force ]]; then
				case $action in
				encrypt | edit)
					echo >&2 "Specify --force to $action node ssh host key"
					popd >/dev/null
					return 1
					;;
				decrypt)
					if [[ -n $in_place ]]; then
						echo >&2 'Specify --force to decrypt node ssh host key in-place'
						popd >/dev/null
						return 1
					fi
					;;
				esac
			fi
			sops "${sops_action[@]}" "$f"
			return
			;;
		esac

		local key
		case $action in
		decrypt | edit)
			key=build/$node_dir/age.key
			;;
		encrypt)
			key=build/$node_dir/age.pubkey
			;;
		esac
		if [[ ! -e $key ]]; then
			make -f - -f @out@/lib/nixverse/secrets.mk "$key" <<-EOF
				node_names += $node_name
				node_${node_name}_dir := $node_dir
			EOF
		fi
		case $action in
		decrypt | edit)
			SOPS_AGE_KEY=$(<"$key") sops "${sops_action[@]}" "$f"
			;;
		encrypt)
			sops "${sops_action[@]}" --age "$(<"$key")" "$f"
			;;
		esac
		popd >/dev/null
		return
	fi
	echo >&2 "No node.nix or group.nix exists for node $entity_name"
	popd >/dev/null
	return 1
}

eval_nix() {
	local flake=$1
	local expr=$2

	nix eval \
		--json \
		--no-eval-cache \
		--no-warn-dirty \
		--apply "{ nixverse, ... }: let inherit (nixverse) lib lib'; in $expr" \
		--show-trace \
		"$flake?submodules=1#."
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

find_node_file() {
	find_node

	local name=$1
	local files=("$node_dir/$name")
	if [[ -n $node_group ]]; then
		files+=("$node_base_dir/common/$name")
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

rsync_fs() {
	local target_dir=${1-}

	find_node
	local dirs=()
	if [[ -n $node_group ]]; then
		if [[ -d "$node_base_dir/common/fs" ]]; then
			dirs+=("$node_base_dir/common/fs")
		fi
		if [[ $node_secrets_base_dir != "$node_base_dir" ]] && [[ -d "$node_secrets_base_dir/common/fs" ]]; then
			dirs+=("$node_secrets_base_dir/common/fs")
		fi
	fi
	if [[ -d "$node_dir/fs" ]]; then
		dirs+=("$node_dir/fs")
	fi
	if [[ $node_secrets_dir != "$node_dir" && -d "$node_secrets_dir/fs" ]]; then
		dirs+=("$node_secrets_dir/fs")
	fi
	local uid
	local args=()
	if [[ ${#dirs[@]} != 0 ]]; then
		if [[ -z $ssh_dst ]] && uid=$(id --user) && [[ $uid != 0 ]]; then
			set -- sudo
		else
			set --
		fi
		"$@" rsync \
			--quiet \
			--recursive \
			--perms \
			--times \
			"${dirs[@]/%//}" \
			"${ssh_dst:+$ssh_dst:}${target_dir}/"
	fi

	dirs=()
	if [[ -d "$node_dir/home" ]]; then
		dirs+=("$node_dir/home")
	fi
	if [[ $node_secrets_dir != "$node_dir" ]] && [[ -d "$node_secrets_dir/home" ]]; then
		dirs+=("$node_secrets_dir/home")
	fi
	if [[ ${#dirs[@]} != 0 ]]; then
		find "${dirs[@]}" \
			-mindepth 2 \
			-maxdepth 2 \
			-name fs \
			-type d | (
			read -r dir
			user=$(basename "$(dirname "$dir")")
			case $node_os in
			darwin)
				if [[ $user = root ]]; then
					home=/var/root
					uid=0
					gid=0
				else
					home=$(dscl . -read "/Users/$user" NFSHomeDirectory)
					home=${home#NFSHomeDirectory: }
					uid=$(dscl . -read "/Users/$user" UniqueID)
					uid=${uid#UniqueID: }
					gid=$(dscl . -read "/Users/$user" PrimaryGroupID)
					gid=${gid#PrimaryGroupID: }
				fi
				;;
			nixos)
				IFS=: read -r uid gid home < <(
					awk -F: -v OFS=: -v "user=$user" \
						'$1 == user { print $3, $4, $6 }' /etc/passwd
				)
				;;
			*)
				echo >&2 "Unknown OS: $node_os"
				return 1
				;;
			esac
			if [[ -z $ssh_dst ]] && uid=$(id --user) && [[ $uid != 0 ]]; then
				set -- sudo
			else
				set --
			fi
			"$@" rsync \
				--quiet \
				--recursive \
				--perms \
				--times \
				--chown "$uid:$gid" \
				--numeric-ids \
				"$dir/" \
				"${ssh_dst:+$ssh_dst:}$target_dir$home/"
		)
	fi
}

make() {
	command make \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
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
			args=$(getopt -n nixverse -o '+h' --long '--help' -- "$@")
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
			args=$(getopt -n nixverse -o '+h' --long '--help' -- "$@")
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
cmd '' "$@"
