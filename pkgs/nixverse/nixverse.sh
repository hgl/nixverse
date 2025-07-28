#!@shell@
# shellcheck shell=bash
set -euo pipefail

export PATH=@path@:$PATH
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
  eval         eval a nix expression against nodes

Use "nixverse node <command> --help" for more information about a command.
EOF
	else
		cmd help node "$@"
	fi
}

cmd_node() {
	cmd node "$@"
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
	make_flake "$flake" "$@"
	parallel-run "$parallel" <(
		eval_nixverse "$flake" "$@" <<EOF
builtins.toJSON (map (
  nodeName:
  let
    node = entities.\${nodeName};
    buildOn = "--build-on \${if node.install.buildOnRemote then "remote" else "local"}";
    useSubstitutes = lib.optionalString (!node.install.useSubstitutes) "--no-substitute-on-destination";
    extraFiles = lib.optionalString (node.sshHostKeyPath != null) "--extra-files \\"\$tmpdir\\"";
    cpFiles = lib.optionals (node.sshHostKeyPath != null) ''
      tmpdir=\$(mktemp --directory)
      trap "rm -rf '\$tmpdir'" EXIT
      mkdir -p "\$tmpdir/etc/ssh"
      cp -p '$flake/build/\${node.dir}/ssh_host_ed25519_key' '\${node.sshHostKeyPath}.pub' "\$tmpdir/etc/ssh"
    '';
  in
  assert lib.assertMsg (
    node.os != "darwin"
  ) "Deploy to the darwin node \${nodeName} directlt to install nix-darwin";
  assert lib.assertMsg (
    node.install.targetHost != null
  ) "Missing meta configuration install.targetHost for node \${nodeName}";
  assert lib.assertMsg (
    node.diskConfigPaths != [ ]
  ) "Missing disk-config.nix for node \${nodeName}";
  {
    name = nodeName;
    command = ''
      set -e
      \${cpFiles}
      nixos-anywhere --no-disko-deps \\
        --flake '$flake?submodules=1#\${nodeName}' \\
        --generate-hardware-config nixos-generate-config '$flake/\${node.dir}/hardware-configuration.nix' \\
        \${buildOn} \${useSubstitutes} \${extraFiles} \${lib.escapeShellArg node.install.targetHost}
    '';
  }
) nodeNames)
EOF
	)
}

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
	make_flake "$flake" "$@"
	parallel-run "$parallel" <(
		eval_nixverse "$flake" "$@" <<EOF
builtins.toJSON (map (
  nodeName:
  let
    node = entities.\${nodeName};
    attrPath = {
      nixos = "nixosConfigurations.\${nodeName}.config.system.build.toplevel";
      darwin = "darwinConfigurations.\${nodeName}.system";
    }.\${node.os};
  in
  {
    name = nodeName;
    command = "nix build --no-link --show-trace '$flake?submodules=1#\${attrPath}'";
  }
) nodeNames)
EOF
	)
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

	which darwin-rebuild
	local flake
	flake=$(find_flake)
	make_flake "$flake" "$@"
	parallel-run "$parallel" <(
		eval_nixverse "$flake" "$@" <<EOF
builtins.toJSON (map (
  nodeName:
  let
    node = entities.\${nodeName};
    targetHost = lib.optionalString (node.deploy.targetHost != null) "--target-host \${lib.escapeShellArg node.deploy.targetHost}";
    buildHost = lib.optionalString (node.deploy.targetHost != null && node.deploy.buildOnRemote) "--build-host \${lib.escapeShellArg node.deploy.targetHost}";
    useSubstitutes = lib.optionalString (node.deploy.useSubstitutes) "--use-substitutes";
    useRemoteSudo = lib.optionalString (node.deploy.useRemoteSudo) "--use-remote-sudo";
    sshOpts = "NIX_SSHOPTS=\${lib.escapeShellArg (map (opt: "-o \${lib.escapeShellArg opt}") node.deploy.sshOpts)}";
    common = "--flake \${lib.escapeShellArg "$flake?submodules=1#\${nodeName}"} --show-trace";
  in
  assert lib.assertMsg (lib.length nodeNames != 1 -> node.deploy.targetHost != null)
    "Deploying multiple local nodes in parallel is not allowed";
  {
    name = nodeName;
    command = {
      nixos = "\${sshOpts} nixos-rebuild-ng switch \${targetHost} \${buildHost} \${useSubstitutes} \${useRemoteSudo} \${common}";
      darwin = "sudo darwin-rebuild switch \${common}";
    }.\${node.os};
  }
) nodeNames)
EOF
	)
}

