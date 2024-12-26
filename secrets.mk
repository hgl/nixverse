SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

.PHONY: all

ssh_host_key_types := ed25519 rsa
all: $(foreach key,$(ssh_host_key_types:%=ssh_host_%_key),$(NODE_SECRETS_DIR)/$(key) $(NODE_SECRETS_DIR)/$(key).pub $(NODE_BUILD_DIR)/fs/etc/ssh/$(key))
.NOTINTERMEDIATE: $(NODE_SECRETS_DIR)/ssh_host_%_key $(NODE_SECRETS_DIR)/ssh_host_%_key.pub

$(NODE_SECRETS_DIR)/ssh_host_%_key $(NODE_SECRETS_DIR)/ssh_host_%_key.pub &: | $(NODE_SECRETS_DIR)
	@key=$(NODE_SECRETS_DIR)/ssh_host_$*_key
	if [[ -e $$key ]]; then
		ssh-keygen -yf "$$key" | cut -d ' ' -f-2 >"$$key.pub"
		chmod a=r,u+w "$$key.pub"
	else
		ssh-keygen -t $* -N '' -C '' -f "$$key"
	fi
	if [[ ! -e $(FLAKE_DIR)/config.json ]]; then
		echo >&2 'config.json not found in $(FLAKE_DIR)'
		exit 1
	fi
	recipients=$$(jq --raw-output '.secrets.rootRecipients // empty | [.] | flatten(1) | join(",")' $(FLAKE_DIR)/config.json)
	if [[ -z $$recipients ]]; then
		echo >&2 'Missing secrets root recipients configuration in $(FLAKE_DIR)/config.json'
		exit 1
	fi
	umask a=,u=rw
	sops encrypt \
		--age "$$recipients" \
		--in-place \
		"$$key"

$(NODE_BUILD_DIR)/fs/etc/ssh/ssh_host_%_key: $(NODE_SECRETS_DIR)/ssh_host_%_key | $(NODE_BUILD_DIR)/fs/etc/ssh
	sops decrypt --output $@ $<

$(NODE_SECRETS_DIR) $(NODE_BUILD_DIR)/fs/etc/ssh:
	mkdir -p $@
