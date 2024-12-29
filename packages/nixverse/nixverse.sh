#!@shell@
# shellcheck shell=bash
set -euo pipefail

PATH=@path@:$PATH

cmd_node() {
	cmd "$@"
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

	build_node

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
		--flake "$flake_dir#$node_name" \
		"${args[@]}" \
		"$ssh_dst"
	rsync_fs /mnt
}

cmd_node_deploy() {
	local remote_build=1
	OPTIND=1
	while getopts 'R' opt; do
		case $opt in
		R) remote_build='' ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local node_name=$1
	local ssh_dst=${2-}

	build_node

	case $node_os in
	nixos)
		local args=()
		if [[ -n $ssh_dst ]]; then
			args+=(
				--target-host "$ssh_dst"
				--use-remote-sudo
				--fast
			)
		fi
		if [[ -z $remote_build ]]; then
			args+=(
				--build-host ''
			)
		fi
		nixos-rebuild switch \
			--flake "$flake_dir#$node_name" \
			--show-trace \
			"${args[@]}"
		;;
	darwin)
		darwin-rebuild switch \
			--flake "$flake_dir#$node_name" \
			--show-trace
		;;
	esac

	rsync_fs
}

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
		--flake "$flake_dir#$node_name" \
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

	pushd "$flake_dir" >/dev/null
	nix flake update
	popd >/dev/null

	cmd_node_deploy "$@"
}

cmd_node_state() {
	local node_name=$1
	local filter=${2:-.}

	find_node_json
	jq --raw-output "$filter" <<<"$node_json"
}

cmd_node_secrets() {
	local node_name=$1
	local filter=${2-}

	find_secrets
	find_node

	local node_secrets=$node_secrets_dir/secrets.yaml
	local new_node_secrets=''
	local key
	if [[ -z $filter ]]; then
		if [[ ! -e $node_secrets ]]; then
			new_node_secrets=1
			mkdir -p "$(dirname "$node_secrets")"
		fi
		if [[ -z $node_group ]]; then
			if [[ -n $new_node_secrets ]]; then
				mkdir -p "$(dirname "$node_secrets")"
				(
					umask a=,u=rw
					cat <<EOF >"$node_secrets"
name: value
EOF
				)
				sops encrypt --age "$recipient" --in-place "$node_secrets"
			fi
			key=$(node_age_key)
			SOPS_AGE_KEY=$key sops "$node_secrets"
		else
			local common_secrets=$node_secrets_common_dir/secrets.yaml
			local new_common_secrets=''
			if [[ ! -e $common_secrets ]]; then
				new_common_secrets=1
				mkdir -p "$(dirname "$common_secrets")"
				(
					umask a=,u=rw
					cat <<EOF >"$common_secrets"
common:
  # secrets for all nodes
  name: value
${node_name}:
  # secrets for this node only, overrides those in common
  name: value
EOF
				)
				encrypt_root_secrets '' "$common_secrets"
			fi
			if sops --indent 2 "$common_secrets"; then
				:
			elif [[ $? = 200 ]]; then
				if [[ -z $new_common_secrets ]] && [[ -z $new_node_secrets ]]; then
					return
				fi
			else
				return 1
			fi
			local tmp
			tmp=$(mktemp)
			#shellcheck disable=SC2016
			decrypt_root_secrets '' "$common_secrets" - |
				yq --yaml-output --indent 2 --arg n "$node_name" '(.common // {}) * (.[$n] // {})' >"$tmp"
			#shellcheck disable=SC2064
			trap "rm -f '$tmp'" EXIT

			if [[ -n $new_node_secrets ]]; then
				local recipient
				recipient=$(node_age_recipient)
				(
					umask a=,u=rw
					sops encrypt --age "$recipient" --filename-override "$node_secrets" --output "$node_secrets" "$tmp"
				)
			else
				key=$(node_age_key)
				EDITOR="mv $tmp" SOPS_AGE_KEY=$key sops edit "$node_secrets"
			fi
		fi
	else
		key=$(node_age_key)
		SOPS_AGE_KEY=$key sops decrypt "$node_secrets" | yq --raw-output "$filter"
	fi
}

cmd_secrets() {
	cmd "$@"
}

