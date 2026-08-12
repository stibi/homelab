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

cli-latest: ## Print current gh/glab/cue/flux versions and checksums, for pinning
	@for r in cli/cli:gh fluxcd/flux2:flux; do \
	  repo=$${r%%:*}; bin=$${r##*:}; \
	  V=$$(curl -sL https://api.github.com/repos/$$repo/releases/latest \
	       | sed -n 's/.*"tag_name": "v\{0,1\}\([^"]*\)".*/\1/p'); \
	  echo "$$bin $$V"; \
	  curl -sL https://github.com/$$repo/releases/download/v$$V/$${bin}_$${V}_checksums.txt \
	    | grep -E "linux_(amd64|arm64)\.tar\.gz$$" | sed 's/^/  /'; \
	done; \
	V=$$(curl -sL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?per_page=1" \
	     | sed -n 's/.*"tag_name":"v\{0,1\}\([^"]*\)".*/\1/p' | head -1); \
	echo "glab $$V"; \
	curl -sL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/$$V/checksums.txt" \
	  | grep -E "linux_(amd64|arm64)\.tar\.gz$$" | sed 's/^/  /'; \
	V=$$(curl -sL https://api.github.com/repos/cue-lang/cue/releases/latest \
	     | sed -n 's/.*"tag_name": "v\{0,1\}\([^"]*\)".*/\1/p'); \
	echo "cue $$V"; \
	echo "  cue publishes no checksums file - compute it:"; \
	echo "  curl -sL https://github.com/cue-lang/cue/releases/download/v$$V/cue_v$${V}_linux_amd64.tar.gz | sha256sum"

talos-latest: ## Print current talosctl/omnictl versions and checksums, for pinning
	@for r in siderolabs/talos:talosctl siderolabs/omni:omnictl; do \
	  repo=$${r%%:*}; bin=$${r##*:}; \
	  V=$$(curl -sL https://api.github.com/repos/$$repo/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p'); \
	  echo "$$bin $$V"; \
	  curl -sL https://github.com/$$repo/releases/download/$$V/sha256sum.txt \
	    | grep -E "$$bin-linux-(amd64|arm64)$$" | sed 's/^/  /'; \
	done
