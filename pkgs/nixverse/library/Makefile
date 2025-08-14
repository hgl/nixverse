SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:

private_dir := $(shell [[ -d private ]] && echo 'private/')

define DefineNode
  # $(1): node name

  .PHONY: nodes/$(1)

  build/nodes/$(1):
	mkdir -p $$@
endef

define DefineNodeSecrets
  # $(1): node name
  # $(2): node dir

  nodes/$(1): $(private_dir)$(2)/secrets/default.yaml
  $(private_dir)$(2)/secrets/default.yaml: build/nodes/$(1)/secrets.json build/nodes/$(1)/age.key build/nodes/$(1)/age.pubkey | $(private_dir)$(2)/secrets
	umask a=,u=rw
	if [[ ! -e $$@ ]]; then
		if [[ $$@ = private/* && -e $(2)/secrets/default.yaml ]]; then
			mv $(2)/secrets/default.yaml $$@
		else
			: >$$@
		fi
		if [[ $$@ = private/* ]]; then
			if git -C private rev-parse --is-inside-work-tree >/dev/null; then
				git -C private add --intent-to-add --force $$(@:private/%=%)
			fi
		else
			if git rev-parse --is-inside-work-tree >/dev/null; then
				git add --intent-to-add --force $$@
			fi
		fi
	elif [[ $$@ = private/* && -e $(2)/secrets/default.yaml ]]; then
		echo >&2 "Both $(2)/secrets/default.yaml and $$@ exist, only one is allowed"
		exit 1
	elif cmp --quiet <(
		jq --sort-keys . $$<
	) <(
		SOPS_AGE_KEY=$$$$(< $$(word 2,$$^)) sops --config "$$$$SOPS_CONFIG" --decrypt  \
			--output-type json $$@ | jq --sort-keys .
	); then
		touch $$@
		exit
	elif [[ $$$$? != 1 ]]; then
		exit 1
	fi
	sops --config "$$$$SOPS_CONFIG" --encrypt --input-type json \
		--output-type yaml --indent 2 --age $$$$(< $$(word 3,$$^)) \
		--output $$@ $$<

  build/nodes/$(1)/age.key: build/nodes/$(1)/fs/etc/ssh/ssh_host_ed25519_key
	umask a=,u=rw
	ssh-to-age -private-key -i $$< -o $$@
  build/nodes/$(1)/age.pubkey: $(private_dir)$(2)/fs/etc/ssh/ssh_host_ed25519_key.pub | build/nodes/$(1)
	ssh-to-age -i $$< -o $$@

  $(private_dir)$(2)/fs/etc/ssh/ssh_host_ed25519_key.pub: build/nodes/$(1)/fs/etc/ssh/ssh_host_ed25519_key | $(private_dir)$(2)/fs/etc/ssh
	if [[ ! -e $$@ ]]; then
		if [[ $$@ = private/* && -e $(2)/fs/etc/ssh/ssh_host_ed25519_key.pub ]]; then
			mv $(2)/fs/etc/ssh/ssh_host_ed25519_key.pub $$@
		else
			: >$$@
		fi
		if [[ $$@ = private/* ]]; then
			if git -C private rev-parse --is-inside-work-tree >/dev/null; then
				git -C private add --intent-to-add --force $$(@:private/%=%)
			fi
		else
			if git rev-parse --is-inside-work-tree >/dev/null; then
				git add --intent-to-add --force $$@
			fi
		fi
	fi
	ssh-keygen -yf $$< >$$@


  build/nodes/$(1)/fs/etc/ssh/ssh_host_ed25519_key: $(private_dir)$(2)/secrets/fs/etc/ssh/ssh_host_ed25519_key | build/nodes/$(1)/fs/etc/ssh
	umask a=,u=rw
	sops --config "$$$$SOPS_CONFIG" --decrypt --output $$@ $$<

  $(private_dir)$(2)/secrets/fs/etc/ssh/ssh_host_ed25519_key: | $(private_dir)$(2)/secrets/fs/etc/ssh
	if [[ $$@ = private/* && -e $(2)/secrets/fs/etc/ssh/ssh_host_ed25519_key ]]; then
		mv $(2)/secrets/fs/etc/ssh/ssh_host_ed25519_key $$@
	else
		ssh-keygen -t ed25519 -N '' -C '' -f $$@
		rm -f $$@.pub
		sops --config "$$$$SOPS_CONFIG" --encrypt --indent 2 --in-place $$@
	fi
	if [[ $$@ = private/* ]]; then
		if git -C private rev-parse --is-inside-work-tree >/dev/null; then
			git -C private add --intent-to-add --force $$(@:private/%=%)
		fi
	else
		if git rev-parse --is-inside-work-tree >/dev/null; then
			git add --intent-to-add --force $$@
		fi
	fi

  build/nodes/$(1)/secrets.json: | build/nodes/$(1)

  $(private_dir)$(2)/secrets \
  $(private_dir)$(2)/fs/etc/ssh \
  $(private_dir)$(2)/secrets/fs/etc/ssh \
  build/nodes/$(1)/fs/etc/ssh:
	mkdir -p $$@
endef

define DefineNodesSecrets
  # $(1): secrets node names

  $(1:%=build/nodes/%/secrets.json) &: $(private_dir)secrets.yaml
	. @out@/lib/nixverse/utils.sh
	build_node_secrets_json . "$$$$SOPS_CONFIG" $$< '$(1)'
endef

build/secrets.json: $(private_dir)secrets.yaml | build
	. @out@/lib/nixverse/utils.sh
	secrets_json . "$$SOPS_CONFIG" $< $@

build:
	mkdir -p $@