cmd_secrets_edit() {
	local f=$1
	if [[ ! -e $f ]]; then
		mkdir -p "$(dirname "$f")"
		(
			umask a=,u=rw
			cat <<EOF >"$f"
name: value
EOF
		)
	fi

	find_node_by_secret_path "$f"
	if [[ -z $node_name ]]; then
		if sops --indent 2 "$f"; then
			return
		elif [[ $? = 200 ]]; then
			return
		else
			return 1
		fi
	elif [[ $node_name = common ]]; then
		if [[ $secret_path = secrets.yaml ]]; then
			echo >&2 'Node secrets can only be edit with "nixverse node secrets <node name>"'
			return 1
		fi
		if sops --indent 2 "$f"; then
			return
		elif [[ $? = 200 ]]; then
			return
		else
			return 1
		fi
	else
		if [[ $secret_path = secrets.yaml ]]; then
			echo >&2 'Node secrets can only be edit with "nixverse node secrets <node name>"'
			return 1
		else
			local key
			key=$(node_age_key)
			if SOPS_AGE_KEY=$key sops --indent 2 "$f"; then
				return
			elif [[ $? = 200 ]]; then
				return
			else
				return 1
			fi
		fi
	fi
}

cmd_secrets_encrypt() {
	local type=''
	OPTIND=1
	while getopts 't:' opt; do
		case $opt in
		t) type=$OPTARG ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local in_file=$1
	local out_file=${2-}

	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	local ref_file=''
	if [[ $in_file = - ]]; then
		if [[ -z $out_file ]] || [[ $out_file = - ]]; then
			echo >&2 "Unable to determine the secret's path, encrypting as a root secret"
			encrypt_root_secrets "$type" -
			return
		else
			ref_file=$out_file
			if [[ ! -e $out_file ]]; then
				mkdir -p "$(dirname "$out_file")"
				: >"$out_file"
			fi
			args+=(--output "$out_file")
		fi
		args+=(/dev/stdin)
	else
		if [[ -z $out_file ]]; then
			args+=(--in-place)
			ref_file=$in_file
		elif [[ $out_file = - ]]; then
			ref_file=$in_file
		else
			args+=(--output "$out_file")
			ref_file=$out_file
			if [[ ! -e $out_file ]]; then
				mkdir -p "$(dirname "$out_file")"
				: >"$out_file"
			fi
		fi
		args+=("$in_file")
	fi
	find_node_by_secret_path "$ref_file"
	if [[ -z $node_name ]]; then
		encrypt_root_secrets "$type" "$in_file" "$out_file"
	elif [[ $node_name = common ]]; then
		if [[ $secret_path = secrets.yaml ]]; then
			echo >&2 'Node secrets can only be edit with "nixverse node secrets <node name>"'
			return 1
		fi
		encrypt_root_secrets "$type" "$in_file" "$out_file"
	else
		case $secret_path in
		secrets.yaml)
			echo >&2 'Node secrets can only be edit with "nixverse node secrets <node name>"'
			return 1
			;;
		ssh_host_*_key)
			echo >&2 'Node ssh host keys are managed automatically, do not edit'
			return 1
			;;
		esac
		local recipient
		recipient=$(node_age_recipient)
		(
			umask a=,u=rw
			sops encrypt \
				--age "$recipient" \
				"${args[@]}"
		)
	fi
}

cmd_secrets_decrypt() {
	local type=''
	OPTIND=1
	while getopts 't:' opt; do
		case $opt in
		t) type=$OPTARG ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	local in_file=$1
	local out_file=${2-}

	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	local ref_file=''
	if [[ $in_file = - ]]; then
		if [[ -z $out_file ]] || [[ $out_file = - ]]; then
			echo >&2 "Unable to determine the secret's path, decrypting as a root secret"
			decrypt_root_secrets "$type" -
			return
		else
			ref_file=$out_file
			if [[ ! -e $out_file ]]; then
				mkdir -p "$(dirname "$out_file")"
				: >"$out_file"
			fi
			args+=(--output "$out_file")
		fi
		args+=(/dev/stdin)
	else
		ref_file=$in_file
		if [[ -z $out_file ]]; then
			args+=(--in-place)
		elif [[ $out_file = - ]]; then
			:
		else
			args+=(--output "$out_file")
		fi
		args+=("$in_file")
	fi
	find_node_by_secret_path "$ref_file"
	if [[ -z $node_name ]]; then
		decrypt_root_secrets "$type" "$in_file" "$out_file"
	elif [[ $node_name = common ]]; then
		if [[ $secret_path = secrets.yaml ]]; then
			echo >&2 'Node secrets can only be edit with "nixverse node secrets"'
			return 1
		fi
		decrypt_root_secrets "$type" "$in_file" "$out_file"
	else
		case $secret_path in
		secrets.yaml)
			echo >&2 'Node secrets can only be edit with "nixverse node secrets"'
			return 1
			;;
		ssh_host_*_key)
			echo >&2 'Node ssh host keys are managed automatically, do not edit'
			return 1
			;;
		esac
		local age_key
		age_key=$(node_age_key)
		(
			umask a=,u=rw
			SOPS_AGE_KEY=$age_key sops decrypt \
				"${args[@]}"
		)
	fi
}

