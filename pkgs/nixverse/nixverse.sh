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

cmd_help_node_build() {
	cat <<EOF
Usage: nixverse node build [<option>...] <node>...

Run one or more nodes' makefile and build the configurations.

Options:
  -p, --parallel <num>      number of nodes to install in parallel (default: 10)
  -h, --help                show this help
EOF
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
  inputs        flake inputs
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
  lib = flake.nixverse.inputs.nixpkgs-unstable.lib;
  lib' = flake.lib;
  inherit (flake.nixverse) inputs nodes;
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
  edit         edit the secrets
  eval         evaluate a Nix expression against the secrets

Use "nixverse secrets <command> --help" for more information about a command.
EOF
	else
		cmd help secrets "$@"
	fi
}
cmd_secrets() {
	cmd secrets "$@"
}

cmd_help_secrets_edit() {
	cat <<EOF
Usage: nixverse secrets edit [<option>...]

Edit the secrets file.

Options:
  -h, --help    show this help
EOF
}
cmd_secrets_edit() {
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

	local flake
	flake=$(find_flake)
	pushd "$flake" >/dev/null

	local private_dir=''
	if [[ -d private ]]; then
		private_dir=private/
	fi

	local ssecrets_file_exist=1
	local public_secrets_exist=''
	local private_secrets_exist=''
	if [[ -e secrets.yaml ]]; then
		public_secrets_exist=1
	fi
	if [[ -e private/secrets.yaml ]]; then
		private_secrets_exist=1
	fi
	if [[ -n $public_secrets_exist && -n $private_secrets_exist ]]; then
		echo >&2 "Both $flake/secrets.yaml and $flake/private/secrets.yaml exist, only one is allowed"
		return 1
	elif [[ -n $public_secrets_exist && -n $private_dir ]]; then
		mv secrets.yaml private/secrets.yaml
		git add private/secrets.yaml
	elif [[ -z $public_secrets_exist && -z $private_secrets_exist ]]; then
		ssecrets_file_exist=''
	fi
	local secrets_file=${private_dir}secrets.yaml

	mkdir -p build
	if [[ -z $ssecrets_file_exist ]]; then
		cp @out@/lib/nixverse/secrets/template.nix build/secrets.nix
		chmod a=,u=rw build/secrets.nix
	else
		sops --decrypt --output-type binary \
			--output build/secrets.nix "$secrets_file"
	fi

	${SOPS_EDITOR:-${EDITOR:-vi}} build/secrets.nix
	(
		rm -f build/secrets.json
		umask a=,u=rw
		eval_secrets "$flake" <<EOF >build/secrets.json
let
  inherit (flake.nixverse) lib lib' entities;
  nodesSecrets =
    let
      removeHiddenSecrets = attrs:
        if lib.isAttrs attrs then
          lib.concatMapAttrs (
            k: v:
            let
              removed = removeHiddenSecrets v;
            in
            lib.optionalAttrs (!lib.hasPrefix "_" k && removed != {}) { \${k} = removed; }
          )  attrs
        else if lib.isList attrs then
          map removeHiddenSecrets attrs
        else
          attrs;
    in
    lib.concatMapAttrs (
      entityName: entitySecrets:
      lib.optionalAttrs (entities.\${entityName}.type == "node") {
        \${entityName} = removeHiddenSecrets entitySecrets;
      }
    ) secrets.nodes;
in
builtins.toJSON {
  nodes = nodesSecrets;
  makefile = ''
    all: \${lib.concatStringsSep "\\\\\\n" (lib'.concatMapAttrsToList (
      nodeName: _:
      let
        node = entities.\${nodeName};
      in
      [
        "\$(private_dir)\${node.dir}/secrets.yaml"
        "build/\${node.dir}/ssh_host_ed25519_key"
        "\$(private_dir)\${node.dir}/ssh_host_ed25519_key"
        "\$(private_dir)\${node.dir}/ssh_host_ed25519_key.pub"
      ]
    ) nodesSecrets)}
    \${lib.concatStringsSep "\\\\\\n" (lib'.concatMapAttrsToList (
      nodeName: _:
      let
        node = entities.\${nodeName};
      in
      [
        "\$(private_dir)\${node.dir}"
        "build/\${node.dir}"
      ]
    ) nodesSecrets)}:
    	mdir -p \$@
  '';
}
EOF
	)
	trap 'rm -f build/secrets.json' EXIT
	yq --raw-output .makefile build/secrets.json |
		make --silent -f @out@/lib/nixverse/secrets/Makefile -f -
	if [[ -z $ssecrets_file_exist ]]; then
		:
	elif
		sops --decrypt --output-type binary "$secrets_file" |
			cmp --quiet - build/secrets.nix
	then
		popd >/dev/null
		return
	elif [[ $? = 1 ]]; then
		:
	else
		exit 1
	fi
	sops --encrypt --output-type yaml --indent 2 \
		--output "$secrets_file" build/secrets.nix
	popd >/dev/null
}

