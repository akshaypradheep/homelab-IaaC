# The complete guide

One doc that walks through everything: how the pieces are wired together,
and a worked example for every common task. If you only read one doc in
this repo, read this one.

- [1. The big picture](#1-the-big-picture)
- [2. The three files that control everything](#2-the-three-files-that-control-everything)
- [3. What `make apply` actually does](#3-what-make-apply-actually-does)
- [4. Recipes](#4-recipes)
  - [Add a new server](#add-a-new-server)
  - [Add a new server type](#add-a-new-server-type)
  - [Install a package on every server](#install-a-package-on-every-server)
  - [Install a package on every server of one type](#install-a-package-on-every-server-of-one-type)
  - [Install a package on one server only](#install-a-package-on-one-server-only)
  - [Turn on a system-wide setting (e.g. the firewall)](#turn-on-a-system-wide-setting-eg-the-firewall)
  - [Turn on that setting for one type only](#turn-on-that-setting-for-one-type-only)
  - [Run a playbook against everything / one type / one server](#run-a-playbook-against-everything--one-type--one-server)
  - [Set up a service on just one server](#set-up-a-service-on-just-one-server)
  - [Deploy a Docker Compose stack](#deploy-a-docker-compose-stack)
- [5. Cheat sheet](#5-cheat-sheet)

---

## 1. The big picture

Three tools, one direction of data flow:

```
You edit terraform/servers.auto.tfvars
        |
        v
Terraform creates/updates the VMs on Proxmox,
and writes ansible/inventory/hosts.generated.yml automatically
        |
        v
Ansible reads that inventory, figures out which group each
server is in (all_servers, docker_hosts, env_<type>), and applies
site.yml — a fixed list of roles, most of which quietly do nothing
unless a server opts in
        |
        v
Docker Compose stacks get pushed to whichever servers opted into them
```

You never hand-write the Ansible inventory, and you never manually SSH in
to install something — you always go back to a config file and re-run
`make apply`.

## 2. The three files that control everything

Almost every "how do I configure X" question comes down to picking the
right one of these three:

| File | Applies to | Example use |
|---|---|---|
| `ansible/inventory/group_vars/all.yml` | **Every server**, no exceptions | "Every server should have `curl` installed" |
| `ansible/inventory/group_vars/env_<type>.yml` | **Every server of one type** (e.g. every `prod` server) | "Every prod server should run `fail2ban`" |
| `ansible/inventory/host_vars/<hostname>.yml` | **One specific server** | "Only `jellyfin-01` needs the `ffmpeg` package" |

These three files always get combined — a server gets what's in `all.yml`,
*plus* what's in its type's file, *plus* what's in its own file. Nothing
you set at a wider level ever needs to be repeated at a narrower one.

This same "all / type / one server" shape is used for four different
things in this repo:

| What | Variable names | Who applies it |
|---|---|---|
| Packages to install | `common_packages` / `type_packages` / `host_packages` | `roles/packages` |
| Docker Compose stacks to run | `common_compose_stacks` / `type_compose_stacks` / `host_compose_stacks` | `playbooks/deploy-compose.yml` |
| Firewall ports to open | `common_firewall_ports` / `type_firewall_ports` / `host_firewall_ports` | `roles/common` |
| Whether the firewall is even on | plain `common_firewall_enabled` (override in a type/host file, not a union — see the recipe below) | `roles/common` |

Once you've internalized this table, every recipe below is really just
"which of these three files do I edit, and with which variable."

## 3. What `make apply` actually does

Run this after any change, to any file:

```bash
make apply
```

It does five things, in order:

1. **Create/update servers.** Reads `terraform/servers.auto.tfvars`,
   creates or updates VMs on Proxmox to match. If a server was removed
   from the file, it asks before destroying the matching VM — everything
   else runs unattended.
2. **Regenerate the inventory.** Writes
   `ansible/inventory/hosts.generated.yml` — the list of servers Ansible
   will configure, and which groups (`all_servers`, `docker_hosts`,
   `env_<type>`) each one is in. You never edit this file by hand.
3. **Scaffold missing config files.** If you added a server or a brand
   new type, it creates an empty `host_vars/<name>.yml` or
   `group_vars/env_<type>.yml` stub for you — it never overwrites one
   that already exists.
4. **Provision every server** — runs `site.yml` (see below) against
   every server in the inventory.
5. **Deploy every Compose stack** that at least one server opts into.

`site.yml` is the playbook that does step 4. It applies a fixed list of
roles to every server:

```yaml
roles:
  - common          # timezone, SSH hardening, firewall (if enabled)
  - packages        # installs the common + type + host package union
  - docker          # installs Docker, so Compose stacks can run
  - usb-kernel-fix   # only does something if usb_mounts is set
  - usb-mounts       # only does something if usb_mounts is set
  - webmin           # only does something if install_webmin: true
```

The first three always run. The last three are **opt-in** — they check a
variable, and do nothing at all if it isn't set. This is the same pattern
used everywhere in this repo: a role or task looks for a variable, and
quietly no-ops if that host doesn't define it. That's what makes it safe
to run `make apply` against every server, every time, without it doing
something unwanted to a server that doesn't need it.

## 4. Recipes

### Add a new server

**Edit:** `terraform/servers.auto.tfvars`

```hcl
servers = {
  # ...existing entries...

  app-staging-02 = {
    type      = "staging"
    node      = "pve1"
    template  = "debian12-cloudinit"
    cores     = 2
    memory    = 2048
    disk_size = "20G"
    ip        = "10.0.20.13/24"
    gateway   = "10.0.20.1"
  }
}
```

**Run:** `make apply`

That's it. The map key (`app-staging-02`) becomes the hostname
everywhere — the Proxmox VM name, the Ansible inventory hostname, and the
`host_vars/` filename `make apply` creates for you. Full walkthrough:
[`adding-a-server.md`](adding-a-server.md).

### Add a new server type

Types are just strings — "prod"/"staging"/"uat" are only what this repo
ships with by default. There's no list of valid types to update anywhere.

**Edit:** `terraform/servers.auto.tfvars` — use the new type on any server:

```hcl
backup-dr-01 = {
  type = "dr"
  # ...
}
```

**Run:** `make apply`

This creates `ansible/inventory/group_vars/env_dr.yml` for you (empty,
the first time). Go back and edit it for whatever that type needs — see
the package recipe below. Full walkthrough:
[`adding-a-server-type.md`](adding-a-server-type.md).

### Install a package on every server

**Edit:** `ansible/inventory/group_vars/all.yml`

```yaml
common_packages:
  - vim
  - curl
  - htop
  - git
  - ca-certificates
  - unzip
  - jq   # <- add your package here
```

**Run:** `make apply` (or `make ansible-provision` to skip the
Terraform/Compose steps and just re-provision).

### Install a package on every server of one type

**Edit:** `ansible/inventory/group_vars/env_<type>.yml`, e.g.
`env_prod.yml`:

```yaml
type_packages:
  - fail2ban
  - unattended-upgrades
  - logrotate
  - jq   # <- add your package here, only prod servers get it
```

**Run:** `make provision-env ENV=prod` (scoped to just that type — faster
than a full `make apply` if that's all that changed).

### Install a package on one server only

**Edit:** `ansible/inventory/host_vars/<hostname>.yml`, e.g.
`jellyfin-01.yml`:

```yaml
host_packages:
  - ffmpeg
```

**Run:** `make apply`, or scope it to just that server:

```bash
cd ansible && ansible-playbook playbooks/site.yml --limit jellyfin-01
```

### Turn on a system-wide setting (e.g. the firewall)

Some settings aren't a list of packages — they're a single on/off switch,
like the firewall. The pattern is different: instead of adding to a list,
you **override the same variable name** in a narrower file. Ansible
always prefers the most specific file that sets a variable.

The firewall (`ufw`) ships in this repo already wired up, **off by
default everywhere** — turning it on for the first time is itself a
recipe:

**Edit:** `ansible/inventory/group_vars/all.yml` to turn it on for
*every* server:

```yaml
common_firewall_enabled: true
common_firewall_ports:
  - 22   # never remove this — it's your only way in over SSH
```

**Run:** `make apply`.

Every server now runs `ufw` with a default-deny policy, SSH open, and
nothing else — unless you also add ports per type or per host (next
recipe). Port 22 is always in the default list specifically so turning
this on can never lock you out.

### Turn on that setting for one type only

Say only `prod` servers should have the firewall on, and a web server in
that group also needs 80/443 open.

**Edit:** `ansible/inventory/group_vars/env_prod.yml`:

```yaml
common_firewall_enabled: true
```

**Edit:** `ansible/inventory/host_vars/web-prod-01.yml` (that one server
needs extra ports — this list is *added to*, not a replacement, same
union pattern as packages):

```yaml
host_firewall_ports:
  - 80
  - 443
```

**Run:** `make provision-env ENV=prod`.

`web-prod-01` ends up with ports 22 (from `all.yml`) + 80 + 443 (from its
own file) open; every other prod server just gets 22.

### Run a playbook against everything / one type / one server

| I want to run it against... | Command |
|---|---|
| Every server | `make ansible-provision` |
| One type | `make provision-env ENV=prod` |
| One server | `make ansible-run PLAYBOOK=site LIMIT=jellyfin-01` |
| Several specific servers | `make ansible-run PLAYBOOK=site LIMIT=jellyfin-01,web-prod-01` |
| A playbook that isn't `site.yml` | `make ansible-run PLAYBOOK=<name> LIMIT=<target>` |

`LIMIT` always accepts the same shapes: one hostname, a comma-separated
list, a group name (`env_prod`), or `all`. Full reference:
[`commands.md`](commands.md#targeting-one-host--several--a-group--everything).

### Set up a service on just one server

"Service" here usually means one of two things — a system-level service
(like Webmin) or a Docker Compose stack. Both follow the same "opt in
from that one server's own file" pattern:

**A system service (e.g. Webmin):** add the flag it checks for to that
server's `host_vars` file:

```yaml
# host_vars/open-media-vault.yml
install_webmin: true
```

Then `make apply`. `site.yml` includes `roles/webmin`, gated on exactly
this flag — see [`ansible-layout.md`](ansible-layout.md#opt-in-roles) for
the other opt-in roles (USB kernel fix, USB drive mounts) that follow the
identical pattern.

**A Docker Compose stack:** see the next recipe.

### Deploy a Docker Compose stack

**Add the stack:** create `compose/<stack-name>/docker-compose.yml`.

**Opt one server into it** — edit its `host_vars/<hostname>.yml`:

```yaml
host_compose_stacks:
  - my-new-stack
```

(Or `type_compose_stacks` in a `group_vars/env_<type>.yml` file for every
server of that type, or `common_compose_stacks` in `group_vars/all.yml`
for every server — same three-file pattern as packages.)

**Run:**

```bash
make compose-deploy STACK=my-new-stack
```

This pushes the whole `compose/my-new-stack/` directory to every server
that opted in, and runs it. A server that didn't opt in is skipped
entirely — nothing is pushed to it.

## 5. Cheat sheet

| I want to... | Edit this file | With this variable | Then run |
|---|---|---|---|
| Add a server | `terraform/servers.auto.tfvars` | — | `make apply` |
| Add a server type | `terraform/servers.auto.tfvars` (use the new `type`) | — | `make apply` |
| Install a package everywhere | `group_vars/all.yml` | `common_packages` | `make apply` |
| Install a package on one type | `group_vars/env_<type>.yml` | `type_packages` | `make provision-env ENV=<type>` |
| Install a package on one server | `host_vars/<name>.yml` | `host_packages` | `make apply` |
| Turn on the firewall everywhere | `group_vars/all.yml` | `common_firewall_enabled: true` | `make apply` |
| Turn on the firewall for one type | `group_vars/env_<type>.yml` | `common_firewall_enabled: true` | `make provision-env ENV=<type>` |
| Open an extra port on one server | `host_vars/<name>.yml` | `host_firewall_ports` | `make apply` |
| Install Webmin on one server | `host_vars/<name>.yml` | `install_webmin: true` | `make apply` |
| Run everything on every server | — | — | `make ansible-provision` |
| Run everything on one type | — | — | `make provision-env ENV=<type>` |
| Run everything on one server | — | — | `make ansible-run PLAYBOOK=site LIMIT=<host>` |
| Add/update a Compose stack | `compose/<stack>/docker-compose.yml` + opt in via `host_compose_stacks`/`type_compose_stacks`/`common_compose_stacks` | — | `make compose-deploy STACK=<stack>` |

For *why* it's built this way (data flow, security posture, known
gotchas): [`architecture.md`](architecture.md). For a file-by-file
reference of everything under `ansible/`: [`ansible-layout.md`](ansible-layout.md).
