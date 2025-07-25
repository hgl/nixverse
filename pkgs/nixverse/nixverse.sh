#!@shell@
# shellcheck shell=bash
set -euo pipefail

PATH=@path@:$PATH
default_parallel=10

cmd_help() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse <command> [<argument>...]

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
Usage: nixverse node <command> [<argument>...]

Manage nodes.

Commands:
  install      install NixOS to nodes
  deploy       manage nodes
  value        show nodes or groups' meta configurations

Use "nixverse node <command> --help" for more information about a command.
EOF
	else
		cmd help node "$@"
	fi
}

cmd_help_node_install() {
	cat <<EOF
Usage: nixverse node install [<option>...] <node>...

Install one or more nodes.

Options:
  -p, --parallel <num>      number of nodes to install in parallel (default: 10)
  -h, --help                show this help
EOF
}

cmd_help_node_deploy() {
	cat <<EOF
Usage: nixverse node deploy [<option>...] <node>...

Deploy one or more nodes.

Options:
  -p, --parallel <num>      number of nodes to deploy in parallel (default: 10)
  -h, --help                show this help
EOF
}

cmd_help_eval() {
	cat <<EOF
Usage: nixverse eval [<option>...] <nix expression>

Evaluate a Nix expression, with these variables available:
  lib           nixpkgs lib
  lib'          your custom lib
  nodes         all nodes

Options:
  --raw         print in raw format (default)
  --json        print in JSON format
  -h, --help    show this help
EOF
}

cmd_help_secrets() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse secrets <command> [<argument>...]

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
Usage: nixverse secrets edit [<option>...] [<file>]

Edit an encrytped file.
With no <file>, edit top secrets.yaml.

Options:
  -h, --help    show this help
EOF
}

cmd_help_secrets_encrypt() {
	cat <<EOF
Usage: nixverse secrets encrypt [<option>...] [<file>] [<output>]

Encrypt a file.
With no <file> or <file> is -, encrypt standard input.
With no <output> or <output> is -, output to standard output.

Options:
  -i, --in-place      encrypt the file in-place
  -h, --help          show this help
EOF
}

cmd_help_secrets_decrypt() {
	cat <<EOF
Usage: nixverse secrets decrypt [<option>...] [<file>] [<output>]

Decrypt a file.
With no <file> or <file> is -, decrypt standard input.
With no <output> or <output> is -, output to standard output.

Options:
  -i, --in-place      decrypt the file in-place
  -h, --help          show this help
EOF
}

cmd_help_help() {
	cat <<EOF
Usage: nixverse help <command>

Show help for the command.
EOF
}

cmd_node() {
	cmd node "$@"
}

cmd_node_install() {
	local args
	args=$(getopt -n nixverse -o 'hp:' --long 'help,parallel:' -- "$@")
	eval set -- "$args"
	unset args

	local parallel=$default_parallel
	while true; do
		case $1 in
		-p | --parallel)
			parallel=$2
			if [[ $parallel = 0 || ! $parallel =~ ^[0-9]+$ ]]; then
				echo >&2 "$1 must specify a positive number"
				return 1
			fi
			shift 2
			;;
		-h | --help)
			cmd help node install
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
		cmd help node install >&2
		return 1
	fi

	local flake
	flake=$(find_flake)
	run_make "$flake" "$@"
	local json
	json=$(nixeval_nixverse json "$flake" "getNodeInstallJobs (lib.splitString \" \" \"$*\")")
	parallel "$parallel" "$json"
}

install_node() {
	set -euo pipefail

	local flake=$1
	local node_name=$2
	local node_dir=$3
	local target_host=$4
	local build_on_remote=$5
	local use_substitutes=$6
	local ssh_host_key=$7
	shift 7

	local args=()
	local sshOpt
	for sshOpt; do
		args+=(-o "$sshOpt")
	done
	if [[ -n $build_on_remote ]]; then
		args+=(--build-on remote)
	else
		args+=(--build-on local)
	fi
	if [[ -z $use_substitutes ]]; then
		args+=(--no-substitute-on-destination)
	fi

	if [[ -n $ssh_host_key ]]; then
		local tmpdir
		tmpdir=$(mktemp --directory)
		# shellcheck disable=SC2064
		trap "rm -rf '$tmpdir'" EXIT

		mkdir -p "$tmpdir/etc/ssh"
		cp -p \
			"$flake/build/$node_dir/ssh_host_ed25519_key" \
			"$ssh_host_key.pub" \
			"$tmpdir/etc/ssh"
		args+=(--extra-files "$tmpdir")
	fi

	nixos-anywhere --no-disko-deps \
		--flake "$flake?submodules=1#$node_name" \
		--generate-hardware-config nixos-generate-config "$flake/$node_dir/hardware-configuration.nix" \
		"${args[@]}" \
		"$target_host"
}
export -f install_node

