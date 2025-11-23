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

	local sops_config
	sops_config=$(find_sops_config "$flake")

	decrypt_to_secrets_nix --flake "$flake" "$sops_config"

	local dir
	dir=$(
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    lib
    getNodeNames
    getNodesMakefile
    getSecrets
    getSecretsMakefile
    getFSEntries
    userMakefile
    getNodeInstallCommands
    ;
  entityNames = lib.splitString " " "$*";
  nodeNames = getNodeNames entityNames;
  secrets = getSecrets ($(<"$secrets_nix"));
  secretsNodeNames = lib.intersectLists nodeNames secrets.nodeNames;
in
{
  "nodes.mk" = getNodesMakefile nodeNames;
  "secrets.mk" = getSecretsMakefile secretsNodeNames;
  fsEntries = getFSEntries nodeNames;
  "user.mk" = userMakefile;
  "cmds.json" = builtins.toJSON (
    getNodeInstallCommands nodeNames "$flake"
  );
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	local nproc
	nproc=$(nproc)

	set -- "${@/#/nodes/}"
	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
		-f @out@/lib/nixverse/Makefile \
		-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
		-f <(fs_makefile <"$dir/fsEntries") \
		"$@"

	if [[ -e $flake/Makefile || -e $flake/private/Makefile ]]; then
		nix run "$flake#make" -- -j $((nproc + 1)) -C "$flake" -f <(
			cat <<EOF
include $dir/user.mk
-include Makefile
-include private/Makefile
EOF
		) "$@"
	fi

	parallel-run "$parallel" "$dir/cmds.json"
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

	local sops_config
	sops_config=$(find_sops_config "$flake")

	decrypt_to_secrets_nix --flake "$flake" "$sops_config"

	local dir
	dir=$(
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    lib
    getNodeNames
    getNodesMakefile
    getSecrets
    getSecretsMakefile
    getFSEntries
    userMakefile
    getNodeBuildCommands
    ;
  entityNames = lib.splitString " " "$*";
  nodeNames = getNodeNames entityNames;
  secrets = getSecrets ($(<"$secrets_nix"));
  secretsNodeNames = lib.intersectLists nodeNames secrets.nodeNames;
in
{
  "nodes.mk" = getNodesMakefile nodeNames;
  "secrets.mk" = getSecretsMakefile secretsNodeNames;
  fsEntries = getFSEntries nodeNames;
  "user.mk" = userMakefile;
  "cmds.json" = builtins.toJSON (
    getNodeBuildCommands nodeNames
  );
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	local nproc
	nproc=$(nproc)

	set -- "${@/#/nodes/}"
	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
		-f @out@/lib/nixverse/Makefile \
		-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
		-f <(fs_makefile <"$dir/fsEntries") \
		"$@"

	if [[ -e $flake/Makefile || -e $flake/private/Makefile ]]; then
		nix run "$flake#make" -- -j $((nproc + 1)) -C "$flake" -f <(
			cat <<EOF
include $dir/user.mk
-include Makefile
-include private/Makefile
EOF
		) "$@"
	fi

	parallel-run "$parallel" "$dir/cmds.json"
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

	local sops_config
	sops_config=$(find_sops_config "$flake")

	decrypt_to_secrets_nix --flake "$flake" "$sops_config"

	local dir
	dir=$(
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    lib
    getNodeNames
    getNodesMakefile
    getSecrets
    getSecretsMakefile
    getFSEntries
    userMakefile
    getNodeDeployCommands
    ;
  entityNames = lib.splitString " " "$*";
  nodeNames = getNodeNames entityNames;
  secrets = getSecrets ($(<"$secrets_nix"));
  secretsNodeNames = lib.intersectLists nodeNames secrets.nodeNames;
in
{
  "nodes.mk" = getNodesMakefile nodeNames;
  "secrets.mk" = getSecretsMakefile secretsNodeNames;
  fsEntries = getFSEntries nodeNames;
  "user.mk" = userMakefile;
  "cmds.json" = builtins.toJSON (
    getNodeDeployCommands nodeNames "$flake" "@out@"
  );
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	local nproc
	nproc=$(nproc)

	set -- "${@/#/nodes/}"
	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
		-f @out@/lib/nixverse/Makefile \
		-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
		-f <(fs_makefile <"$dir/fsEntries") \
		"$@"

	if [[ -e $flake/Makefile || -e $flake/private/Makefile ]]; then
		nix run "$flake#make" -- -j $((nproc + 1)) -C "$flake" -f <(
			cat <<EOF
include $dir/user.mk
-include Makefile
-include private/Makefile
EOF
		) "$@"
	fi

	parallel-run "$parallel" "$dir/cmds.json"
}

cmd_node_rsync() {
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
			cmd help node rsync
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
		cmd help node rsync >&2
		return 1
	fi

	local flake
	flake=$(find_flake)

	local sops_config
	sops_config=$(find_sops_config "$flake")

	decrypt_to_secrets_nix --flake "$flake" "$sops_config"

	local dir
	dir=$(
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    lib
    getNodeNames
    getNodesMakefile
    getSecrets
    getSecretsMakefile
    getFSEntries
    userMakefile
    getNodeRsyncCommands
    ;
  entityNames = lib.splitString " " "$*";
  nodeNames = getNodeNames entityNames;
  secrets = getSecrets ($(<"$secrets_nix"));
  secretsNodeNames = lib.intersectLists nodeNames secrets.nodeNames;
in
{
  "nodes.mk" = getNodesMakefile nodeNames;
  "secrets.mk" = getSecretsMakefile secretsNodeNames;
  fsEntries = getFSEntries nodeNames;
  "user.mk" = userMakefile;
  "cmds.json" = builtins.toJSON (
    getNodeRsyncCommands nodeNames "$flake" "@out@"
  );
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	local nproc
	nproc=$(nproc)

	set -- "${@/#/nodes/}"
	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
		-f @out@/lib/nixverse/Makefile \
		-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
		-f <(fs_makefile <"$dir/fsEntries") \
		"$@"

	if [[ -e $flake/Makefile || -e $flake/private/Makefile ]]; then
		nix run "$flake#make" -- -j $((nproc + 1)) -C "$flake" -f <(
			cat <<EOF
include $dir/user.mk
-include Makefile
-include private/Makefile
EOF
		) "$@"
	fi

	parallel-run "$parallel" "$dir/cmds.json"
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

	local expr=$1

	local flake
	flake=$(find_flake)

	eval_flake "$flake" <<EOF
let
  lib = flake.nixverse.inputs.nixpkgs-unstable.lib;
  lib' = flake.lib;
  inherit (flake.nixverse) inputs;
  nodes = flake.nixverse.userEntities;
in
$expr
EOF
}

cmd_help_secrets() {
	if [[ -z ${1-} ]]; then
		cat <<EOF
Usage: nixverse secrets <command> [<argument>...]

Manage secrets

Commands:
  edit         edit the secrets
  encrypt      encrypt a file using either the master or node age pubkey
  decrypt      decrypt a file using either the master or node age pubkey
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

	local secrets_yaml
	secrets_yaml=$(find_secrets_yaml -i "$flake")

	local sops_config
	sops_config=$(find_sops_config "$flake")

	pushd "$flake" >/dev/null
	if [[ -z $secrets_yaml ]]; then
		mkdir -p build
		cp @out@/lib/nixverse/secrets-template.nix "$secrets_nix"
		chmod a=,u=rw "$secrets_nix"
	else
		decrypt_to_secrets_nix "$sops_config" "$secrets_yaml"
	fi
	${SOPS_EDITOR:-${EDITOR:-vi}} "$secrets_nix"
	if [[ -z $secrets_yaml ]]; then
		if [[ -d private ]]; then
			secrets_yaml=$flake/private/secrets.yaml
		else
			secrets_yaml=$flake/secrets.yaml
		fi
		: >"$secrets_yaml"
		if git rev-parse --is-inside-work-tree >/dev/null; then
			git add --intent-to-add --force "$secrets_yaml"
		fi
	fi

	local dir
	dir=$(
		umask a=,u=rw
		eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    getNodesMakefile
    getSecrets
    getSecretsMakefile
    getNodesSecrets
    ;
  secrets = getSecrets ($(<"$secrets_nix"));
in
{
  "nodes.mk" = getNodesMakefile secrets.nodeNames;
  "secrets.mk" = getSecretsMakefile secrets.nodeNames;
  targets = toString (map (name: "nodes/\${name}") secrets.nodeNames);
  "secrets.json" = builtins.toJSON secrets.config;
  nodes = getNodesSecrets secrets.config secrets.nodeNames;
}
EOF
	)
	# shellcheck disable=SC2064
	trap_add "rm -r '$dir'" EXIT

	mv "$dir/secrets.json" "$flake/build/secrets.json"

	local f
	for f in "$dir"/nodes/*/secrets.json; do
		mv "$f" "build${f#"$dir"}"
	done

	local nproc
	nproc=$(nproc)
	local targets
	targets=$(<"$dir/targets")
	# shellcheck disable=SC2086
	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
		-f @out@/lib/nixverse/Makefile \
		-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
		$targets

	sops --config "$sops_config" --encrypt --output-type yaml --indent 2 \
		--output "$secrets_yaml" "$secrets_nix"
}

cmd_help_secrets_encrypt() {
	cat <<EOF
Usage: nixverse secrets encrypt [<option>...] <file>

Encrypt the file using the master age pubkey.
If <file> is -, encrypt the stdin.

Options:
  -n, --node <name>       encrypt using the node's SSH host key instead
  --in-type <type>        type of the input file: yaml, json, binary or dotenv
  --out-type <type>       type of the output file: yaml, json, binary or dotenv
  -i, --in-place          encrypt the file in-place
  -o, --out <file>        output to <file> instead of stdout
  -h, --help              show this help
EOF
}
cmd_secrets_encrypt() {
	local args
	args=$(getopt -n nixverse -o 'hn:io:' --long 'help,node:,--in-type:,--out-type:,in-place,indent:,out:' -- "$@")
	eval set -- "$args"
	unset args

	local node_name=''
	local in_type=''
	local out_type=''
	local in_place=''
	local indent=2
	local out=''
	while true; do
		case $1 in
		-n | --node)
			node_name=$2
			shift 2
			;;
		--in-type)
			in_type=$2
			shift 2
			;;
		--out-type)
			out_type=$2
			shift 2
			;;
		-i | --in-place)
			in_place=1
			shift
			;;
		--indent)
			indent=$1
			shift 2
			;;
		-o | --out)
			out=$2
			shift 2
			;;
		-h | --help)
			cmd help secrets encrypt
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
	if [[ -n $out && -n $in_place ]]; then
		echo >&2 "--in-place and --out can not both be specified"
		exit 1
	fi
	if [[ $out = - ]]; then
		out=''
	fi

	if [[ $# = 0 ]]; then
		cmd help secrets encrypt >&2
		return 1
	elif [[ $# -gt 1 ]]; then
		echo >&2 "Only one file can be specified"
		exit 1
	fi
	local file=$1

	local flake
	flake=$(find_flake)

	local sops_config
	sops_config=$(find_sops_config "$flake")

	local pubkey=''
	if [[ -n $node_name ]]; then
		pubkey=build/nodes/$node_name/age.pubkey
		local dir
		dir=$(
			eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    validNodeName
    getNodesMakefile
    getSecretsMakefile
	;
  nodeName = "$node_name";
in
assert validNodeName nodeName;
{
  "nodes.mk" = getNodesMakefile [ nodeName ];
  "secrets.mk" = getSecretsMakefile [ nodeName ];
}
EOF
		)
		# shellcheck disable=SC2064
		trap_add "rm -r '$dir'" EXIT

		local nproc
		nproc=$(nproc)

		SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
			-f @out@/lib/nixverse/Makefile \
			-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
			"$pubkey"
	fi

	local args=(--indent "$indent")
	if [[ -n $pubkey ]]; then
		args+=(--age "$(<"$pubkey")")
	fi
	if [[ -n $in_type ]]; then
		args+=(--input-type "$in_type")
	fi
	if [[ -n $out_type ]]; then
		args+=(--output-type "$out_type")
	fi
	if [[ -n $in_place ]]; then
		args+=(--in-place)
	elif [[ -n $out ]]; then
		args+=(--output "$out")
	fi
	if [[ $file = - ]]; then
		file=/dev/stdin
	fi
	sops --config "$sops_config" --encrypt "${args[@]}" "$file"
}

cmd_help_secrets_decrypt() {
	cat <<EOF
Usage: nixverse secrets decrypt [<option>...] <file>

Decrypt the file using the master age key.
If <file> is -, decrypt the stdin.

Options:
  -n, --node <name>       decrypt using the node's SSH host key instead
  --in-type <type>        type of the input file: yaml, json, binary or dotenv
  -i, --in-place          decrypt the file in-place
  -o, --out <file>        output to <file> instead of stdout
  -h, --help              show this help
EOF
}
cmd_secrets_decrypt() {
	local args
	args=$(getopt -n nixverse -o 'hn:io:' --long 'help,node:,--in-type:,--out-type:,in-place,out:' -- "$@")
	eval set -- "$args"
	unset args

	local node_name=''
	local in_type=''
	local out_type=''
	local in_place=''
	local out=''
	while true; do
		case $1 in
		-n | --node)
			node_name=$2
			shift 2
			;;
		--in-type)
			in_type=$2
			shift 2
			;;
		--out-type)
			out_type=$2
			shift 2
			;;
		-i | --in-place)
			in_place=1
			shift
			;;
		-o | --out)
			out=$2
			shift 2
			;;
		-h | --help)
			cmd help secrets decrypt
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
	if [[ -n $out && -n $in_place ]]; then
		echo >&2 "--in-place and --out can not both be specified"
		exit 1
	fi
	if [[ $out = - ]]; then
		out=''
	fi

	if [[ $# = 0 ]]; then
		cmd help secrets decrypt >&2
		return 1
	elif [[ $# -gt 1 ]]; then
		echo >&2 "Only one file can be specified"
		exit 1
	fi
	local file=$1

	local flake
	flake=$(find_flake)

	local sops_config
	sops_config=$(find_sops_config "$flake")

	local key=''
	if [[ -n $node_name ]]; then
		key=build/nodes/$node_name/age.key
		local dir
		dir=$(
			eval_flake --write "$flake" <<EOF
let
  inherit (flake.nixverse)
    validNodeName
    getNodesMakefile
    getSecretsMakefile
    ;
  nodeName = "$node_name";
in
assert validNodeName nodeName;
{
  "nodes.mk" = getNodesMakefile [ nodeName ];
  "secrets.mk" = getSecretsMakefile [ nodeName ];
}
EOF
		)
		# shellcheck disable=SC2064
		trap_add "rm -r '$dir'" EXIT

		local nproc
		nproc=$(nproc)

		SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" \
			-f @out@/lib/nixverse/Makefile \
			-f "$dir/nodes.mk" -f "$dir/secrets.mk" \
			"$key"
	fi

	local args=()
	if [[ -n $in_type ]]; then
		args+=(--input-type "$in_type")
	fi
	if [[ -n $out_type ]]; then
		args+=(--output-type "$out_type")
	fi
	if [[ -n $in_place ]]; then
		args+=(--in-place)
	elif [[ -n $out ]]; then
		args+=(--output "$out")
	fi
	if [[ $file = - ]]; then
		file=/dev/stdin
	fi
	(
		umask a=,u=rw
		if [[ -z $key ]]; then
			sops --config "$sops_config" --decrypt "${args[@]}" "$file"
		else
			SOPS_AGE_KEY=$(<"$key") sops --config "$sops_config" decrypt "${args[@]}" "$file"
		fi
	)
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

	local expr
	expr=$1

	local flake
	flake=$(find_flake)

	local sops_config
	sops_config=$(find_sops_config "$flake")

	local nproc
	nproc=$(nproc)

	SOPS_CONFIG=$sops_config make -j $((nproc + 1)) -C "$flake" --silent \
		-f @out@/lib/nixverse/Makefile \
		build/secrets.json

	eval_flake --impure . <<EOF
let
  lib = flake.nixverse.inputs.nixpkgs-unstable.lib;
  lib' = flake.lib;
  inherit (flake.nixverse) inputs;
  nodes = flake.nixverse.userEntities;
  secrets = builtins.fromJSON (
    builtins.readFile "$(realpath --no-symlinks "$flake")/build/secrets.json"
  );
in
$expr
EOF
}

cmd_help_help() {
	cat <<EOF
Usage: nixverse help <command>

Show help for the command.
EOF
}

# shellcheck source=library/utils.sh
. @out@/lib/nixverse/utils.sh

cmd '' "$@"
