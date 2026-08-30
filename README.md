# homelab-IaaC

Terraform + Ansible for provisioning homelab servers: add one entry to a
file, run one command, get a fully configured server. Default provider is
Proxmox.

## Quickstart

You'll need: `terraform`, `ansible`, `sops`, `age`, a Proxmox host with a
cloud-init VM template, and an SSH keypair for Ansible to use.

```bash
# 1. Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# 2. Generate the age key everything is encrypted against
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

# 5. Create servers, configure them, deploy every compose stack they opt into
make apply
```

`make apply` creates/updates VMs unattended — if a plan would *destroy* a
VM, it stops and asks first.

## Everyday use

| I want to... | Do this |
|---|---|
| Add a server | Edit `terraform/servers.auto.tfvars`, then `make apply` — see [`docs/adding-a-server.md`](docs/adding-a-server.md) |
| Add a server type (e.g. a new "dr" tier) | Use the new `type` string in `servers.auto.tfvars`, then `make apply` — see [`docs/adding-a-server-type.md`](docs/adding-a-server-type.md) |
| Install a package everywhere | `ansible/inventory/group_vars/all.yml` |
| Install a package on one type | `ansible/inventory/group_vars/env_<type>.yml` |
| Install a package on one server | `ansible/inventory/host_vars/<hostname>.yml` |
| Add/update a Docker stack | `compose/<stack>/docker-compose.yml`, then `make compose-deploy STACK=<stack>` |

Full command reference: [`docs/commands.md`](docs/commands.md).

## Layout

```
terraform/     Creates VMs, renders the Ansible inventory
ansible/       site.yml (common -> packages -> docker), layered group/host vars
compose/       One docker-compose.yml per stack, deployed to hosts that opt in
scripts/       apply orchestrator, inventory scaffolder, SSH trust, age keygen
docs/          One doc per topic — see the table below
```

| Doc | Read it for |
|---|---|
| [`docs/guide.md`](docs/guide.md) | **Start here.** How everything is wired together, plus a worked example for every common task. |
| [`docs/commands.md`](docs/commands.md) | Every `make` target |
| [`docs/ansible-layout.md`](docs/ansible-layout.md) | What each file under `ansible/` is for |
| [`docs/adding-a-server.md`](docs/adding-a-server.md) | Adding one server |
| [`docs/adding-a-server-type.md`](docs/adding-a-server-type.md) | Adding a new tier (prod/staging/...) |
| [`docs/architecture.md`](docs/architecture.md) | Why it's built this way, security posture, known gotchas |
| [`docs/usb-passthrough.md`](docs/usb-passthrough.md) | Passing a USB drive into a VM (e.g. open-media-vault) and mounting it |
| [`docs/ci-runner-setup.md`](docs/ci-runner-setup.md) | Setting up CI |

## Core idea

Terraform owns the list of servers. It hands off to Ansible through a
*generated* inventory file — never hand-edited, never a second copy to keep
in sync. Each server's `type` (prod/staging/uat/...) decides both its
Ansible group and which package/compose layer applies to it. Details in
[`docs/architecture.md`](docs/architecture.md).

## CI

`.github/workflows/provision.yml` runs `make tf-apply` + `make
ansible-provision` on every push to `main` that touches `terraform/`,
`ansible/`, or `compose/monitoring/`. Needs a self-hosted runner on your
homelab network — see [`docs/ci-runner-setup.md`](docs/ci-runner-setup.md).
