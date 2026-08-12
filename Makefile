PLAYBOOK ?= playbooks/workstation.yml
LIMIT    ?= all
TAGS     ?=

ANSIBLE_ARGS := --limit $(LIMIT)
ifneq ($(TAGS),)
ANSIBLE_ARGS += --tags $(TAGS)
endif

.DEFAULT_GOAL := help

.PHONY: help deps lint check apply shell

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

deps: ## Install ansible-core from apt
	sudo apt update && sudo apt install -y ansible-core

lint: ## Syntax-check the playbook
	ansible-playbook $(PLAYBOOK) --syntax-check

check: ## Dry run, showing what would change
	ansible-playbook $(PLAYBOOK) $(ANSIBLE_ARGS) --check --diff

apply: ## Apply the playbook
	ansible-playbook $(PLAYBOOK) $(ANSIBLE_ARGS) --diff

shell: ## Apply only the shell role
	$(MAKE) apply TAGS=shell

kubectl-latest: ## Print the current kubectl version and checksum, for pinning
	@V=$$(curl -sL https://dl.k8s.io/release/stable.txt); \
	echo "kubectl_version: $$V"; \
	echo "kubectl_sha256: $$(curl -sL https://dl.k8s.io/release/$$V/bin/linux/amd64/kubectl.sha256)"

talos-latest: ## Print current talosctl/omnictl versions and checksums, for pinning
	@for r in siderolabs/talos:talosctl siderolabs/omni:omnictl; do \
	  repo=$${r%%:*}; bin=$${r##*:}; \
	  V=$$(curl -sL https://api.github.com/repos/$$repo/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p'); \
	  echo "$$bin $$V"; \
	  curl -sL https://github.com/$$repo/releases/download/$$V/sha256sum.txt \
	    | grep -E "$$bin-linux-(amd64|arm64)$$" | sed 's/^/  /'; \
	done
