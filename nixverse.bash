#!@shell@
set -euo pipefail

PATH=@path@:$PATH

cmd_node() {
	cmd "$@"
}

cmd_node_build() {
	local node_name=$1
	shift

	build_node
	build_nixverse_node
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
	local dst=${2-}

	build_node
	build_nixverse_node

	local use_disko=''
	local f
	if f=$(find_node_file partition.bash) && [[ -n $f ]]; then
		#shellcheck disable=SC2029
		ssh "$dst" "$(<"$f")"
	elif f=$(find_node_file disk-config.nix) && [[ -n $f ]]; then
		use_disko=1
	else
		local boot_type boot_device root_format
		IFS=, read -r boot_type boot_device root_format < <(
			jq --raw-output '"\(.boot.type),\(.boot.device.path),\(.boot.device.root.format)"' <<<"$node_json"
		)
		#shellcheck disable=SC2029
		ssh "$dst" "
			BOOT_TYPE='$boot_type'
			BOOT_DEVICE='$boot_device'
			ROOT_FORMAT='$root_format'
			$(<@out@/share/nixverse/partition)
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
		"$dst"
	rsync_fs /mnt
	rsync_home_fs /mnt
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
	local dst=${2-}

	build_node
	build_nixverse_node

	case $node_os in
	nixos)
		local args=()
		if [[ -n $dst ]]; then
			args+=(
				--target-host "$dst"
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
			--flake "$flake#$node_name" \
			--show-trace \
			"${args[@]}"
		;;
	darwin)
		darwin-rebuild switch \
			--flake "$flake#$node_name" \
			--show-trace
		;;
	esac

	rsync_fs
	rsync_home_fs
}

cmd_node_rollback() {
	local node_name=$1
	local dst=${2-}

	find_flake

	local args=()
	if [[ -n $dst ]]; then
		args+=(
			--target-host "$dst"
			--use-remote-sudo
			--fast
		)
	fi
	nixos-rebuild switch \
		--flake "$flake#$node_name" \
		"${args[@]}" \
		--rollback
}

cmd_cleanup() {
	local dst=${1-}

	ssh "$dst" nix-collect-garbage --delete-old
}

cmd_node_state() {
	local node_name=$1
	local filter=${2:-.}

	find_node_json
	jq --raw-output "$filter" <<<"$node_json"
}

cmd_config() {
	local filter=${1-.}

	find_flake
	local f=$flake/config.yaml
	if [[ ! -e $f ]]; then
		echo >&2 "config.yaml not found in $flake"
		return 1
	fi
	yq --raw-output "$filter" "$f"
}

cmd_root-secrets() {
	cmd "$@"
}

cmd_root-secrets_edit() {
	local f=$1
	if [[ ! -e $f ]]; then
		(
			umask a=,u=rw
			cat <<EOF >"$f"
name: value
EOF
		)
		cmd_root-secrets_encrypt -t yaml "$f"
	fi
	if sops --input-type yaml --output-type yaml --indent 2 "$f"; then
		return
	elif [[ $? = 200 ]]; then
		return
	else
		return 1
	fi
}

cmd_root-secrets_encrypt() {
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

	find_flake
	if [[ $in_file = - ]]; then
		in_file=/dev/stdin
	fi
	local recipients
	recipients=$(cmd_config '[.["root-secrets-recipients"] // empty] | flatten(1) | join(",")')
	if [[ -z $recipients ]]; then
		echo >&2 "Missing root-secrets-recipient in $flake/config.yaml"
		return 1
	fi
	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	if [[ -z $out_file ]]; then
		args+=(--in-place)
	elif [[ $out_file != - ]]; then
		mkdir -p "$(dirname "$out_file")"
		args+=(--output "$out_file")
	fi
	(
		umask a=,u=rw
		sops encrypt \
			--age "$recipients" \
			"${args[@]}" \
			"$in_file"
	)
}

