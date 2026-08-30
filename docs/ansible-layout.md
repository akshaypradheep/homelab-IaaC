# Ansible directory layout

What each file under `ansible/` is for. See
[`architecture.md`](architecture.md) for *why* it's shaped this way — this
doc is just the *what's where* reference.

## Inventory — who the hosts are, what groups they're in

| Path | What it is |
|---|---|
| `ansible.cfg` | Points at both inventory files, sets the SSH user, checks host keys against `ssh_known_hosts`. |
| `inventory/hosts.generated.yml` | Auto-written by Terraform on every `make tf-apply`. Gitignored — never hand-edit. Every host from `servers.auto.tfvars` lands in `all_servers`, `docker_hosts`, and `env_<type>`. |
| `inventory/hosts.static.yml` | Hand-maintained, for hosts Terraform doesn't own (a NAS, a router, ...). Merged in alongside the generated file. |
| `inventory/group_vars/all.yml` | Applies to every host. Defines `common_packages`, `common_compose_stacks`, and baseline hardening (`common_ssh_password_auth`, `common_timezone`). |
| `inventory/group_vars/env_<type>.yml` | Applies to hosts of that type. One file per type. Defines `type_packages`, `type_compose_stacks`, `common_auto_reboot`. |
| `inventory/host_vars/<hostname>.yml` | Applies to one host only. Usually `host_packages` and/or `host_compose_stacks`. |

## The 3-layer model

Packages and compose stacks both follow the same shape — three lists,
unioned and deduped:

```
common_*  (all.yml, every host)
  + type_*  (env_<type>.yml, per type)
    + host_*  (host_vars/<name>.yml, per host)
      = the full set that host gets
```

`roles/packages` does this for packages. `playbooks/deploy-compose.yml`
does it for compose stacks.

## Playbooks — what to run

| Path | What it does |
|---|---|
| `playbooks/site.yml` | Main playbook. Applies every role below to every host — most gated by a `when:`, so a role only does something on a host that opts in (see "Opt-in roles" below). `make ansible-provision` runs it against everything; `make provision-env ENV=<type>` runs the same playbook scoped to one type. |
| `playbooks/update-all.yml` | `apt update && upgrade`, reboots only if required and allowed (`common_auto_reboot`). Kept separate from `site.yml` so a routine patch run doesn't also re-assert every role. |
| `playbooks/deploy-compose.yml` | Pushes `compose/<stack>/` to whichever hosts opt into `<stack>` (3-layer union above). Renders `.env` from `.env.j2` if present. Run via `make compose-deploy STACK=<name>`. |
| `playbooks/fix-usb-cloud-kernel.yml` | Manual entry point for `roles/usb-kernel-fix` — same logic `site.yml` already runs automatically. Use it to retry just this step. Disruptive (reboots) — always scoped with `LIMIT=`. |
| `playbooks/install-webmin.yml` | Manual entry point for `roles/webmin` — same logic `site.yml` runs automatically for hosts with `install_webmin: true`. |
| `playbooks/mount-usb-drives.yml` | Manual entry point for `roles/usb-mounts` — same logic `site.yml` runs automatically for hosts with `usb_mounts` declared. |

## Roles

| Role | Does | Runs when |
|---|---|---|
| `roles/common` | Timezone, SSH hardening (key-only, no root login), unattended-upgrades. | Always |
| `roles/packages` | Installs the 3-layer package union in one `apt` task. | Always |
| `roles/docker` | Installs Docker Engine + Compose plugin, adds users to the `docker` group, creates `/opt/compose`. | Always |
| `roles/usb-kernel-fix` | Swaps Debian's cloud kernel for the standard one (adds the USB drivers it lacks) and reboots. Idempotent — no-ops (no reboot) once already on the standard kernel. | `usb_mounts` is non-empty in host_vars |
| `roles/usb-mounts` | Mounts each declared USB drive by UUID, persists it in `/etc/fstab`. | `usb_mounts` is non-empty in host_vars |
| `roles/webmin` | Installs Webmin (web admin panel, port 10000). | `install_webmin: true` in host_vars |

## Opt-in roles

`usb-kernel-fix`, `usb-mounts`, and `webmin` are skipped by default —
`site.yml` only runs them for hosts that declare the matching host_var, the
same pattern as `host_packages`/`host_compose_stacks`. See
`host_vars/open-media-vault.yml` for a host that opts into all three, and
[`usb-passthrough.md`](usb-passthrough.md) for the full walkthrough
(including the one manual step, attaching the USB device in Proxmox, that
nothing in this repo can automate).

## Secrets

- `requirements.yml` — Galaxy collections needed (`community.general`,
  `community.docker`, `community.sops`). Install with
  `ansible-galaxy collection install -r ansible/requirements.yml`.
- `secrets.sops.yaml` (gitignored, real) / `.example` (committed, shows the
  shape) — SOPS-encrypted. Never decrypted to disk; playbooks read
  individual keys live via the `community.sops.sops` lookup. See
  `secrets.sops.yaml.example` for the exact syntax.

## Worked example: `vim` everywhere, `net-tools` on UAT only

**`vim` on every server** → belongs everywhere, so it's a `common_packages`
change in `group_vars/all.yml`:

```yaml
common_packages:
  - vim
  - curl
  - htop
```

**`net-tools` on UAT only** → belongs to one type, so it's a
`type_packages` change in `group_vars/env_uat.yml`:

```yaml
type_packages:
  - net-tools
```

Apply it, scoped to just the group that changed:

```bash
make provision-env ENV=uat
```
