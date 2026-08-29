# Ansible directory layout

What each file/folder under `ansible/` is for, and how they connect. See
`docs/architecture.md` for *why* it's shaped this way; this doc is the
reference for *what's where*.

## Inventory — who the hosts are, and what groups they're in

| Path | What it is |
|---|---|
| `ansible.cfg` | Points Ansible at both inventory files (merged), sets `remote_user = apj` (the cloud-init user Terraform creates), verifies SSH host keys against `ssh_known_hosts` (see `scripts/trust-host-keys.sh`), enables SSH pipelining. |
| `inventory/hosts.generated.yml` | Auto-written by Terraform on every `make tf-apply` (`local_file.ansible_inventory` in `terraform/main.tf`, from `terraform/templates/inventory.tpl`). Gitignored — never hand-edit. Puts every host from `servers.auto.tfvars` into `all_servers`, `docker_hosts`, and `env_<type>`. |
| `inventory/hosts.static.yml` | Hand-maintained inventory for hosts Terraform doesn't own (a NAS, a router, anything set up outside this repo). Merged in alongside the generated file. Add a host here *and* under the matching `env_<type>` group if it should get packages like a normal server. |
| `inventory/group_vars/all.yml` | Applies to `all_servers` (every host). Defines `common_packages`, `common_compose_stacks` (every host runs these — currently just `node-exporter`), and baseline hardening toggles (`common_ssh_password_auth`, `common_timezone`) used by the `common` role. |
| `inventory/group_vars/env_<type>.yml` | Applies to hosts of that `type` (one file per type: `env_prod.yml`, `env_staging.yml`, `env_uat.yml`, ...). Defines `type_packages`, `type_compose_stacks`, and `common_auto_reboot` for that type. |
| `inventory/host_vars/<hostname>.yml` | Applies to one host only. Typically `host_packages` (extra packages just for this box) and/or `host_compose_stacks` (extra Docker Compose stacks just for this host — unioned with `common_compose_stacks`/`type_compose_stacks`, see the Playbooks section below). |

This gives a **3-layer package model**:
`common_packages` (all.yml) + `type_packages` (env_&lt;type&gt;.yml) + `host_packages` (host_vars) →
unioned and deduped by `roles/packages`.

Compose stack opt-in follows the identical 3-layer shape —
`common_compose_stacks` + `type_compose_stacks` + `host_compose_stacks` →
unioned by `playbooks/deploy-compose.yml` — see the Playbooks section
below.

## Playbooks — what to run

| Path | What it does |
|---|---|
| `playbooks/site.yml` | Main playbook. Targets `all_servers`, applies roles `common` → `packages` → `docker` in order. `make ansible-provision` runs this against everything; `make provision-env ENV=<type>` runs the *same* playbook with `--limit env_<type>` — there's no separate playbook per type. |
| `playbooks/update-all.yml` | `apt update && apt upgrade` across every host, reboots only if required and the host's `common_auto_reboot` allows it. Kept separate from `site.yml` so a routine patch run doesn't also re-assert every role's full state. |
| `playbooks/deploy-compose.yml` | Pushes the whole `compose/<stack>/` directory (compose file + any supporting config, e.g. Grafana provisioning) to whichever hosts resolve `<stack>` into their compose-stacks set — a 3-layer union just like the packages role: `common_compose_stacks` (`group_vars/all.yml`, every host) + `type_compose_stacks` (`group_vars/env_<type>.yml`, per type) + `host_compose_stacks` (`host_vars/<hostname>.yml`, per host). If the stack has a `.env.j2`, it's rendered to `.env` on the host (secrets pulled live from `secrets.sops.yaml`, never committed) so `docker-compose.yml` can reference `${SOME_VAR}`. Hosts that don't opt in are skipped. Run via `make compose-deploy STACK=<name>`. |
| `playbooks/fix-usb-cloud-kernel.yml` | One-off fix for USB passthrough: Debian's cloud kernel flavor ships without `xhci_pci`/`xhci_hcd` drivers, so a passed-through USB controller is invisible to the guest even with correct host/QEMU config. Installs the standard kernel, removes the cloud kernel packages, regenerates GRUB, reboots, then verifies. Disruptive (kernel swap + reboot) — never run by `make apply`, always scoped explicitly. Run via `make fix-usb-kernel LIMIT=<host[,host...]\|group\|all>`. |
| `playbooks/install-webmin.yml` | Installs Webmin (web-based admin panel, :10000) on a host. Downloads a specific, checksummed `.deb` release from GitHub directly, not Webmin's own apt repo — verified live, that repo's GPG key hasn't been updated since 2020 and current Debian apt rejects its SHA-1 signature outright. Opt-in, never run by `make apply`. Run via `make ansible-run PLAYBOOK=install-webmin LIMIT=<host[,host...]\|group\|all>`. |

