# Commands

Every `make` target, what it does, and when to reach for it.

| Target | What it does | When to use it |
|---|---|---|
| `make apply` | The single command: `scripts/apply.sh` — decrypts secrets, auto-creates any missing `host_vars`/`group_vars` stub files (`scripts/scaffold-inventory.sh`), `terraform apply`s (creates/updates VMs unattended; **stops and asks for confirmation first if the plan would destroy a VM**), re-trusts SSH host keys (`scripts/trust-host-keys.sh`), runs `ansible-provision`, then deploys every `compose/*/` stack (each host's compose-stacks opt-in — common/type/host, unioned — still decides who actually gets it). | The normal day-to-day command — after editing `servers.auto.tfvars`, `host_vars`/`group_vars`, or any `compose/*/docker-compose.yml`. |
| `make age-init` | Generates the age keypair at `keys/age.key` used by SOPS. | Once, when setting up the repo for the first time. |
| `make show-secrets` | Decrypts and prints both `secrets.sops.yaml` files to stdout. Never writes plaintext to disk. | Checking what a secret is currently set to. |
| `make tf-init` | `terraform init` in `terraform/`. | Automatically run by `tf-plan`/`tf-apply`; rarely needed standalone. |
| `make tf-plan` | Decrypts `terraform/secrets.sops.yaml` to a gitignored tfvars.json, then `terraform plan`. | Before any apply, to review what will change. |
| `make tf-apply` | Same decrypt step, then `terraform apply` — creates/updates VMs and regenerates `ansible/inventory/hosts.generated.yml` and `compose/monitoring/targets.generated.json`. | After editing `servers.auto.tfvars`. |
| `make ansible-provision` | Runs `site.yml` (common → packages → docker → ...) against every host in the merged generated + static inventory. | After `tf-apply`, or any time you want to re-assert config on everything. |
| `make provision-env ENV=<type>` | Same as above, `--limit env_<type>`. | You only changed something for one type and don't want to touch the others, e.g. `make provision-env ENV=staging`. |
| `make ansible-run PLAYBOOK=<name> LIMIT=<...>` | Runs any `playbooks/<name>.yml` against a target — the generic escape hatch for a one-off playbook that doesn't have (or doesn't need) its own dedicated `make` target. `LIMIT` is required. | e.g. `make ansible-run PLAYBOOK=install-webmin LIMIT=open-media-vault`. |
| `make compose-deploy STACK=<name>` | Pushes `compose/<name>/` (compose file + any supporting config/secrets template) to every host that resolves `<name>` in its `common_compose_stacks`/`type_compose_stacks`/`host_compose_stacks` union (same pattern as packages), then `docker compose up`. | Deploying or updating one app stack. |
| `make update-all` | `apt update && apt upgrade` across every host; reboots if required and the host's type allows it (`common_auto_reboot`). | Routine patching, e.g. from a cron/CI schedule. |
| `make fix-usb-kernel LIMIT=<...>` | Swaps the Debian cloud kernel for the standard one (adds the `xhci_pci`/`xhci_hcd` USB drivers the cloud kernel lacks) and reboots. Disruptive — `LIMIT` is required. | A VM with USB passthrough configured on the Proxmox side still can't see the device. |
| `make add-server` | Prints a pointer to `docs/adding-a-server.md`. | You forgot the workflow — it's a docs walkthrough, not a script, because "add a server" really is just "edit a tfvars file." |

`make apply`'s granular building blocks (`tf-init`, `tf-plan`, `tf-apply`,
`ansible-provision`, `compose-deploy`, ...) all still work individually,
listed above — reach for them when you want to review or scope a change
rather than converge everything at once.

## Targeting one host / several / a group / everything

Anything driven by `LIMIT=` (`compose-deploy`, `fix-usb-kernel`, `ansible-run`) or `ENV=`
(`provision-env`) is just Ansible's own `--limit` flag underneath, so the
same patterns work everywhere that takes `LIMIT`:

| Target | `LIMIT=` value | Example |
|---|---|---|
| One host | the hostname | `make fix-usb-kernel LIMIT=open-media-vault` |
| Several hosts | comma-separated hostnames, no spaces | `make fix-usb-kernel LIMIT=web-prod-01,open-media-vault` |
| One type/group | `env_<type>` (or any other inventory group) | `make compose-deploy STACK=monitoring LIMIT=env_prod` |
| Every host | `all` | `make fix-usb-kernel LIMIT=all` |

`make ansible-provision` (all hosts) and `make provision-env ENV=<type>`
(one type, via `--limit env_<type>`) cover the two most common cases for
`site.yml` directly; drop to `cd ansible && ansible-playbook
playbooks/site.yml --limit <whatever>` for anything more specific than
that.

## Which file do I edit?

| I want to... | Edit... |
|---|---|
| Add a server | `terraform/servers.auto.tfvars` (see `docs/adding-a-server.md`) — `make apply` auto-creates its `host_vars/<name>.yml` stub |
| Add a server type | Just use the new `type` string in `servers.auto.tfvars` — `make apply` auto-creates `ansible/inventory/group_vars/env_<type>.yml` (see `docs/adding-a-server-type.md`) |
| Install a package on ALL servers | `ansible/inventory/group_vars/all.yml` (`common_packages`) |
| Install a package on all servers of one type | `ansible/inventory/group_vars/env_<type>.yml` (`type_packages`) |
| Install a package on ONE server | `ansible/inventory/host_vars/<hostname>.yml` (`host_packages`) |
| Add/change a Docker stack | `compose/<stack>/docker-compose.yml`, then `make compose-deploy STACK=<stack>` |

See `docs/ansible-layout.md` for a full breakdown of every file under
`ansible/` and a worked example of the "install on all / install on one
type" cases above.