cmd_help_secrets_eval() {
	cat <<EOF
Usage: nixverse secrets eval [<option>...] <nix expression>

Evaluate a Nix expression, with these variables available:
  lib           nixpkgs lib
  lib'          your custom lib
  inputs        flake inputs
  nodes         all nodes
  secrets       all secrets

Options:
  -h, --help    show this help
EOF
}
cmd_secrets_eval() {
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
		cmd help secrets eval >&2
		return 1
	fi

	local flake
	flake=$(find_flake)

	eval_secrets "$flake" <<EOF
let
  lib = flake.nixverse.inputs.nixpkgs-unstable.lib;
  lib' = flake.lib;
  inherit (flake.nixverse) inputs nodes;
in
$*
EOF
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
  toTargets = map (name: "nodes/\${name}");
  allNodeNames = lib.attrNames (
    lib.concatMapAttrs (
      entityName: entity:
      {
        node = { \${entityName} = true; };
        group = lib.mapAttrs (nodeName: node: true) entity.nodes;
      }.\${entity.type}
    ) entities
  );
  makefile = [
    ".PHONY: \${toString (toTargets allNodeNames)}"
  ] ++ lib'.concatMapAttrsToList (
    entityName: entity:
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
lib.concatLines ([ (toString (toTargets nodeNames)) ] ++ makefile)
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
nodeNames = lib.attrNames (
  lib'.concatMapListToAttrs (
    entityName:
    let
      entity = entities.\${entityName};
    in
    assert lib.assertMsg (lib.hasAttr entityName entities) "Unknown node \${entityName}";
    {
      node = { \${entityName} = true; };
      group = lib.mapAttrs (nodeName: node: true) entity.nodes;
    }.\${entity.type}
  ) entityNames
);
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

eval_secrets() {
	local flake=$1
	shift

	local private_dir=''
	if [[ -d private ]]; then
		private_dir=private/
	fi
	local secrets_file=${private_dir}secrets.yaml
	local secrets
	secrets=$(sops --decrypt --output-type binary "$secrets_file")

	eval_flake "$flake" <<EOF
let
  secrets =
    let
      inherit (flake.nixverse) lib lib' entities nodes inputs;
      raw = lib'.call ($secrets) {
        lib = inputs.nixpkgs-unstable.lib;
        lib' = flake.lib;
        inherit secrets inputs nodes;
      };
      evaled = lib.evalModules {
        modules = [
          ($(<@out@/lib/nixverse/secrets/module.nix))
          { config = raw; }
        ];
      };
      nodeNameAttrs = lib.concatMapAttrs (
        entityName: _:
        let
          entity = entities.\${entityName};
        in
        {
          node = {
            \${entityName} = true;
          };
          group = lib.mapAttrs (nodeName: node: true) entity.nodes;
        }.\${entity.type}
      ) evaled.config.nodes;
      nodesSecrets = lib.mapAttrs (
        nodeName: _:
        let
          node = entities.\${nodeName};
        in
        node.recursiveFoldParentNames (
          acc: parentNames: _:
          lib.recursiveUpdate (
            builtins.foldl' (
              acc: parentName:
              lib.recursiveUpdate acc evaled.config.nodes.\${parentName} or {}
            ) {} parentNames
          ) acc
        ) evaled.config.nodes.\${nodeName} or {}
      ) nodeNameAttrs;
    in
    evaled.config // {
      nodes = evaled.config.nodes // nodesSecrets;
    };
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
