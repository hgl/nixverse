SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

.PHONY: all

ifeq ($(NODE_OS),nixos)
  ssh_host_key_types := ed25519 rsa
  all: $(foreach key,$(ssh_host_key_types:%=ssh_host_%_key),$(NODE_SECRETS_DIR)/$(key) $(NODE_SECRETS_DIR)/$(key).pub $(NODE_SECRETS_DIR)/fs/etc/ssh/$(key))
  .NOTINTERMEDIATE: $(NODE_SECRETS_DIR)/ssh_host_%_key $(NODE_SECRETS_DIR)/ssh_host_%_key.pub

  $(NODE_SECRETS_DIR)/ssh_host_%_key $(NODE_SECRETS_DIR)/ssh_host_%_key.pub &: | $(NODE_SECRETS_DIR)
	@key=$(NODE_SECRETS_DIR)/ssh_host_$*_key
	if [[ -e $$key ]]; then
		ssh-keygen -yf "$$key" | cut -d ' ' -f-2 >"$$key.pub"
		chmod a=r,u+w "$$key.pub"
	else
		ssh-keygen -t $* -N '' -C '' -f "$$key"
	fi
	recipients=$$(nixver config '.rootSecretsRecipients // empty | [.] | flatten(1) | join(",")')
	if [[ -z $$recipients ]]; then
		echo >&2 'Missing "rootSecretsRecipients": $(FLAKE_DIR)/config.json'
		exit 1
	fi
	umask a=,u=rw
	sops encrypt \
		--age "$$recipients" \
		--in-place \
		"$$key"

  $(NODE_SECRETS_DIR)/fs/etc/ssh/ssh_host_%_key: $(NODE_SECRETS_DIR)/ssh_host_%_key | $(NODE_SECRETS_DIR)/fs/etc/ssh
	sops decrypt --output $@ $<

  $(NODE_SECRETS_DIR) $(NODE_SECRETS_DIR)/fs/etc/ssh:
	mkdir -p $@
endif