cmd_root-secrets_decrypt() {
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

	if [[ $in_file = - ]]; then
		in_file=/dev/stdin
	fi
	local args=()
	if [[ -n $type ]]; then
		args+=(--output-type "$type")
	fi
	if [[ -z $out_file ]]; then
		args+=(--in-place)
	elif [[ $out_file != - ]]; then
		mkdir -p "$(dirname "$out_file")"
		args+=(--output "$out_file")
	fi
	(
		umask a=,u=rw
		sops decrypt \
			"${args[@]}" \
			"$in_file"
	)
}

cmd_secrets() {
	cmd "$@"
}

cmd_secrets_edit() {
	local node_name=$1
	local f=${2-}

	find_node
	local base_secrets=$node_base_dir/${node_group:+common/}/secrets/main.yaml
	if [[ -z $f ]] && f=$base_secrets || [[ $f = "$base_secrets" ]]; then
		local node_secrets=$node_dir/secrets/main.yaml
		local new=''
		if [[ ! -e $f ]]; then
			new=1
			(
				umask a=,u=rw
				cat <<EOF >"$f"
common:
  # secrets for all nodes
  name: value
${node_name}:
  # secrets for this node only, overrides those in common
  name: value
EOF
			)
			cmd_root-secrets_encrypt "$f"
		fi
		if sops --indent 2 "$f"; then
			:
		elif [[ $? = 200 ]]; then
			if [[ -z $new ]] && [[ -e $node_secrets ]]; then
				return
			fi
		else
			return 1
		fi
		local tmp
		tmp=$(mktemp)
		#shellcheck disable=SC2016
		cmd_root-secrets_decrypt "$f" - |
			yq --yaml-output --indent 2 --arg n "$node_name" '(.common // {}) * (.[$n] // {})' >"$tmp"
		#shellcheck disable=SC2064
		trap "rm -f '$tmp'" EXIT

		if [[ ! -e $node_secrets ]]; then
			local recipient
			recipient=$(node_age_recipient)
			(
				umask a=,u=rw
				sops encrypt --age "$recipient" --filename-override "$node_secrets" --output "$node_secrets" "$tmp"
			)
		else
			local key
			key=$(node_age_key)
			EDITOR="mv $tmp" SOPS_AGE_KEY=$key sops edit "$node_secrets"
		fi
	else
		if [[ ! -e $f ]]; then
			(
				umask a=,u=rw
				cat <<EOF >"$f"
name: value
EOF
			)
			cmd_secrets_encrypt "$f"
		fi
		if sops --indent 2 "$f"; then
			return
		elif [[ $? = 200 ]]; then
			return
		else
			return 1
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

	local node_name=$1
	local in_file=$2
	local out_file=${3-}

	if [[ $in_file = - ]]; then
		in_file=/dev/stdin
	fi
	local args=()
	if [[ -n $type ]]; then
		args+=(--input-type "$type")
	fi
	if [[ -z $out_file ]]; then
		args+=(--in-place)
	elif [[ $out_file != - ]]; then
		mkdir -p "$(dirname "$out_file")"
		args+=(--output "$out_file")
	fi
	local recipient
	recipient=$(node_age_recipient)
	(
		umask a=,u=rw
		sops encrypt \
			--age "$recipient" \
			"${args[@]}" \
			"$in_file"
	)
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

	local node_name=$1
	local in_file=$2
	local out_file=${3-}

	if [[ $in_file = - ]]; then
		in_file=/dev/stdin
	fi
	local args=()
	if [[ -n $type ]]; then
		args+=(--output-type "$type")
	fi
	if [[ -z $out_file ]]; then
		args+=(--in-place)
	elif [[ $out_file != - ]]; then
		mkdir -p "$(dirname "$out_file")"
		args+=(--output "$out_file")
	fi
	local age_key
	age_key=$(node_age_key)
	(
		umask a=,u=rw
		SOPS_AGE_KEY=$age_key sops decrypt \
			--input-type yaml \
			"${args[@]}" \
			"$in_file"
	)
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

find_flake() {
	if [[ -n ${flake-} ]]; then
		return
	fi
	flake=$PWD
	local f
	while true; do
		f=$flake/flake.nix
		if [[ -e $f ]]; then
			return
		fi
		if [[ $flake = / ]]; then
			echo >&2 "not in a flake directory: $PWD"
			return 1
		fi
		flake=$(dirname "$flake")
	done
}

find_node() {
	if [[ -n ${node_os-} ]]; then
		return
	fi
	find_node_json
	IFS=, read -r node_os node_channel node_group node_dir node_base_dir < <(
		jq --raw-output '"\(.os),\(.channel),\(.group),\(.dir),\(.baseDir)"' <<<"$node_json"
	)
	node_build_dir=$flake/build/$node_dir
	node_build_base_dir=$flake/build/$node_base_dir
	node_dir=$flake/$node_dir
	node_base_dir=$flake/$node_base_dir
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
			--impure "$flake#." \
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
			--impure "$flake#." \
			--apply "$fn" \
			--show-trace |
			jq "$filter"
	)
}

