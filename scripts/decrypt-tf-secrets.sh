#!/usr/bin/env bash
# Terraform can't read SOPS files directly, so this decrypts
# terraform/secrets.sops.yaml to terraform/terraform.auto.tfvars.json
# (gitignored) right before plan/apply. Ansible secrets take a different
# path — see ansible/secrets.sops.yaml.example — because the sops lookup
# plugin lets playbooks read them live without ever touching disk.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/terraform/secrets.sops.yaml"
DEST="${ROOT_DIR}/terraform/terraform.auto.tfvars.json"

if [[ ! -f "${SRC}" ]]; then
  echo "Missing ${SRC}. Copy terraform/secrets.sops.yaml.example there, fill it in, and encrypt it:" >&2
  echo "  cp terraform/secrets.sops.yaml.example terraform/secrets.sops.yaml" >&2
  echo "  sops -e -i terraform/secrets.sops.yaml" >&2
  exit 1
fi

command -v sops >/dev/null || {
  echo "sops not found. Install it (brew install sops / apt install sops)." >&2
  exit 1
}

export SOPS_AGE_KEY_FILE="${ROOT_DIR}/keys/age.key"

sops -d --output-type json "${SRC}" > "${DEST}"
chmod 600 "${DEST}"

echo "Decrypted secrets to ${DEST} (gitignored)."
