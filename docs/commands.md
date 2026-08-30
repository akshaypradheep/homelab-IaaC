# Commands

## Day to day

| Command | Does |
|---|---|
| `make apply` | The one command: create/update servers, configure them, deploy every compose stack they opt into. Stops and asks first if it would destroy a VM. |
| `make compose-deploy STACK=<name>` | Deploy or update one stack, e.g. `make compose-deploy STACK=monitoring`. |
| `make update-all` | `apt update && upgrade` on every server. |

## Setup (once)

| Command | Does |
|---|---|
| `make age-init` | Generates the age key used to encrypt secrets. |
| `make show-secrets` | Prints both `secrets.sops.yaml` files, decrypted. Never writes plaintext to disk. |

## Finer control

`make apply` is a wrapper around these — use them when you want to review
or scope a change instead of converging everything:

| Command | Does |
|---|---|
| `make tf-plan` | Preview what `terraform apply` would change. |
| `make tf-apply` | Create/update VMs, regenerate the Ansible inventory. |
| `make ansible-provision` | Run `site.yml` (common → packages → docker) against every server. |
| `make provision-env ENV=<type>` | Same, but scoped to one type, e.g. `ENV=staging`. |
| `make ansible-run PLAYBOOK=<name> LIMIT=<...>` | Run any playbook by name — the generic escape hatch. |

## Manual re-runs of an automatic step

These already run as part of `make apply` for any host that opts in (see
[`ansible-layout.md`](ansible-layout.md#opt-in-roles)) — use these
directly only to retry one step without a full run.

| Command | Does |
|---|---|
| `make fix-usb-kernel LIMIT=<...>` | Swaps the Debian cloud kernel for the standard one and reboots — fixes USB passthrough. `LIMIT` required. |
| `make ansible-run PLAYBOOK=mount-usb-drives LIMIT=<...>` | Mounts a host's declared USB drives. |
| `make ansible-run PLAYBOOK=install-webmin LIMIT=<...>` | Installs Webmin. |

## Targeting: one host / several / a group / everything

Anything with `LIMIT=` or `ENV=` is Ansible's `--limit` flag underneath —
same patterns everywhere:

| I want... | `LIMIT=` | Example |
|---|---|---|
| One host | the hostname | `LIMIT=open-media-vault` |
| Several hosts | comma-separated, no spaces | `LIMIT=web-prod-01,open-media-vault` |
| One type/group | `env_<type>` | `LIMIT=env_prod` |
| Every host | `all` | `LIMIT=all` |

## Which file do I edit?

| I want to... | Edit... |
|---|---|
| Add a server | `terraform/servers.auto.tfvars` — [`adding-a-server.md`](adding-a-server.md) |
| Add a server type | Just use the new `type` string in `servers.auto.tfvars` — [`adding-a-server-type.md`](adding-a-server-type.md) |
| Install a package on every server | `ansible/inventory/group_vars/all.yml` (`common_packages`) |
| Install a package on one type | `ansible/inventory/group_vars/env_<type>.yml` (`type_packages`) |
| Install a package on one server | `ansible/inventory/host_vars/<hostname>.yml` (`host_packages`) |
| Add/change a Docker stack | `compose/<stack>/docker-compose.yml`, then `make compose-deploy STACK=<stack>` |

Full file-by-file breakdown: [`ansible-layout.md`](ansible-layout.md).
