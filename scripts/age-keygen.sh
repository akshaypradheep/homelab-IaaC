#!/usr/bin/env bash
# Generates the single age keypair every *.sops.yaml file in this repo is
# encrypted against. Run once per environment (or once per person, if you
# want per-operator keys — then add each public key as a recipient in
# .sops.yaml instead of replacing the placeholder).
set -euo pipefail

KEY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/keys"
KEY_FILE="${KEY_DIR}/age.key"

if [[ -f "${KEY_FILE}" ]]; then
  echo "Key already exists at ${KEY_FILE} — refusing to overwrite." >&2
  exit 1
fi

command -v age-keygen >/dev/null || {
  echo "age-keygen not found. Install age (brew install age / apt install age)." >&2
  exit 1
}

mkdir -p "${KEY_DIR}"
age-keygen -o "${KEY_FILE}"
chmod 600 "${KEY_FILE}"

PUBLIC_KEY="$(grep 'public key:' "${KEY_FILE}" | awk '{print $NF}')"

echo
echo "Private key written to ${KEY_FILE} (gitignored — back it up somewhere safe)."
echo "Public key: ${PUBLIC_KEY}"
echo
echo "Next: paste that public key into .sops.yaml (replacing the placeholder),"
echo "then encrypt your secrets files, e.g.:"
echo "  sops -e -i terraform/secrets.sops.yaml"
echo "  sops -e -i ansible/secrets.sops.yaml"
