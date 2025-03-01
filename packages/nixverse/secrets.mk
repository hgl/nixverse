SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:

private_dir := $(shell [[ -d private ]] && echo 'private/')

.PHONY: all

ifdef node_names
  all: $(foreach name,$(node_names), \
    $(private_dir)$(node_$(name)_dir)/secrets.yaml \
    build/$(node_$(name)_dir)/ssh_host_ed25519_key \
    $(private_dir)$(node_$(name)_dir)/ssh_host_ed25519_key \
    $(private_dir)$(node_$(name)_dir)/ssh_host_ed25519_key.pub \
  )
  $(foreach name,$(node_names), \
    build/$(node_$(name)_dir) \
    $(private_dir)$(node_$(name)_dir) \
  ):
	mkdir -p $@
endif

$(private_dir)nodes/%/secrets.yaml: build/secrets.yaml build/nodes/%/age.key build/nodes/%/age.pubkey | $(private_dir)nodes/%
	umask a=,u=rw
	yq \
		--yaml-output \
		--arg names '$(node_$(lastword $(subst /, ,$*))_secrets_sections)' \
		'. as $$obj | reduce ($$names | split(" ") | .[]) as $$name ({}; . * ($$obj[$$name] // {}))' \
		$< >$@.new
	trap 'rm $@.new' EXIT
	exist=''
	if [[ -e $@ ]]; then
		exist=1
  ifneq ($(private_dir),)
	elif [[ -e nodes/$*/secrets.yaml ]]; then
  else
	elif false; then
  endif
		mv nodes/$*/secrets.yaml $@
		exist=1
	fi
	if [[ -n $$exist ]]; then
		if
			SOPS_AGE_KEY=$$(< $(word 2,$^)) sops --decrypt --indent 2 $@ |
			yq --yaml-output |
			cmp --quiet - $@.new
		then
			touch $@
			exit
		elif [[ $$? = 1 ]]; then
			:
		else
			exit 1
		fi
	fi
	sops --encrypt --indent 2 \
		--age "$$(< $(word 3,$^))" \
		--output $@ \
		--filename-override $(@F) \
		$@.new
build/nodes/%/age.key: build/nodes/%/ssh_host_ed25519_key
	umask a=,u=rw
	ssh-to-age -private-key -i $< -o $@
build/nodes/%/age.pubkey: $(private_dir)nodes/%/ssh_host_ed25519_key.pub | build/nodes/%
	ssh-to-age -i $< -o $@

$(private_dir)nodes/%/ssh_host_ed25519_key.pub: build/nodes/%/ssh_host_ed25519_key | $(private_dir)nodes/%
ifneq ($(private_dir),)
	if [[ -e nodes/$*/ssh_host_ed25519_key.pub ]] && [[ ! -e $@ ]]; then
else
	if false; then
endif
		rm nodes/$*/ssh_host_ed25519_key.pub
	fi
	ssh-keygen -yf $< >$@

build/nodes/%/ssh_host_ed25519_key: $(private_dir)nodes/%/ssh_host_ed25519_key | build/nodes/%
	umask a=,u=rw
	sops decrypt --output $@ $<

$(private_dir)nodes/%/ssh_host_ed25519_key:
ifneq ($(private_dir),)
	if [[ -e nodes/$*/ssh_host_ed25519_key ]] && [[ ! -e $@ ]]; then
else
	if false; then
endif
		mv nodes/$*/ssh_host_ed25519_key $@
	else
		ssh-keygen -t ed25519 -N '' -C '' -f $@
		sops --encrypt --output $@ $<
	fi