## Roles — how

| Role | Does |
|---|---|
| `roles/common` | Sets timezone, disables SSH password auth (validates sshd config before applying, restarts sshd only if changed), writes the unattended-upgrades auto-reboot setting. |
| `roles/packages` | Computes `packages_all_layers` as the `union()` of common + type + host package lists, installs them in one `apt` task. |
| `roles/docker` | Installs Docker Engine + Compose plugin from Docker's own apt repo, adds `docker_users` to the `docker` group, creates the compose stacks root (`/opt/compose`), enables and starts the service. |

Each follows the standard role layout: `tasks/main.yml` (what runs),
`defaults/main.yml` (overridable low-precedence vars), `handlers/main.yml`
(notify-triggered actions like service restarts).

## Secrets & dependencies

- `requirements.yml` — Galaxy collections needed: `community.general`
  (timezone), `community.docker` (compose), `community.sops` (secrets
  lookup). Install with `ansible-galaxy collection install -r ansible/requirements.yml`.
- `secrets.sops.yaml` (gitignored, real) / `secrets.sops.yaml.example`
  (committed, shows the shape) — age/SOPS-encrypted. Unlike Terraform's
  secrets, this file is **never decrypted to disk**; playbooks read
  individual keys straight out of it at runtime via
  `(lookup('community.sops.sops', playbook_dir + '/../secrets.sops.yaml') | from_yaml)['some_key']`
  — the full 3-part FQCN (`community.sops.sops`, not `community.sops`) and
  `| from_yaml` (the lookup returns a raw string, not a parsed dict) both
  matter; see `ansible/secrets.sops.yaml.example` for the annotated version.

## Worked example: install `vim` everywhere, `net-tools` in UAT only

Say you need `vim` on every server regardless of type, and `net-tools` on
UAT servers only.

1. **`vim` on every server** → it belongs everywhere, so it's a
   `common_packages` change in `ansible/inventory/group_vars/all.yml`:

   ```yaml
   common_packages:
     - vim   # already here, if using the boilerplate as-is
     - curl
     - htop
     - git
     - ca-certificates
     - unzip
   ```

   (In this repo `vim` is already in the default list — this step is a
   no-op unless you'd removed it. If it were missing, adding the line is
   the whole change.)

2. **`net-tools` on UAT only** → it belongs to one type, so it's a
   `type_packages` change in `ansible/inventory/group_vars/env_uat.yml`:

   ```yaml
   type_packages:
     - tcpdump
     - strace
     - net-tools   # add this line
   ```

3. Apply it:

   ```bash
   # Just UAT, since that's the only group that changed:
   make provision-env ENV=uat

   # Or, if you also touched common_packages (step 1 was a real change),
   # run against everything instead:
   make ansible-provision
   ```

That's the entire change — no new role, no new playbook, no Terraform
involved. `roles/packages` picks up both edits automatically because it
just unions whatever `common_packages`/`type_packages`/`host_packages`
resolve to for each host via normal Ansible variable precedence.
