# homelab-IaaC

Terraform + Ansible boilerplate for provisioning homelab/small-infra
servers: one map entry, one command, a fully configured server. Default
provider is Proxmox (via `bpg/proxmox`); see `docs/architecture.md` for why
swapping providers later only touches `terraform/modules/server`.

## Quickstart

Prerequisites: `terraform`, `ansible`, `sops`, `age`, a Proxmox host with a
cloud-init-ready VM template, and an SSH keypair for Ansible to use.

```bash
# 1. Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# 2. Generate the age keypair everything is encrypted against
make age-init
#   -> paste the printed public key into .sops.yaml, replacing the placeholder

# 3. Set up secrets
cp terraform/secrets.sops.yaml.example terraform/secrets.sops.yaml
#   -> fill in your Proxmox endpoint/API token/SSH public key
sops -e -i terraform/secrets.sops.yaml

cp ansible/secrets.sops.yaml.example ansible/secrets.sops.yaml
#   -> fill in any app secrets your compose stacks need
sops -e -i ansible/secrets.sops.yaml

# 4. Declare your servers
cp terraform/servers.auto.tfvars.example terraform/servers.auto.tfvars
#   -> edit to match your homelab (or start from the example entries as-is)

# 5. Create the VMs and generate the Ansible inventory
make tf-apply

# 6. Configure them
make ansible-provision
```

You now have servers running, grouped by `type` (prod/staging/uat/...),
each with the right package set installed. Add a server or a server type
without touching anything else — see `docs/adding-a-server.md` and
`docs/adding-a-server-type.md`.

## Layout

```
terraform/     VM creation (modules/server), renders the Ansible inventory
ansible/       site.yml (common -> packages -> docker), layered group/host vars
compose/       one docker-compose.yml per stack, deployed per-host by tag
scripts/       age keygen, secrets decrypt
docs/          architecture.md, adding-a-server.md, adding-a-server-type.md, commands.md
```

Full breakdown of every `make` target: `docs/commands.md`.
Why it's built this way: `docs/architecture.md`.

## Core idea

Terraform is the only source of truth for what servers exist; it hands off
to Ansible via a *generated* inventory file (`ansible/inventory/hosts.generated.yml`),
never a hand-maintained second copy. A server's `type` (prod/staging/uat)
drives both its Ansible inventory group and which package layer applies —
see `docs/architecture.md` for the full data-flow diagram.
