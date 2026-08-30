# Architecture

One source of truth, one direction of data flow:

```
Terraform (Proxmox, via bpg/proxmox)
  reads terraform/servers.auto.tfvars  ->  var.servers (one entry per server)
  for_each over var.servers            ->  modules/server (one instance per server)
  renders, on every apply:
    - ansible/inventory/hosts.generated.yml     (Ansible's hand-off)
    - compose/monitoring/targets.generated.json (Prometheus file_sd)
        |
        v
Ansible
  inventory = hosts.generated.yml (Terraform-owned) + hosts.static.yml (hand-maintained)
  site.yml applies to every host:  common -> packages -> docker -> (per-type roles)
  deploy-compose.yml pushes one compose/<stack>/ to whichever hosts opt in
        |
        v
Docker Compose stacks running on each server
```

## Why one direction

Terraform is the only thing that writes `hosts.generated.yml`. It's
gitignored — a build artifact, not a source file. Never hand-edit it; if
you need a change there, it belongs in `servers.auto.tfvars` instead.
Hosts Terraform doesn't own (a NAS, a router, ...) go in `hosts.static.yml`,
merged in alongside the generated file.

## Why `type` drives both grouping and packages

Every server declares a `type` once, in `servers.auto.tfvars`. The
inventory template turns that into an `env_<type>` group, and normal
Ansible variable precedence does the rest — `group_vars/env_<type>.yml`
only applies to hosts in that group. No second place to declare `type`, no
custom merge code. See [`adding-a-server-type.md`](adding-a-server-type.md).

## Why packages are three flat lists, not a templating engine

`common_packages` + `type_packages` + `host_packages` get unioned and
deduped by one `apt` task. That's the whole mechanism. A fancier merge
engine would solve a problem this repo doesn't have.

## Why Terraform's VM logic is one module

`terraform/modules/server` is the only thing that talks to the Proxmox
provider — `main.tf` just loops over `var.servers` and calls it. If this
homelab ever moves off Proxmox, that module is the only thing that should
need a rewrite; its input variables are generic (name/cores/memory/...),
not Proxmox-shaped.

## `make apply`, step by step

`scripts/apply.sh` orchestrates the pieces above:

1. **Scaffold** (`scripts/scaffold-inventory.sh`) — reads `var.servers`
   from Terraform and creates any missing `host_vars`/`group_vars` files.
   Only creates, never overwrites or deletes — those files are
   hand-maintained (`host_packages` etc. aren't derivable from
   `servers.auto.tfvars`), so scaffolding just gives you a starting point.
2. **`terraform apply`** — from a saved plan, so creates/updates run
   unattended. If the plan would *delete* a real VM, it stops and asks for
   confirmation first. Regenerated files (inventory, Prometheus targets)
   aren't gated — they're just text output, not infrastructure.
3. **Trust host keys** (`scripts/trust-host-keys.sh`) — refreshes
   `ansible/ssh_known_hosts` via `ssh-keyscan` against every server, so
   Ansible can verify SSH host keys instead of skipping verification.
4. **Provision** — same as `make ansible-provision`.
5. **Deploy compose** — same as `make compose-deploy`, once per
   `compose/*/` directory on disk. No separate "which stacks exist"
   registry; each host's opt-in still decides who actually gets each one.

Every step above also works as its own `make` target (`tf-plan`,
`tf-apply`, `ansible-provision`, `provision-env`, `compose-deploy`) for
when you want to review or scope a change instead of converging
everything.

## `deploy-compose.yml`: known gotchas

Three idempotency bugs, found by running this repeatedly against live
hosts — each made `changed` report `true` (or a container go stale) on
runs where nothing should have happened. All fixed, documented here so
nobody reintroduces them:

- **Bind-mounted files can go stale.** Docker binds a file by inode, not
  path. Replacing a file `docker-compose.yml` itself didn't reference
  (e.g. `prometheus.yml`) left the running container watching a deleted
  inode, silently. Fix: `recreate: always` only when the file-push task
  actually changed something.
- **`directory_mode` doesn't retro-apply.** It only affects directories
  `copy` creates, not ones that already exist from an earlier run. Fix: an
  explicit `chmod` pass after every push.
- **Don't delete a file the next run will just re-add.** `.env.j2` used to
  get deleted after rendering `.env` — so every subsequent run saw it
  "missing" and re-pushed it, permanently reporting `changed`. It's
  harmless left in place, so it's no longer deleted.

Related: `local_file.prometheus_targets` needs an explicit trailing
newline in `terraform/main.tf` (`jsonencode()` doesn't add one) — without
it the generated file can never byte-match what lands on a host, same
false-`changed` failure mode.

## Secrets

- `terraform/secrets.sops.yaml` (age-encrypted) → decrypted by
  `scripts/decrypt-tf-secrets.sh` to a gitignored `terraform.auto.tfvars.json`
  right before plan/apply. Terraform state still contains secrets in
  plaintext (a normal Terraform caveat) — keep state out of git. Same for
  `scripts/apply.sh`'s saved plan (`terraform/tfplan`): `sensitive` only
  redacts CLI output, not the plan file, so the script deletes it right
  after use and it's gitignored as a backstop.
- `ansible/secrets.sops.yaml` (age-encrypted) → read live by playbooks via
  the `community.sops.sops` lookup. Never decrypted to disk.
- Both encrypted against the same age keypair (`scripts/age-keygen.sh`,
  configured in `.sops.yaml`).

## Security posture

Stated plainly rather than left implicit:

- **SSH host keys are verified**, via `ssh_known_hosts` refreshed on every
  `make apply`. This is trust-on-first-use, not out-of-band verification —
  real, but not a substitute for checking a key fingerprint through a
  separate channel.
- **`PermitRootLogin no` / `PasswordAuthentication no`** on every host
  (SSH key-only, non-root). Override points exist (`common_permit_root_login`,
  `common_ssh_password_auth`) if a type ever genuinely needs otherwise.
- **`proxmox_insecure = true` by default** skips TLS verification against
  the Proxmox API. Deliberate default for the common self-signed-cert
  homelab case — set to `false` if you put a real cert on Proxmox.
- **Use a scoped Proxmox API token, not `root@pam`.** This is a Proxmox-side
  decision this repo can't enforce, but least-privilege is worth doing.
- **Compose images are pinned**, never `:latest` — see the comment atop
  `compose/monitoring/docker-compose.yml`. Every service also sets
  `security_opt: no-new-privileges:true` and a memory/CPU ceiling.
- **Provider/collection versions are pinned to 3 components**
  (`~> 0.111.0`, not `~> 0.66`) so nothing upgrades silently underneath you.
- **Input is validated.** `terraform/variables.tf` checks server names,
  `type`, and `disk_size` — these become filenames and Proxmox tags, so a
  bad value fails fast with a clear message instead of a confusing one
  downstream.