cmd_group() {
	cmd "$@"
}

cmd_group_state() {
	local node_group=$1
	local filter=${2:-.}

	find_group_json
	jq --raw-output "$filter" <<<"$group_json"
}

cmd_config() {
	config "$@"
}

find_flake() {
	if [[ -n ${flake_dir-} ]]; then
		return
	fi
	if [[ -n ${FLAKE_DIR-} ]]; then
		if [[ ! -e $FLAKE_DIR/flake.nix ]]; then
			echo >&2 "FLAKE_DIR is not a flake directory: $FLAKE_DIR"
			return 1
		fi
		flake_dir=$FLAKE_DIR
		return
	fi
	flake_dir=$PWD
	while true; do
		if [[ -e $flake_dir/flake.nix ]]; then
			build_dir=$flake_dir/build
			return
		fi
		if [[ $flake_dir = / ]]; then
			echo >&2 "not in a flake directory: $PWD"
			return 1
		fi
		flake_dir=$(dirname "$flake_dir")
	done
}

find_node() {
	if [[ -n ${node_os-} ]]; then
		return
	fi
	find_flake
	find_secrets -o
	find_node_json
	IFS=, read -r node_os node_channel node_group < <(
		jq --raw-output '"\(.os),\(.channel),\(.group)"' <<<"$node_json"
	)
	if [[ -z $node_group ]]; then
		node_base_dir=nodes/$node_name
		node_dir=$node_base_dir
	else
		node_base_dir=nodes/$node_group
		node_dir=$node_base_dir/$node_name
	fi
	if [[ -z $secrets_dir ]]; then
		node_secrets_common_dir=''
		node_secrets_dir=''
		node_secrets_base_dir=''
	else
		if [[ -z $node_group ]]; then
			node_secrets_common_dir=''
		else
			node_secrets_common_dir=$secrets_dir/nodes/$node_group/common
		fi
		node_secrets_dir=$secrets_dir/$node_dir
		node_secrets_base_dir=$secrets_dir/$node_base_dir
	fi
	node_build_dir=$build_dir/$node_dir
	node_build_base_dir=$build_dir/$node_base_dir
	node_dir=$flake_dir/$node_dir
	node_base_dir=$flake_dir/$node_base_dir
}

find_secrets() {
	if [[ ${secrets_dir-.} != . ]]; then
		return
	fi

	local optional=''
	OPTIND=1
	while getopts 'o' opt; do
		case $opt in
		o) optional=1 ;;
		?) exit 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	find_flake
	local input_exists
	input_exists=$(nix flake metadata "$flake_dir" --json |
		jq 'if .locks.nodes.secrets then 1 else empty end')
	if [[ -z $input_exists ]]; then
		if [[ -z $optional ]]; then
			echo >&2 "Missing secrets directory configuration in $flake_dir/config.json"
			return 1
		fi
		secrets_dir=''
	else
		nix flake update secrets --flake "$flake_dir"
		secrets_dir=$(nix eval --raw "$flake_dir#self.inputs.secrets")
	fi
}