cmd_node_build() {
	local args
	args=$(getopt -n nixverse -o 'hp:' --long 'help,parallel:' -- "$@")
	eval set -- "$args"
	unset args

	local parallel=$default_parallel
	while true; do
		case $1 in
		-p | --parallel)
			parallel=$2
			if [[ $parallel = 0 || ! $parallel =~ ^[0-9]+$ ]]; then
				echo >&2 "$1 must specify a positive number"
				return 1
			fi
			shift 2
			;;
		-h | --help)
			cmd help node build
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
		cmd help node build >&2
		return 1
	fi

	local flake
	flake=$(find_flake)
	run_make "$flake" "$@"
	local json
	json=$(nixeval_nixverse json "$flake" "getNodeBuildJobs (lib.splitString \" \" \"$*\")")
	parallel "$parallel" "$json"
}

build_node() {
	set -euo pipefail

	local flake=$1
	local node_name=$2
	local node_os=$3

	case $node_os in
	nixos)
		nix build --show-trace --no-link "$flake?submodules=1#nixosConfigurations.$node_name.config.system.build.toplevel"
		;;
	darwin)
		nix build --show-trace --no-link "$flake?submodules=1#darwinConfigurations.$node_name.system"
		;;
	*)
		echo >&2 "Unknown node OS: $node_os"
		return 1
		;;
	esac
}
export -f build_node

cmd_node_deploy() {
	local args
	args=$(getopt -n nixverse -o 'hp:' --long 'help,parallel:' -- "$@")
	eval set -- "$args"
	unset args

	local parallel=$default_parallel
	while true; do
		case $1 in
		-p | --parallel)
			parallel=$2
			if [[ $parallel = 0 || ! $parallel =~ ^[0-9]+$ ]]; then
				echo >&2 "$1 must specify a positive number"
				return 1
			fi
			shift 2
			;;
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
	run_make "$flake" "$@"
	local json
	json=$(nixeval_nixverse json "$flake" "getNodeDeployJobs (lib.splitString \" \" \"$*\")")
	parallel "$parallel" "$json"
}

deploy_node() {
	set -euo pipefail

	local flake=$1
	local node_name=$2
	local node_os=$3
	local target_host=$4
	local build_on_remote=$5
	local use_substitutes=$6
	local use_remote_sudo=$7
	local ssh_opts=$8

	case $node_os in
	nixos)
		local args=()
		if [[ -n $target_host ]]; then
			args+=(--target-host "$target_host")
			if [[ -n $build_on_remote ]]; then
				args+=(--build-host "$target_host")
			fi
		fi
		if [[ -n $use_remote_sudo ]]; then
			args+=(--use-remote-sudo)
		fi
		if [[ -n $use_substitutes ]]; then
			args+=(--use-substitutes)
		fi
		NIX_SSHOPTS=$ssh_opts nixos-rebuild switch \
			--flake "$flake?submodules=1#$node_name" \
			--fast \
			--show-trace \
			"${args[@]}"
		;;
	darwin)
		sudo darwin-rebuild switch \
			--flake "$flake?submodules=1#$node_name" \
			--show-trace
		;;
	*)
		echo >&2 "Unknown node OS: $node_os"
		return 1
		;;
	esac
}
export -f deploy_node

cmd_eval() {
	local args
	args=$(getopt -n nixverse -o 'h' --long 'help,raw,json' -- "$@")
	eval set -- "$args"
	unset args

	local format=raw
	while true; do
		case $1 in
		--raw)
			format=raw
			shift
			;;
		--json)
			format=json
			shift
			;;
		-h | --help)
			cmd help eval
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
		cmd help eval >&2
		return 1
	fi

	local flake
	flake=$(find_flake)

	local expr
	expr=$(
		cat <<EOF
let
  inherit (
    (flake.nixverse "$flake").evalData
  ) lib lib' nodes;
in
${@: -1}
EOF
	)

	nixeval "$format" "$flake" "$expr"
}

