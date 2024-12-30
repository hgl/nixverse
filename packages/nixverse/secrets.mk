SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

.PHONY: all

ifeq ($(NODE_OS),nixos)
  ssh_host_key_types := ed25519 rsa
  all: $(foreach key,$(ssh_host_key_types:%=ssh_host_%_key),$(NODE_SECRETS_DIR)/$(key) $(NODE_DIR)/fs/etc/ssh/$(key).pub $(NODE_DIR)/fs/etc/ssh/$(key))
  .NOTINTERMEDIATE: $(NODE_SECRETS_DIR)/ssh_host_%_key $(NODE_SECRETS_DIR)/ssh_host_%_key.pub

  $(NODE_SECRETS_DIR)/ssh_host_%_key: | $(NODE_SECRETS_DIR)
	recipients=$$(nixver config '.rootSecretsRecipients // empty | [.] | flatten(1) | join(",")')
	if [[ -z $$recipients ]]; then
		echo >&2 'Missing "rootSecretsRecipients": $(FLAKE_DIR)/config.json'
		exit 1
	fi
	ssh-keygen -t $* -N '' -C '' -f $@
	rm $@.pub
	umask a=,u=rw
	sops encrypt \
		--age "$$recipients" \
		--in-place \
		$@

  $(NODE_DIR)/fs/etc/ssh/ssh_host_%_key: $(NODE_SECRETS_DIR)/ssh_host_%_key | $(NODE_DIR)/fs/etc/ssh
	umask a=,u=rw
	sops decrypt --output $@ $<

  $(NODE_DIR)/fs/etc/ssh/ssh_host_%_key.pub: $(NODE_DIR)/fs/etc/ssh/ssh_host_%_key
	ssh-keygen -yf $< | cut -d ' ' -f-2 >$@
	chmod a=r,u+w $@

  $(NODE_SECRETS_DIR) $(NODE_DIR)/fs/etc/ssh:
	mkdir -p $@
endif
