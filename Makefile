.PHONY: age-init apply show-secrets tf-init tf-plan tf-apply ansible-provision provision-env compose-deploy update-all add-server

# Every ansible-playbook invocation below can hit the community.sops.sops
# lookup (ansible/secrets.sops.yaml, read live — see docs/ansible-layout.md)
# — it needs to find the age private key, which isn't in any of sops's
# default search locations for this repo. Exporting it here means every
# target gets it for free instead of repeating this per-target.
export SOPS_AGE_KEY_FILE := $(CURDIR)/keys/age.key

# --- the one command ---------------------------------------------------

apply: ## Single command: create/update/destroy VMs (confirms before any destroy), scaffold missing inventory files, provision everything, deploy every compose stack hosts opt into.
	./scripts/apply.sh

# --- secrets -----------------------------------------------------------

age-init: ## Generate the age keypair used by SOPS (run once).
	./scripts/age-keygen.sh

show-secrets: ## Decrypt and print both secrets.sops.yaml files to stdout — never writes plaintext to disk.
	@echo "=== terraform/secrets.sops.yaml ==="
	@sops -d terraform/secrets.sops.yaml
	@echo
	@echo "=== ansible/secrets.sops.yaml ==="
	@sops -d ansible/secrets.sops.yaml

# --- terraform -----------------------------------------------------------

# -parallelism=1: this homelab's pveproxy times out under a handful of
# concurrent API calls (one per server, from the template-lookup data
# source) — serializing them avoids the flakiness.

tf-init: ## Standard `terraform init`.
	cd terraform && terraform init

tf-plan: tf-init ## Decrypt secrets, then `terraform plan`.
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform plan -parallelism=1

tf-apply: tf-init ## Decrypt secrets, then `terraform apply` (renders inventory + monitoring targets).
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform apply -parallelism=1

# --- ansible -----------------------------------------------------------

ansible-provision: ## Run site.yml against every generated + static host.
	cd ansible && ansible-playbook playbooks/site.yml

provision-env: ## Run site.yml scoped to one type, e.g. `make provision-env ENV=prod`.
	@if [ -z "$(ENV)" ]; then echo "Usage: make provision-env ENV=<prod|staging|uat|...>"; exit 1; fi
	cd ansible && ansible-playbook playbooks/site.yml --limit env_$(ENV)

compose-deploy: ## Push and run one stack, e.g. `make compose-deploy STACK=example-stack`. Optionally scope it: `LIMIT=web-prod-01` (one host) or `LIMIT=env_prod` (one group).
	@if [ -z "$(STACK)" ]; then echo "Usage: make compose-deploy STACK=<name> [LIMIT=<host-or-group>]"; exit 1; fi
	cd ansible && ansible-playbook playbooks/deploy-compose.yml -e stack=$(STACK) $(if $(LIMIT),--limit $(LIMIT),)

update-all: ## apt update+upgrade across every host.
	cd ansible && ansible-playbook playbooks/update-all.yml

# --- day-to-day -----------------------------------------------------------

add-server: ## Adding a server is a docs walkthrough, not a script.
	@echo "See docs/adding-a-server.md — add one entry to terraform/servers.auto.tfvars,"
	@echo "then: make apply"
