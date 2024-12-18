SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

node_key_types := ed25519 rsa

.PHONY: ssh-host-keys
ifeq ($(NODE_OS),nixos)
  ssh-host-keys: $(foreach t,$(node_key_types),$(NODE_DIR)/secrets/fs/etc/ssh/ssh_host_$(t)_key $(NODE_DIR)/fs/etc/ssh/ssh_host_$(t)_key.pub)
endif

$(NODE_DIR)/secrets/fs/etc/ssh/ssh_host_%_key $(NODE_DIR)/fs/etc/ssh/ssh_host_%_key.pub &: | $(NODE_DIR)/secrets/fs/etc/ssh $(NODE_DIR)/fs/etc/ssh
	@key=$(NODE_DIR)/secrets/fs/etc/ssh/ssh_host_$*_key
	pubkey=$(NODE_DIR)/fs/etc/ssh/ssh_host_$*_key.pub
	if [[ -e $$f ]]; then
		ssh-keygen -yf "$$f" | cut -d ' ' -f-2 >"$$pubkey"
		chmod a=r,u+w "$$pubkey"
	else
		ssh-keygen -t $* -N '' -C '' -f "$$f"
		mv "$$f.pub" "$$pubkey"
	fi
	nixverse root-secrets encrypt "$$f"

.PHONY: all
secrets_fs_files = $(patsubst $(NODE_DIR)/%,$(NODE_BUILD_DIR)/%,$(shell find $(NODE_DIR)/secrets/fs -mindepth 1 -type f))
all: $(secrets_fs_files)

$(NODE_BUILD_DIR)/secrets/fs/etc/ssh/ssh_host_%_key: $(NODE_DIR)/secrets/fs/etc/ssh/ssh_host_%_key | $(NODE_BUILD_DIR)/secrets/fs/etc/ssh
	nixverse root-secrets decrypt $< $@

$(NODE_BUILD_DIR)/secrets/fs/%: $(NODE_DIR)/secrets/fs/% $(NODE_BUILD_DIR)/fs/etc/ssh/ssh_host_ed25519_key
	mkdir -p $(@D)
	nixverse secrets decrypt $< $@

$(NODE_DIR)/secrets/fs/etc/ssh $(NODE_BUILD_DIR)/secrets/fs/etc/ssh $(NODE_DIR)/fs/etc/ssh:
	mkdir -p $@