find_node_by_secret_path() {
	find_secrets

	secret_path=$(readlink -f "$1")

	node_name=''
	node_group=''
	secret_base_dir=${secret_path#"$secrets_dir/"}
	if [[ $secret_base_dir = "$secrets_dir" ]]; then
		echo >&2 "Secret is not inside the secrets directory: $secret_path"
		return 1
	else
		secret_path=$secret_base_dir
		secret_base_dir=$flake_dir
	fi

	if [[ $secret_path = "${secret_path#nodes/}" ]]; then
		return
	fi
	secret_path=${secret_path#nodes/}
	secret_base_dir=$secret_base_dir/nodes
	node_name=${secret_path%%/*}
	secret_path=${secret_path#"$node_name/"}
	if [[ -e $secret_base_dir/$node_name/node.nix ]]; then
		find_node
	elif [[ -e $secret_base_dir/$node_name/nodes.nix ]]; then
		node_name=${secret_path%%/*}
		secret_path=${secret_path#"$node_name/"}
		if [[ $node_name != common ]]; then
			find_node
		fi
	else
		echo >&2 "File is inside nodes directory, but not in a node directory: $secret_path"
		return 1
	fi
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

find_node_json() {
	find_flake

	local fn
	fn=$(
		cat <<-EOF
			{ self, nodes, ... }:
			let
				inherit (self) inputs;
				inherit (inputs.nixpkgs-unstable) lib;
				lib' = inputs.nixverse-unstable.lib;
				node = nodes.\${"$node_name"} or null;
			in
			if node == null then
				null
			else
				lib'.filterRecursive
					(n: v: !(lib.isFunction v))
					node
		EOF
	)
	local filter
	filter=$(
		cat <<-EOF
			if . == null then
				"Unknown node $node_name\n" | halt_error(1)
			else
				.
			end
		EOF
	)
	node_json=$(
		nix eval \
			--json \
			--no-warn-dirty \
			--impure "$flake_dir#." \
			--apply "$fn" \
			--show-trace |
			jq "$filter"
	)
}

find_group_json() {
	find_flake

	local fn
	fn=$(
		cat <<-EOF
			{ self, nodeGroups, ... }:
			let
				inherit (self) inputs;
				inherit (inputs.nixpkgs-unstable) lib;
				lib' = inputs.nixverse-unstable.lib;
				group = nodeGroups.\${"$node_group"} or null;
			in
			if group == null then
				null
			else
				lib'.filterRecursive
					(n: v: !(lib.isFunction v))
					group
		EOF
	)
	local filter
	filter=$(
		cat <<-EOF
			if . == null then
				"Unknown group $node_group\n" | halt_error(1)
			else
				.
			end
		EOF
	)
	group_json=$(
		nix eval \
			--json \
			--no-warn-dirty \
			--impure "$flake_dir#." \
			--apply "$fn" \
			--show-trace |
			jq "$filter"
	)
}

#shellcheck disable=SC2120
build_node() {
	build_node_secrets

	if [[ -n $node_secrets_base_dir ]] && [[ -e $node_secrets_base_dir/Makefile ]]; then
		NODE_OS=$node_os \
			NODE_CHANNEL=$node_channel \
			NODE_NAME=$node_name \
			NODE_GROUP=$node_group \
			NODE_DIR=$node_dir \
			NODE_BASE_DIR=$node_base_dir \
			FLAKE_DIR=$flake_dir \
			NODE_BUILD_DIR=$node_build_dir \
			NODE_BUILD_BASE_DIR=$node_build_base_dir \
			BUILD_DIR=$build_dir \
			SECRETS_DIR=$secrets_dir \
			NODE_SECRETS_DIR=$node_secrets_dir \
			NODE_SECRETS_COMMON_DIR=$node_secrets_common_dir \
			make \
			-C "$node_secrets_base_dir" \
			--no-builtin-rules \
			--no-builtin-variables \
			--warn-undefined-variables \
			"$@"
	fi
}

build_node_secrets() {
	find_node

	if [[ -z $node_secrets_dir ]]; then
		return
	fi
	NODE_OS=$node_os \
		NODE_CHANNEL=$node_channel \
		NODE_NAME=$node_name \
		NODE_GROUP=$node_group \
		NODE_DIR=$node_dir \
		NODE_BASE_DIR=$node_base_dir \
		FLAKE_DIR=$flake_dir \
		NODE_BUILD_DIR=$node_build_dir \
		NODE_BUILD_BASE_DIR=$node_build_base_dir \
		BUILD_DIR=$build_dir \
		SECRETS_DIR=$secrets_dir \
		NODE_SECRETS_DIR=$node_secrets_dir \
		NODE_SECRETS_COMMON_DIR=$node_secrets_common_dir \
		make \
		-C "$flake_dir" \
		-f @out@/lib/nixverse/secrets.mk \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
}

config() {
	find_secrets -o

	local filter=${1-.}

	local f
	if [[ ! -e $flake_dir/config.json ]]; then
		if [[ -z $secrets_dir ]] || [[ ! -e $secrets_dir/config.json ]]; then
			echo >&2 "config.json does not exist in flake"
			return 1
		fi
		f=$secrets_dir/config.json
	elif [[ -z $secrets_dir ]] || [[ ! -e $secrets_dir/config.json ]]; then
		f=$flake_dir/config.json
	else
		jq --raw-output --slurp ".[0] * .[1] | $filter" \
			"$flake_dir/config.json" "$secrets_dir/config.json"
		return
	fi
	jq --raw-output "$filter" "$f"
}

encrypt_root_secrets() {
	find_flake

	local type=$1
	local in_file=$2
	local out_file=${3-}

	local recipients
	recipients=$(config '.rootSecretsRecipients // empty | [.] | flatten(1) | join(",")')
	if [[ -z $recipients ]]; then
		echo >&2 "Missing \"rootSecretsRecipients\" in $flake_dir/config.json"
		return 1
	fi
	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	if [[ $in_file = - ]]; then
		if [[ -z $out_file ]]; then
			:
		elif [[ $out_file != - ]]; then
			args+=(--output "$out_file")
		fi
		args+=(/dev/stdin)
	else
		if [[ -z $out_file ]]; then
			args+=(--in-place)
		elif [[ $out_file != - ]]; then
			args+=(--output "$out_file")
		fi
		args+=("$in_file")
	fi
	(
		umask a=,u=rw
		sops encrypt \
			--age "$recipients" \
			"${args[@]}"
	)
}

decrypt_root_secrets() {
	local type=$1
	local in_file=$2
	local out_file=${3-}

	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	if [[ $in_file = - ]]; then
		if [[ -z $out_file ]]; then
			:
		elif [[ $out_file != - ]]; then
			args+=(--output "$out_file")
		fi
		args+=(/dev/stdin)
	else
		if [[ -z $out_file ]]; then
			args+=(--in-place)
		elif [[ $out_file != - ]]; then
			args+=(--output "$out_file")
		fi
		args+=("$in_file")
	fi
	(
		umask a=,u=rw
		sops decrypt \
			"${args[@]}"
	)
}

node_age_recipient() {
	find_secrets
	find_node

	local pubkey=$node_secrets_dir/ssh_host_ed25519_key.pub
	if [[ ! -e $pubkey ]]; then
		build_node_secrets "$pubkey" >/dev/null
	fi
	ssh-to-age -i "$pubkey"
}

node_age_key() {
	find_node

	local key=$node_build_dir/fs/etc/ssh/ssh_host_ed25519_key
	if [[ ! -e $key ]]; then
		build_node_secrets "$key" >/dev/null
	fi
	ssh-to-age -private-key -i "$key"
}

rsync_fs() {
	local target_dir=${1-}

	find_node
	local dirs=()
	if [[ -n $node_group ]] && [[ -d "$node_base_dir/common/fs" ]]; then
		dirs+=("$node_base_dir/common/fs")
	fi
	if [[ -d "$node_dir/fs" ]]; then
		dirs+=("$node_dir/fs")
	fi
	if [[ -d "$node_build_dir/fs" ]]; then
		dirs+=("$node_build_dir/fs")
	fi
	local uid
	local args=()
	if [[ ${#dirs[@]} != 0 ]]; then
		uid=$(id --user)
		if [[ $uid = 0 ]]; then
			set --
		else
			set -- sudo
		fi
		"$@" rsync \
			--quiet \
			--recursive \
			--perms \
			--times \
			"${dirs[@]/%//}" \
			"${ssh_dst:+$ssh_dst:}${target_dir:-/}"
	fi

	dirs=()
	if [[ -d "$node_dir/home" ]]; then
		dirs+=("$node_dir/home")
	fi
	if [[ -d "$node_build_dir/home" ]]; then
		dirs+=("$node_build_dir/home")
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
			uid=$(id --user)
			if [[ $uid = 0 ]]; then
				set --
			else
				set -- sudo
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
