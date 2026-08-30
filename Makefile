.PHONY: age-init apply show-secrets tf-init tf-plan tf-apply ansible-provision provision-env ansible-run compose-deploy update-all add-server fix-usb-kernel

# Lets Ansible's SOPS lookup (ansible/secrets.sops.yaml) find the age key.
export SOPS_AGE_KEY_FILE := $(CURDIR)/keys/age.key

# --- the one command you'll use most ------------------------------------

apply: ## Create/update servers, configure them, deploy every compose stack. Run this after any change.
	./scripts/apply.sh

# --- one-time setup -------------------------------------------------------

age-init: ## Generate the age key used to encrypt secrets. Run once.
	./scripts/age-keygen.sh

show-secrets: ## Print both secrets files, decrypted. Never writes plaintext to disk.
	@echo "=== terraform/secrets.sops.yaml ==="
	@sops -d terraform/secrets.sops.yaml
	@echo
	@echo "=== ansible/secrets.sops.yaml ==="
	@sops -d ansible/secrets.sops.yaml

# --- terraform: create/update servers -------------------------------------

tf-init: ## terraform init.
	cd terraform && terraform init

tf-plan: tf-init ## Preview what `make tf-apply` would change.
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform plan -parallelism=1

tf-apply: tf-init ## Create/update servers, regenerate the Ansible inventory.
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform apply -parallelism=1

# --- ansible: configure servers -------------------------------------------

ansible-provision: ## Configure every server (packages, docker, hardening).
	cd ansible && ansible-playbook playbooks/site.yml

provision-env: ## Same, but one type only. Usage: make provision-env ENV=prod
	@if [ -z "$(ENV)" ]; then echo "Usage: make provision-env ENV=<prod|staging|uat|...>"; exit 1; fi
	cd ansible && ansible-playbook playbooks/site.yml --limit env_$(ENV)

ansible-run: ## Run any playbook. Usage: make ansible-run PLAYBOOK=install-webmin LIMIT=open-media-vault
	@if [ -z "$(PLAYBOOK)" ]; then echo "Usage: make ansible-run PLAYBOOK=<name> LIMIT=<host[,host...]|group|all>"; exit 1; fi
	@if [ -z "$(LIMIT)" ]; then echo "Usage: make ansible-run PLAYBOOK=<name> LIMIT=<host[,host...]|group|all> — LIMIT is required so nothing runs against every host by accident."; exit 1; fi
	cd ansible && ansible-playbook playbooks/$(PLAYBOOK).yml --limit $(LIMIT)

compose-deploy: ## Deploy one stack. Usage: make compose-deploy STACK=monitoring [LIMIT=env_prod]
	@if [ -z "$(STACK)" ]; then echo "Usage: make compose-deploy STACK=<name> [LIMIT=<host-or-group>]"; exit 1; fi
	cd ansible && ansible-playbook playbooks/deploy-compose.yml -e stack=$(STACK) $(if $(LIMIT),--limit $(LIMIT),)

update-all: ## apt update && upgrade on every server.
	cd ansible && ansible-playbook playbooks/update-all.yml

# --- one-off fixes (never run automatically by `make apply`) --------------

fix-usb-kernel: ## Fix USB passthrough (swaps kernel, reboots). Usage: make fix-usb-kernel LIMIT=open-media-vault
	@if [ -z "$(LIMIT)" ]; then echo "Usage: make fix-usb-kernel LIMIT=<host[,host...]|group|all> — required, this reboots whatever it targets."; exit 1; fi
	cd ansible && ansible-playbook playbooks/fix-usb-cloud-kernel.yml --limit $(LIMIT)

# --- help -------------------------------------------------------------------

add-server: ## How to add a server (see docs/adding-a-server.md).
	@echo "See docs/adding-a-server.md — add one entry to terraform/servers.auto.tfvars,"
	@echo "then: make apply"