build_nixverse_node() {
	find_node
	NODE_OS=$node_os \
		NODE_CHANNEL=$node_channel \
		NODE_NAME=$node_name \
		NODE_GROUP=$node_group \
		NODE_DIR=$node_dir \
		NODE_BASE_DIR=$node_base_dir \
		NODE_BUILD_DIR=$node_build_dir \
		NODE_BUILD_BASE_DIR=$node_build_base_dir \
		BUILD_DIR=$flake/build \
		TOP_DIR=$flake \
		make \
		-C "$flake" \
		-f @out@/share/nixverse/Makefile \
		--no-builtin-rules \
		--no-builtin-variables \
		--warn-undefined-variables \
		"$@"
}

#shellcheck disable=SC2120
build_node() {
	build_nixverse_node ssh-host-keys

	local f
	local files=()
	if [[ -n $node_group ]]; then
		files+=("$node_base_dir/common/Makefile" "$node_dir/Makefile")
	else
		files+=("$node_dir/Makefile")
	fi
	local dir
	for f in "${files[@]}"; do
		if [[ ! -e $f ]]; then
			continue
		fi

		dir=$(dirname "$f")
		NODE_OS=$node_os \
			NODE_CHANNEL=$node_channel \
			NODE_NAME=$node_name \
			NODE_GROUP=$node_group \
			NODE_DIR=$node_dir \
			NODE_BASE_DIR=$node_base_dir \
			NODE_BUILD_DIR=$node_build_dir \
			NODE_BUILD_BASE_DIR=$node_build_base_dir \
			BUILD_DIR=$flake/build \
			TOP_DIR=$flake \
			make \
			-C "$dir" \
			--no-builtin-rules \
			--no-builtin-variables \
			--warn-undefined-variables \
			"$@"
	done
}

node_age_recipient() {
	find_node
	local pubkey=$node_dir/fs/etc/ssh/ssh_host_ed25519_key.pub
	if [[ ! -e $pubkey ]]; then
		build_nixverse_node "$pubkey"
	fi
	ssh-to-age -i "$pubkey"
}

node_age_key() {
	find_node
	local key=$node_build_dir/secrets/fs/etc/ssh/ssh_host_ed25519_key
	if [[ ! -e $key ]]; then
		build_nixverse_node "$key"
	fi
	ssh-to-age -private-key -i "$key"
}

rsync_fs() {
	local target_dir=${1:-/}
	find_node

	local dirs=()
	if [[ -n $node_group ]]; then
		if [[ -d "$node_base_dir/common/fs" ]]; then
			dirs+=("$node_base_dir/common/fs")
		fi
	fi
	if [[ -d "$node_dir/fs" ]]; then
		dirs+=("$node_dir/fs")
	fi
	if [[ -d "$node_build_dir/fs" ]]; then
		dirs+=("$node_build_dir/fs")
	fi
	rsync \
		--quiet \
		--recursive \
		--perms \
		--times \
		"${dirs[@]/%//}" \
		"${dst:+$dst:}$target_dir"
}

rsync_home_fs() {
	find_node
	if [[ ! -d "$node_dir/home" ]]; then
		return
	fi

	local target_dir=${1-}

	find "$node_dir/home" \
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
			sudo rsync \
				--quiet \
				--recursive \
				--perms \
				--times \
				--chown "$uid:$gid" \
				--numeric-ids \
				"$dir/" \
				"${dst:+$dst:}$target_dir$home/"
			;;
		esac
	)
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
