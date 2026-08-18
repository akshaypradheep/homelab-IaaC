.PHONY: age-init tf-init tf-plan tf-apply ansible-provision provision-env compose-deploy update-all add-server

# --- secrets -----------------------------------------------------------

age-init: ## Generate the age keypair used by SOPS (run once).
	./scripts/age-keygen.sh

# --- terraform -----------------------------------------------------------

tf-init: ## Standard `terraform init`.
	cd terraform && terraform init

tf-plan: tf-init ## Decrypt secrets, then `terraform plan`.
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform plan

tf-apply: tf-init ## Decrypt secrets, then `terraform apply` (renders inventory + monitoring targets).
	./scripts/decrypt-tf-secrets.sh
	cd terraform && terraform apply

# --- ansible -----------------------------------------------------------

ansible-provision: ## Run site.yml against every generated + static host.
	cd ansible && ansible-playbook playbooks/site.yml

provision-env: ## Run site.yml scoped to one type, e.g. `make provision-env ENV=prod`.
	@if [ -z "$(ENV)" ]; then echo "Usage: make provision-env ENV=<prod|staging|uat|...>"; exit 1; fi
	cd ansible && ansible-playbook playbooks/site.yml --limit env_$(ENV)

compose-deploy: ## Push and run one stack, e.g. `make compose-deploy STACK=example-stack`.
	@if [ -z "$(STACK)" ]; then echo "Usage: make compose-deploy STACK=<name>"; exit 1; fi
	cd ansible && ansible-playbook playbooks/deploy-compose.yml -e stack=$(STACK)

update-all: ## apt update+upgrade across every host.
	cd ansible && ansible-playbook playbooks/update-all.yml

# --- day-to-day -----------------------------------------------------------

add-server: ## Adding a server is a docs walkthrough, not a script.
	@echo "See docs/adding-a-server.md — add one entry to terraform/servers.auto.tfvars,"
	@echo "then: make tf-apply && make ansible-provision"
