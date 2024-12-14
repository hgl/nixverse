SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:

ifeq ($(NODE_GROUP),)
  group_dir :=
  node_dir = nodes/$(NODE_RELEASE)/$(NODE_NAME)
else
  group_dir := nodes/$(NODE_RELEASE)/$(NODE_GROUP)
  node_dir := $(group_dir)/$(NODE_NAME)
endif

node_key_types := ed25519 rsa

.PHONY: all
ifeq ($(NODE_OS),nixos)
  all: $(foreach t,$(node_key_types),$(node_dir)/secrets/ssh_host_$(t)_key $(node_dir)/fs/etc/ssh/ssh_host_$(t)_key.pub)
endif

$(node_dir)/secrets/ssh_host_%_key $(node_dir)/fs/etc/ssh/ssh_host_%_key.pub &: | $(node_dir)/secrets $(node_dir)/fs/etc/ssh
	@f=$(node_dir)/fs/etc/ssh/ssh_host_$*_key
	if [[ -e $$f ]]; then
		ssh-keygen -yf "$$f" | cut -d ' ' -f-2 >"$$f.pub"
		chmod a=r,u+w "$$f.pub"
	else
		ssh-keygen -t $* -N '' -C '' -f "$$f"
	fi
	sops encrypt --age $(MASTER_AGE_RECIPIENTS) --input-type binary --output $(node_dir)/secrets/ssh_host_$*_key "$$f"
	rm "$$f"

$(node_dir)/secrets $(node_dir)/fs/etc/ssh:
	mkdir -p $@
