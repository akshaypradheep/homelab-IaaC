#!/usr/bin/env bash
# Single-command convergence for the whole homelab: create/update/destroy
# VMs, scaffold any missing inventory files, provision every host, and
# deploy every compose stack hosts opt into. See docs/architecture.md.
#
# Creates/updates run unattended. A plan that would DESTROY a real VM
# stops and asks for explicit confirmation first — everything else never
# prompts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# The Ansible steps below can hit the community.sops.sops lookup
# (ansible/secrets.sops.yaml, read live) — it needs to find the age
# private key, which isn't in any of sops's default search locations.
export SOPS_AGE_KEY_FILE="${ROOT_DIR}/keys/age.key"

TF_DIR="${ROOT_DIR}/terraform"
PLAN_FILE="${TF_DIR}/tfplan"
PLAN_JSON="${TF_DIR}/tfplan.json"

cleanup() {
  # tfplan/tfplan.json contain plaintext secrets (the `sensitive` flag on
  # variables.tf only redacts CLI output, not the saved plan) — never
  # leave them lying around, success or failure.
  rm -f "${PLAN_FILE}" "${PLAN_JSON}"
}
trap cleanup EXIT

echo "==> terraform init"
(cd "${TF_DIR}" && terraform init)

echo "==> decrypting terraform secrets"
./scripts/decrypt-tf-secrets.sh

echo "==> scaffolding missing inventory files"
./scripts/scaffold-inventory.sh

echo "==> terraform plan"
(cd "${TF_DIR}" && terraform plan -parallelism=1 -out="${PLAN_FILE}")

(cd "${TF_DIR}" && terraform show -json "${PLAN_FILE}") > "${PLAN_JSON}"

DESTROYED_VMS="$(python3 - "${PLAN_JSON}" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as f:
    plan = json.load(f)

addresses = []
for rc in plan.get("resource_changes", []):
    if rc.get("type") != "proxmox_virtual_environment_vm":
        continue
    if "delete" in rc.get("change", {}).get("actions", []):
        addresses.append(rc.get("address", "<unknown>"))

print("\n".join(addresses))
PYEOF
)"

if [[ -n "${DESTROYED_VMS}" ]]; then
  echo
  echo "The following VM(s) would be DESTROYED:"
  echo "${DESTROYED_VMS}" | sed 's/^/  - /'
  echo
  read -r -p "Type 'y' to proceed with destroying them, anything else to abort: " CONFIRM
  if [[ "${CONFIRM}" != "y" ]]; then
    echo "Aborted — no changes made."
    exit 1
  fi
fi

echo "==> terraform apply"
(cd "${TF_DIR}" && terraform apply -parallelism=1 "${PLAN_FILE}")

echo "==> trusting SSH host keys (fresh scan, see scripts/trust-host-keys.sh)"
./scripts/trust-host-keys.sh

echo "==> installing ansible collections"
(cd ansible && ansible-galaxy collection install -r requirements.yml)

echo "==> ansible-provision (site.yml)"
(cd ansible && ansible-playbook playbooks/site.yml)

echo "==> deploying compose stacks"
for stack_dir in compose/*/; do
  stack="$(basename "${stack_dir}")"
  if [[ -f "${stack_dir}docker-compose.yml" ]]; then
    echo "--> stack: ${stack}"
    (cd ansible && ansible-playbook playbooks/deploy-compose.yml -e "stack=${stack}")
  fi
done

echo "==> done."
