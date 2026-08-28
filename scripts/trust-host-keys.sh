#!/usr/bin/env bash
# Regenerates ansible/ssh_known_hosts from a fresh `ssh-keyscan` against
# every IP in terraform/servers.auto.tfvars, so Ansible can verify SSH host
# keys (ansible.cfg points UserKnownHostsFile at this file) instead of
# skipping verification entirely.
#
# Trade-off, stated plainly: this is trust-on-first-use, re-run on every
# `make apply`. It replaces "never verify, ever" (the old
# host_key_checking = False) with "verify against whatever key answered
# the last time this ran" — a real improvement (a MITM now has to be
# active during this specific scan to plant a bad key, not just at some
# arbitrary point during any future SSH session), but not a substitute for
# out-of-band key verification. Regenerating from scratch each run
# (instead of appending) is deliberate: it's what correctly handles a
# server's IP being legitimately reassigned to a different host, which
# this repo has actually done (see git history around servers.auto.tfvars).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
KNOWN_HOSTS_FILE="${ROOT_DIR}/ansible/ssh_known_hosts"

SERVERS_JSON="$(cd "${TF_DIR}" && echo 'jsonencode(var.servers)' | terraform console)"

IPS="$(SERVERS_JSON="${SERVERS_JSON}" python3 - <<'PYEOF'
import json
import os

servers = json.loads(json.loads(os.environ["SERVERS_JSON"]))
for s in servers.values():
    print(s["ip"].split("/")[0])
PYEOF
)"

if [[ -z "${IPS}" ]]; then
  echo "trust-host-keys: no servers declared, nothing to scan."
  : > "${KNOWN_HOSTS_FILE}"
  exit 0
fi

echo "trust-host-keys: scanning $(echo "${IPS}" | wc -l | tr -d ' ') host(s)..."
# shellcheck disable=SC2086
ssh-keyscan -T 10 -t ed25519 ${IPS} > "${KNOWN_HOSTS_FILE}.tmp" 2>/dev/null

if [[ ! -s "${KNOWN_HOSTS_FILE}.tmp" ]]; then
  echo "trust-host-keys: ssh-keyscan returned nothing — are the VMs up and reachable?" >&2
  rm -f "${KNOWN_HOSTS_FILE}.tmp"
  exit 1
fi

mv "${KNOWN_HOSTS_FILE}.tmp" "${KNOWN_HOSTS_FILE}"
echo "trust-host-keys: wrote $(wc -l < "${KNOWN_HOSTS_FILE}" | tr -d ' ') host key(s) to ${KNOWN_HOSTS_FILE}."
