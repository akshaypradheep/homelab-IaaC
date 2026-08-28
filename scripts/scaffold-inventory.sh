#!/usr/bin/env bash
# Creates ansible/inventory/host_vars/<name>.yml and
# ansible/inventory/group_vars/env_<type>.yml stubs for any server/type in
# terraform/servers.auto.tfvars that doesn't have one yet. Reads
# var.servers straight from Terraform (via `terraform console`, no network
# calls for a plain input-variable expression) so it's always in sync with
# what servers.auto.tfvars actually declares, without needing an apply
# first.
#
# Never overwrites an existing file, never deletes one — see
# docs/architecture.md for why hand-maintained inventory files are treated
# differently from Terraform-generated ones.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
HOST_VARS_DIR="${ROOT_DIR}/ansible/inventory/host_vars"
GROUP_VARS_DIR="${ROOT_DIR}/ansible/inventory/group_vars"

mkdir -p "${HOST_VARS_DIR}" "${GROUP_VARS_DIR}"

SERVERS_JSON="$(cd "${TF_DIR}" && echo 'jsonencode(var.servers)' | terraform console)"

SERVERS_JSON="${SERVERS_JSON}" python3 - "${HOST_VARS_DIR}" "${GROUP_VARS_DIR}" <<'PYEOF'
import json
import os
import sys

host_vars_dir, group_vars_dir = sys.argv[1], sys.argv[2]
# terraform console prints the string result as a JSON-encoded literal,
# so this is a JSON string containing JSON text - decode twice.
servers = json.loads(json.loads(os.environ["SERVERS_JSON"]))

created = []

for name, s in servers.items():
    path = os.path.join(host_vars_dir, f"{name}.yml")
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write(
                "# Auto-created by scripts/scaffold-inventory.sh — edit freely\n"
                "# (compose_stacks, host_packages, etc.). See docs/ansible-layout.md.\n"
                "compose_stacks: []\n"
            )
        created.append(path)

types = sorted({s["type"] for s in servers.values()})
for t in types:
    path = os.path.join(group_vars_dir, f"env_{t}.yml")
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write(
                "# Auto-created by scripts/scaffold-inventory.sh — edit freely.\n"
                "# See docs/adding-a-server-type.md.\n"
                "type_packages: []\n"
                "common_auto_reboot: false\n"
            )
        created.append(path)

if created:
    print("scaffold-inventory: created:")
    for p in created:
        print(f"  {p}")
else:
    print("scaffold-inventory: nothing to scaffold (all servers/types already have files).")

known_hosts = set(servers.keys())
known_types = set(types)
orphan_hosts = sorted(
    f for f in os.listdir(host_vars_dir)
    if f.endswith(".yml") and f[:-4] not in known_hosts
)
orphan_groups = sorted(
    f for f in os.listdir(group_vars_dir)
    if f.startswith("env_") and f.endswith(".yml") and f[len("env_"):-4] not in known_types
)
if orphan_hosts or orphan_groups:
    print("scaffold-inventory: note — these don't match any current server/type")
    print("  (left as-is; `git rm` by hand if they're actually dead):")
    for f in orphan_hosts:
        print(f"  {os.path.join(host_vars_dir, f)}")
    for f in orphan_groups:
        print(f"  {os.path.join(group_vars_dir, f)}")
PYEOF
