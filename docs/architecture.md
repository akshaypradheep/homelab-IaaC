# Architecture

Single source of truth, one direction of data flow:

```
Terraform (Proxmox, via bpg/proxmox)
  reads terraform/servers.auto.tfvars  ->  var.servers (map, one entry per server)
  for_each over var.servers            ->  modules/server (one instance per server)
  renders, on every apply:
    - ansible/inventory/hosts.generated.yml   (Ansible's hand-off)
    - compose/monitoring/targets.generated.json (Prometheus file_sd)
        |
        v
Ansible
  inventory = hosts.generated.yml (Terraform-owned) + hosts.static.yml (hand-maintained)
  site.yml applies to every host, roles in order:
    common -> packages -> docker -> (per-server-type roles)
  deploy-compose.yml pushes one compose/<stack>/docker-compose.yml
  to whichever hosts opt in via the common/type/host_compose_stacks union
        |
        v
Docker Compose stacks running on each server
```

## Why one direction

Terraform is the only thing that writes `hosts.generated.yml`. Nothing
else edits it, and it's gitignored — it's a build artifact, not a source
file. If you find yourself tempted to hand-edit it, that's a sign the
change belongs in `servers.auto.tfvars` instead. Hosts that Terraform
doesn't own (a NAS, a router, anything you set up outside this repo) go in
`hosts.static.yml`, which Ansible merges in alongside the generated file —
see `ansible/ansible.cfg`.

## Why `type` drives both inventory grouping and packages

Every server declares a `type` (prod/staging/uat/...) once, in
`servers.auto.tfvars`. The inventory template
(`terraform/templates/inventory.tpl`) turns that into an `env_<type>`
group. Ansible's normal variable precedence then does the rest —
`group_vars/env_<type>.yml` only applies to hosts in that group. There's
no second place `type` has to be declared and no custom merge code: it's
just how Ansible groups and variable files already work. See
`docs/adding-a-server-type.md` for what "extensible" means in practice.

## Why the packages role is three flat lists, not a templating engine

`common_packages` (group_vars/all.yml) + `type_packages`
(group_vars/env_<type>.yml) + `host_packages` (host_vars/<host>.yml) get
unioned and deduped by one `ansible.builtin.apt` task
(`roles/packages/tasks/main.yml`). That's the entire mechanism. A fancier
merge engine would solve a problem this repo doesn't have — three lists
and `union()` cover every case in the deliverable checklist.

## Why Terraform's VM logic is one module

`terraform/modules/server` is the only place that talks to the Proxmox
provider. `main.tf` just does `for_each` over `var.servers` and calls it.
If this homelab ever moves off Proxmox, that module's `main.tf` is the
only file that should need a rewrite — the module's input variables
(`variables.tf`) are deliberately generic (name/cores/memory/disk/ip/...)
rather than Proxmox-shaped.

## `make apply` — the single entrypoint

`scripts/apply.sh` is what `make apply` runs, and it's just an
orchestrator over the pieces above — it doesn't duplicate any of their
logic:

1. `scripts/scaffold-inventory.sh` — reads `var.servers` straight from
   Terraform (`terraform console`, no network calls for a plain
   input-variable expression) and creates any missing
   `host_vars/<name>.yml` / `group_vars/env_<type>.yml` **only if that
   file doesn't already exist**. It never overwrites, never deletes.
   This deliberately mirrors the asymmetry above: `hosts.generated.yml`
   is Terraform-owned and disposable because nothing hand-edits it;
   `host_vars`/`group_vars` are the opposite — genuinely hand-maintained
   (`host_packages`, `host_compose_stacks`, `type_packages` aren't derivable
   from `servers.auto.tfvars` at all), so scaffolding can only ever *add*
   a starting point, never manage the file's ongoing content.
2. `terraform apply` — same as `make tf-apply`, applied from a saved plan
   (`-out=tfplan`) so creates/updates go through unattended. Before that
   apply, the plan is inspected specifically for any
   `proxmox_virtual_environment_vm` resource with a `delete` action (a
   real VM being removed or replaced) — if found, it stops and asks for
   explicit confirmation. The `local_file` resources (inventory,
   Prometheus targets) get replaced on every apply as a matter of course;
   that's not gated, since it's just a regenerated text file, not
   infrastructure.
3. `scripts/trust-host-keys.sh` — regenerates `ansible/ssh_known_hosts`
   from a fresh `ssh-keyscan` against every server, so the Ansible steps
   below can verify SSH host keys instead of skipping verification. See
   "Security posture" below for the trust model this actually provides.
4. `ansible-playbook playbooks/site.yml` — same as `make ansible-provision`.
5. `ansible-playbook playbooks/deploy-compose.yml -e stack=<name>` for
   every directory under `compose/*/` that has a `docker-compose.yml` —
   no separate "which stacks exist" registry; it just iterates what's on
   disk, and each host's compose-stacks opt-in still decides who actually
   gets each one — same 3-layer union as the packages role (see
   `docs/ansible-layout.md`).

Every step here is also independently reachable as its own `make` target
(`tf-plan`, `tf-apply`, `ansible-provision`, `provision-env`,
`compose-deploy`) for when you want to review or scope a change instead
of converging everything.

## `deploy-compose.yml`'s idempotency gotchas

Three real bugs, found only by actually running this repeatedly against
live hosts rather than by reading the code — each one made `changed`
report `true` (or a container silently go stale) on runs where nothing
should have happened:

