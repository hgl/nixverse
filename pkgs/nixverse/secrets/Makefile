SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL = all

private_dir := $(shell [[ -d private ]] && echo 'private/')

.PHONY: all

$(private_dir)nodes/%/secrets.yaml: build/secrets.json build/nodes/%/age.key build/nodes/%/age.pubkey | $(private_dir)nodes/%
	umask a=,u=rw
	yq \
		--yaml-output --indent 2 \
		--arg name '$(lastword $(subst /, ,$*))' \
		'.nodes[$$name]' \
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
	sops --encrypt --output-type yaml --indent 2 \
		--age "$$(< $(word 3,$^))" \
		--output $@ \
		$@.new
build/nodes/%/age.key: build/nodes/%/ssh_host_ed25519_key
	umask a=,u=rw
	ssh-to-age -private-key -i $< -o $@
build/nodes/%/age.pubkey: $(private_dir)nodes/%/ssh_host_ed25519_key.pub | build/nodes/%
	ssh-to-age -i $< -o $@

$(private_dir)nodes/%/ssh_host_ed25519_key.pub: build/nodes/%/ssh_host_ed25519_key | $(private_dir)nodes/%
	if $(if $(private_dir),[[ -e nodes/$*/ssh_host_ed25519_key.pub && ! -e $@ ]],false); then
		rm nodes/$*/ssh_host_ed25519_key.pub
	fi
	ssh-keygen -yf $< >$@

build/nodes/%/ssh_host_ed25519_key: $(private_dir)nodes/%/ssh_host_ed25519_key | build/nodes/%
	umask a=,u=rw
	sops decrypt --output $@ $<

$(private_dir)nodes/%/ssh_host_ed25519_key: | $(private_dir)nodes/%
	if $(if $(private_dir),[[ -e nodes/$*/ssh_host_ed25519_key && ! -e $@ ]],false); then
		mv nodes/$*/ssh_host_ed25519_key $@
	else
		ssh-keygen -t ed25519 -N '' -C '' -f $@
		sops --encrypt --indent 2 --in-place $@
	fi