cmd_help_eval() {
	cat <<EOF
Usage: nixverse eval [<option>...] <nix expression>

Evaluate a Nix expression, with these variables available:
  lib           nixpkgs lib
  lib'          your custom lib
  nodes         all nodes

Options:
  -h, --help    show this help
EOF
}

cmd_eval() {
	local args
	args=$(getopt -n nixverse -o 'h' --long 'help' -- "$@")
	eval set -- "$args"
	unset args

	while true; do
		case $1 in
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

	eval_flake "$flake" <<EOF
let
  inherit (flake.nixverse) lib nodes;
  lib' = flake.lib;
in
$*
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

cmd_help_help() {
	cat <<EOF
Usage: nixverse help <command>

Show help for the command.
EOF
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

make_flake() {
	local flake=$1
	shift

	if [[ ! -e $flake/Makefile ]] && [[ ! -e $flake/private/Makefile ]]; then
		return
	fi

	{
		local targets
		read -r targets
		local makefile
		makefile=$(cat)
	} < <(
		eval_nixverse "$flake" "$@" <<EOF
let
  targets = map (name: "nodes/\${name}") nodeNames;
  makefile = [
    ".PHONY: \${toString (map (nodeName: "nodes/\${nodeName}") nodeNames)}"
  ] ++ lib'.concatMapAttrsToList (entityName: entity:
    {
      node = [
        "node_\${entityName}_os := \${entity.os}"
        "node_\${entityName}_channel := \${entity.channel}"
      ];
      group = [
        "\${entityName}_node_names := \${toString (lib.attrNames entity.nodes)}"
      ];
    }.\${entity.type}
  ) entities;
in
lib.concatLines ([ (toString targets) ] ++ makefile)
EOF
	)

	local nproc
	nproc=$(nproc)

	local system
	system=$(nix eval --raw --expr 'builtins.currentSystem' --impure)

	local path
	path=$(
		eval_nixverse "$flake" <<EOF
lib.makeBinPath flake.nixverse.makefileInputs.$system or []
EOF
	)

	(
		export PATH=$path:$PATH
		# shellcheck disable=SC2086
		make -j $((nproc + 1)) -C "$flake" -f <(
			cat <<EOF
$makefile
-include Makefile
-include private/Makefile
EOF
		) $targets
	)
}

eval_flake() {
	local flake=$1
	shift

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

	nix eval \
		--no-warn-dirty \
		--apply "$expr" \
		--show-trace \
		--raw \
		"$flake?submodules=1#."
}

eval_nixverse() {
	local flake=$1
	shift

	local node_names=''
	if [[ $# != 0 ]]; then
		node_names=$(
			cat <<EOF
    entityNames = lib.split " " "$*";
    nodeNames = lib.concatMap (entityName:
      let
        entity = entities.\${entityName};
      in
      assert lib.assertMsg (lib.hasAttr entityName entities) "Unknown node \${entityName}";
      {
        node = [ entityName ];
        group = lib.attrNames entity.nodes;
      }.\${entity.type}
    ) entityNames;
EOF
		)
	fi

	eval_flake "$flake" <<EOF
  let
    inherit (flake.nixverse) lib lib' entities;
$node_names
  in
  $(cat)
EOF
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

cmd '' "$@"