cmd_secrets() {
	local private_dir=''
	local force=''
	local sops_action=(--indent 2)
	local f flake path path_is_output sops_target_file

	local action=${1-}
	case $action in
	encrypt | decrypt)
		shift
		local args
		args=$(getopt -n nixverse -o 'hifn:m:' --long 'help,in-place,force,use-node-key:,use-master-key:' -- "$@")
		eval set -- "$args"
		unset args

		local in_place=''
		local use_node_key=''
		local use_master_key=''
		while true; do
			case $1 in
			-i | --in-place)
				in_place=1
				shift
				;;
			-f | --force)
				force=1
				shift
				;;
			-h | --help)
				cmd help secrets "$action"
				return
				;;
			-n | --use-node-key)
				use_node_key=$2
				shift 2
				;;
			-m | --use-master-key)
				use_master_key=$2
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

		f=${1:--}
		local output=${2:-}
		flake=$(find_flake)

		if [[ $f != - ]]; then
			f=$(realpath --no-symlinks --relative-base "$flake" "$f")
			if [[ $f = /* ]]; then
				echo >&2 "Input file not within the flake directory"
				return 1
			fi
			sops_target_file=$f
		else
			sops_target_file=/dev/stdin
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
				echo >&2 "Use --in-place to output to the same file"
				return 1
			fi
		fi
		if [[ $f = - && $output = - && -z $use_master_key && -z $use_node_key ]]; then
			echo >&2 "Speicify either --use-master-key or --use-node-key to $action stdin to stdout"
			return 1
		fi
		if [[ -z $use_master_key && -z $use_node_key ]]; then
			if [[ $f = - ]]; then
				path=$output
				path_is_output=1
			else
				path=$f
				path_is_output=''
			fi
		fi
		pushd "$flake" >/dev/null
		if [[ -d private ]]; then
			private_dir=private/
		fi
		sops_action+=("--$action")
		if [[ -n $in_place ]]; then
			sops_action+=(--in-place)
		elif [[ $output != - ]]; then
			sops_action+=(--output "$output")
		fi
		;;
	edit)
		shift
		local args
		args=$(getopt -n nixverse -o 'h' --long 'help,force' -- "$@")
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
			if [[ -e private/secrets.yaml && -e secrets.yaml ]]; then
				if [[ -e $f ]]; then
					echo >&2 "secrets exist in both $flake and $flake/private, delete one and try again"
					return 1
				fi
				mv secrets.yaml "$f"
			fi
			sops_target_file=$f
			path=$f
			path_is_output=''
		else
			f=$(realpath --no-symlinks --relative-base "$flake" "$f")
			if [[ $f = /* ]]; then
				echo >&2 "Input file is not within the flake directory"
				return 1
			fi
			sops_target_file=$f
			path=$f
			path_is_output=''
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

	local wo_private=${path#"$private_dir"}
	if [[ $wo_private = secrets.yaml ]]; then
		case $action in
		encrypt)
			if [[ -z $force ]]; then
				if [[ -z $path_is_output ]]; then
					echo >&2 'Specify --force to encrypt top secrets'
				else
					echo >&2 'Specify --force to encrypt to top secrets'
				fi
				popd >/dev/null
				return 1
			fi
			sops "${sops_action[@]}" "$sops_target_file"
			return
			;;
		decrypt)
			if [[ -z $force ]]; then
				if [[ -z $path_is_output && $in_place ]]; then
					echo >&2 'Specify --force to decrypt top secrets in-place'
					popd >/dev/null
					return 1
				elif [[ -n $path_is_output ]]; then
					echo >&2 'Specify --force to decrypt to top secrets'
					popd >/dev/null
					return 1
				fi
			fi
			sops "${sops_action[@]}" "$sops_target_file"
			return
			;;
		esac

		mkdir -p build
		if [[ ! -e $sops_target_file ]]; then
			(
				umask a=,u=rw
				cat <<EOF >build/secrets.yaml
node:
  name: value
EOF
			)
		else
			sops --decrypt --indent 2 --output build/secrets.yaml "$sops_target_file"
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
		nixeval_nixverse raw "$flake" "getSecretsMakefileVars (lib.splitString \" \" \"$entity_names\")" |
			make -f - -f @out@/lib/nixverse/secrets.mk
		sops --encrypt --indent 2 --output "$sops_target_file" build/secrets.yaml
		popd >/dev/null
		return
	fi

	if [[ -z ${wo_private#nodes} || -z ${wo_private#nodes/} ]]; then
		if [[ -z $path_is_output ]]; then
			echo >&2 "Can not $action the nodes directory"
			popd >/dev/null
			return 1
		else
			echo >&2 "Can not $action to the nodes directory"
			popd >/dev/null
			return 1
		fi
	fi
	local wo_nodes=${wo_private#nodes/}
	if [[ $wo_nodes = "$wo_private" ]]; then
		sops "${sops_action[@]}" "$sops_target_file"
		popd >/dev/null
		return
	fi
	local entity_name=${wo_nodes%%/*}
	if [[ -z ${wo_nodes#"$entity_name"} || -z ${wo_nodes#"$entity_name/"} ]]; then
		if [[ -z $path_is_output ]]; then
			echo >&2 "Can not $action $entity_name's node directory"
			popd >/dev/null
			return 1
		else
			echo >&2 "Can not $action to $entity_name's nodes directory"
			popd >/dev/null
			return 1
		fi
	fi
	local wo_entity_name=${wo_nodes#"$entity_name/"}

	local node_name node_dir wo_node_name
	if [[ -e private/nodes/$entity_name/node.nix || -e nodes/$entity_name/node.nix ]]; then
		node_name=$entity_name
		node_dir=nodes/$node_name
		wo_node_name=$wo_entity_name
	elif [[ -e private/nodes/$entity_name/group.nix || -e nodes/$entity_name/group.nix ]]; then
		node_name=${wo_entity_name%%/*}
		if [[ -z ${wo_entity_name#"$node_name"} || -z ${wo_entity_name#"$node_name/"} ]]; then
			if [[ -z $path_is_output ]]; then
				echo >&2 "Can not $action $entity_name's node directory"
				popd >/dev/null
				return 1
			else
				echo >&2 "Can not $action to $entity_name's nodes directory"
				popd >/dev/null
				return 1
			fi
		fi
		wo_node_name=${wo_entity_name#"$node_name/"}
		if [[ $wo_node_name = "$wo_entity_name" || $node_name = common ]]; then
			sops "${sops_action[@]}" "$sops_target_file"
			popd >/dev/null
			return
		fi
		node_dir=nodes/$entity_name/$node_name
	else
		echo >&2 "Can not $action for node $entity_name which contains neither node.nix or group.nix"
		popd >/dev/null
		return 1
	fi

	case $wo_node_name in
	secrets.yaml)
		if [[ -z $force ]]; then
			case $action in
			encrypt)
				if [[ -z $path_is_output ]]; then
					echo >&2 "Specify --force to encrypt node $node_name's secrets"
				else
					echo >&2 "Specify --force to encrypt to node $node_name's secrets"
				fi
				popd >/dev/null
				return 1
				;;
			decrypt)
				if [[ -z $path_is_output && -n $in_place ]]; then
					echo >&2 "Specify --force to decrypt node $node_name's secrets in-place"
					popd >/dev/null
					return 1
				elif [[ -n $path_is_output ]]; then
					echo >&2 "Specify --force to decrypt to node $node_name's secrets in-place"
					popd >/dev/null
					return 1
				fi
				;;
			edit)
				echo >&2 "Specify --force to edit node $node_name's secrets"
				popd >/dev/null
				return 1
				;;
			esac
		fi
		;;
	ssh_host_*_key)
		if [[ -z $force ]]; then
			case $action in
			encrypt)
				if [[ -z $path_is_output ]]; then
					echo >&2 "Specify --force to encrypt node $node_name's ssh host key"
				else
					echo >&2 "Specify --force to encrypt to node $node_name's ssh host key"
				fi
				popd >/dev/null
				return 1
				;;
			decrypt)
				if [[ -n $in_place ]]; then
					echo >&2 "Specify --force to decrypt node $node_name's ssh host key in-place"
					popd >/dev/null
					return 1
				fi
				;;
			edit)
				echo >&2 "Specify --force to $action node $node_name's ssh host key"
				popd >/dev/null
				return 1
				;;
			esac
		fi
		sops "${sops_action[@]}" "$sops_target_file"
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
			node_names := $node_name
			node_${node_name}_dir := $node_dir
		EOF
	fi
	case $action in
	decrypt | edit)
		SOPS_AGE_KEY=$(<"$key") sops "${sops_action[@]}" "$sops_target_file"
		;;
	encrypt)
		sops "${sops_action[@]}" --age "$(<"$key")" "$sops_target_file"
		;;
	esac
	popd >/dev/null
}

nixeval() {
	local format=$1
	local flake=$2
	local expr=$3

	local args=()
	case $format in
	json | raw)
		args+=("--$format")
		;;
	*)
		echo >&"Unknown format: $format"
		return 1
		;;
	esac

	expr=$(
		cat <<EOF
flake:
  if builtins.isFunction flake.nixverse or null then
  	($expr)
  else
  	builtins.abort "not inside a flake directory with nixverse loaded"
EOF
	)
	nix eval \
		--no-warn-dirty \
		--apply "$expr" \
		--show-trace \
		"${args[@]}" \
		"$flake?submodules=1#."
}

nixeval_nixverse() {
	local format=$1
	local flake=$2
	local expr=$3

	nixeval "$format" "$flake" "with flake.nixverse \"$flake\"; $expr"
}

nix() {
	command nix --extra-experimental-features 'nix-command flakes' "$@"
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

run_make() {
	local flake=$1
	shift

	if [[ ! -e $flake/Makefile ]] && [[ ! -e $flake/private/Makefile ]]; then
		return
	fi

	local mk
	mk=$(nixeval_nixverse raw "$flake" nodesMakefileVars)

	local targets
	targets=$(nixeval_nixverse raw "$flake" "getNodesMakefileTargets (lib.splitString \" \" \"$*\")")
	local nproc
	nproc=$(nproc)
	# shellcheck disable=SC2086
	make -j $((nproc + 1)) -C "$flake" -f - $targets <<-EOF
		$mk
		-include Makefile
		-include private/Makefile
	EOF
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
cmd '' "$@"
