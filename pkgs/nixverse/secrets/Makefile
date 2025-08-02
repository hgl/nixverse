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
	else
		if $(if $(private_dir),[[ -e nodes/$*/secrets.yaml ]],false); then
			mv nodes/$*/secrets.yaml $@
			exist=1
		else
			: >$@
		fi
		if git rev-parse --is-inside-work-tree >/dev/null; then
			git add --intent-to-add --force $@
		fi
	fi
	if [[ -n $$exist ]]; then
		if
			SOPS_AGE_KEY=$$(< $(word 2,$^)) sops --config "$$SOPS_CONFIG" \
				--decrypt --indent 2 $@ | yq --yaml-output |
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
	sops --config "$$SOPS_CONFIG" --encrypt --input-type yaml \
		--output-type yaml --indent 2 --age "$$(< $(word 3,$^))" \
		--output $@ $@.new
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
	if git rev-parse --is-inside-work-tree >/dev/null; then
		git add --intent-to-add --force $@
	fi

build/nodes/%/ssh_host_ed25519_key: $(private_dir)nodes/%/ssh_host_ed25519_key | build/nodes/%
	umask a=,u=rw
	sops --config "$$SOPS_CONFIG" decrypt --output $@ $<

$(private_dir)nodes/%/ssh_host_ed25519_key: | $(private_dir)nodes/%
	if $(if $(private_dir),[[ ! -e $@ && -e nodes/$*/ssh_host_ed25519_key ]],false); then
		mv nodes/$*/ssh_host_ed25519_key $@
	else
		ssh-keygen -t ed25519 -N '' -C '' -f $@
		sops --config "$$SOPS_CONFIG" --encrypt --indent 2 --in-place $@
	fi
	if git rev-parse --is-inside-work-tree >/dev/null; then
		git add --intent-to-add --force $@
	fi
