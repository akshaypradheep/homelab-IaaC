# Commands

Every `make` target, what it does, and when to reach for it.

| Target | What it does | When to use it |
|---|---|---|
| `make age-init` | Generates the age keypair at `keys/age.key` used by SOPS. | Once, when setting up the repo for the first time. |
| `make tf-init` | `terraform init` in `terraform/`. | Automatically run by `tf-plan`/`tf-apply`; rarely needed standalone. |
| `make tf-plan` | Decrypts `terraform/secrets.sops.yaml` to a gitignored tfvars.json, then `terraform plan`. | Before any apply, to review what will change. |
| `make tf-apply` | Same decrypt step, then `terraform apply` — creates/updates VMs and regenerates `ansible/inventory/hosts.generated.yml` and `compose/monitoring/targets.generated.json`. | After editing `servers.auto.tfvars`. |
| `make ansible-provision` | Runs `site.yml` (common → packages → docker → ...) against every host in the merged generated + static inventory. | After `tf-apply`, or any time you want to re-assert config on everything. |
| `make provision-env ENV=<type>` | Same as above, `--limit env_<type>`. | You only changed something for one type and don't want to touch the others, e.g. `make provision-env ENV=staging`. |
| `make compose-deploy STACK=<name>` | Pushes `compose/<name>/docker-compose.yml` to every host that lists `<name>` in its `compose_stacks` var, then `docker compose up`. | Deploying or updating one app stack. |
| `make update-all` | `apt update && apt upgrade` across every host; reboots if required and the host's type allows it (`common_auto_reboot`). | Routine patching, e.g. from a cron/CI schedule. |
| `make add-server` | Prints a pointer to `docs/adding-a-server.md`. | You forgot the workflow — it's a docs walkthrough, not a script, because "add a server" really is just "edit a tfvars file." |

## Which file do I edit?

| I want to... | Edit... |
|---|---|
| Add a server | `terraform/servers.auto.tfvars` (see `docs/adding-a-server.md`) |
| Add a server type | `ansible/inventory/group_vars/env_<type>.yml` (see `docs/adding-a-server-type.md`) |
| Install a package on ALL servers | `ansible/inventory/group_vars/all.yml` (`common_packages`) |
| Install a package on all servers of one type | `ansible/inventory/group_vars/env_<type>.yml` (`type_packages`) |
| Install a package on ONE server | `ansible/inventory/host_vars/<hostname>.yml` (`host_packages`) |
| Add/change a Docker stack | `compose/<stack>/docker-compose.yml`, then `make compose-deploy STACK=<stack>` |

See `docs/ansible-layout.md` for a full breakdown of every file under
`ansible/` and a worked example of the "install on all / install on one
type" cases above.