- **A running container can silently keep watching a deleted file.**
  Docker binds an individual file (not a directory) into a container by
  *inode*, not by path. `ansible.builtin.copy` replaces a changed file via
  an atomic write-then-rename — a new inode at the same path — so a
  container whose `docker-compose.yml` itself didn't change (only a file
  it bind-mounts, e.g. `prometheus.yml`/`targets.generated.json`) keeps
  looking at the old, now-unlinked inode forever, with nothing logged.
  Fixed by tracking whether the file-push task actually changed anything
  (`pushed_files`) and setting `recreate: always` on `docker_compose_v2`
  only when it did — `auto` (Docker's own default) otherwise, so a no-op
  deploy stays a no-op.
- **`directory_mode` only applies to directories `copy` creates**, not
  ones that already exist from an earlier run under different settings —
  a directory built before this repo's `directory_mode` was tightened to
  `0755` stayed at its old mode forever, both reporting spurious
  `changed` on every run *and* meaning a container's non-root user
  couldn't actually traverse into it. Fixed with an explicit
  `find ... -exec chmod 0755` pass after every push (`changed_when:
  false` — this is normalization, not a real-change signal).
- **Don't delete a file the copy step will just re-add.** The unrendered
  `.env.j2` used to get deleted right after rendering `.env` from it —
  which meant the *next* run's directory copy always found `.env.j2`
  "missing" versus the source tree and re-pushed it, permanently
  reporting `changed`. `.env.j2` is harmless left in place (compose only
  reads `docker-compose.yml`/`.env`, and it holds no secret, just the
  template), so it's no longer deleted.

Also: `local_file.prometheus_targets`'s content gets an explicit trailing
newline appended in `terraform/main.tf` — `jsonencode()` alone doesn't
produce one, and without it the generated file can never byte-match what
actually lands on a host, which is the same "permanent false `changed`"
failure mode as above.

## Secrets

- `terraform/secrets.sops.yaml` (age-encrypted) -> decrypted by
  `scripts/decrypt-tf-secrets.sh` to a gitignored
  `terraform.auto.tfvars.json` right before plan/apply. Terraform state
  itself still contains secrets in plaintext (normal Terraform caveat) —
  keep state out of git and treat it as sensitive. The same is true of
  `scripts/apply.sh`'s saved plan file (`terraform/tfplan`) — marking a
  variable `sensitive` in `variables.tf` only redacts CLI output, not the
  plan file's own contents — which is why that script deletes it
  immediately after use (`trap cleanup EXIT`) and it's gitignored as a
  backstop.
- `ansible/secrets.sops.yaml` (age-encrypted) -> read live by playbooks via
  the `community.sops.sops` lookup plugin (see
  `ansible/secrets.sops.yaml.example` for the exact, verified-working
  syntax — the FQCN and `| from_yaml` both matter). It is never decrypted
  to disk on the control node.
- Both are encrypted against the same age keypair (`scripts/age-keygen.sh`,
  configured in `.sops.yaml`).

## Security posture

Known trade-offs and hardening decisions, stated plainly rather than left
implicit:

- **SSH host keys are verified, not skipped.** `ansible.cfg` used to set
  `host_key_checking = False` (never verify, ever). It now points at
  `ansible/ssh_known_hosts`, which `scripts/trust-host-keys.sh` regenerates
  from a fresh `ssh-keyscan` on every `make apply`, right after Terraform
  creates/updates VMs. This is trust-on-first-use, not out-of-band
  verification — a real improvement (an attacker now has to be
  actively MITM-ing during that specific scan, not just at any point
  during any future SSH session) but not a substitute for verifying a key
  fingerprint through some channel other than the network you're trying to
  secure.
- **`PermitRootLogin no` and `PasswordAuthentication no`** are asserted by
  `roles/common` on every host (SSH key-only, non-root login only) —
  `common_permit_root_login` / `common_ssh_password_auth` exist as the
  single override points if a type ever genuinely needs otherwise, same
  pattern as every other common_* toggle.
- **`proxmox_insecure = true` by default** (`terraform/variables.tf`) skips
  TLS verification against the Proxmox API — the privileged
  `proxmox_api_token` is sent over a connection that doesn't verify the
  server's identity. This is a deliberate, documented default for the
  common homelab case (self-signed cert), not an oversight — if you put a
  real cert on Proxmox, set it to `false`.
- **The Proxmox API token should not be `root@pam`.** This repo can't
  enforce that (it's a Proxmox-side user/role decision, not something
  Terraform config controls), but a token scoped to a dedicated role with
  only VM-management permissions is the least-privilege choice — worth
  doing before treating this as production-grade.
- **Every compose image is pinned to a specific version**, not `:latest` —
  see the comment at the top of `compose/monitoring/docker-compose.yml`
  for the verify-before-bumping process. Every service also sets
  `security_opt: no-new-privileges:true` and a `mem_limit`/`cpus` ceiling.
- **Terraform provider constraints are 3-component** (`~> 0.111.0`, not
  `~> 0.66`) — for a pre-1.0 provider, a 2-component constraint allows any
  minor version up to `<1.0`, which is how this repo ended up running
  0.111.1 under a nominal "0.66" constraint without anyone deciding to
  upgrade. `ansible/requirements.yml` collections are pinned the same way,
  for the same reason (unreviewed code landing silently otherwise).
- **`terraform/variables.tf` validates server names, `type`, and
  `disk_size`** — these strings become filenames
  (`scripts/scaffold-inventory.sh` writes `host_vars/<name>.yml` and
  `group_vars/env_<type>.yml`) and Proxmox tags, so a malformed value fails
  fast with a clear message instead of a confusing failure downstream (or,
  in the scaffold script's case, a path outside the intended directory —
  it independently re-validates the same charset rather than trusting
  Terraform's validation alone, since `terraform console` is what actually
  reads `var.servers` there).
