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
  to whichever hosts opt in via their compose_stacks var
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
   (`host_packages`, `compose_stacks`, `type_packages` aren't derivable
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
3. `ansible-playbook playbooks/site.yml` — same as `make ansible-provision`.
4. `ansible-playbook playbooks/deploy-compose.yml -e stack=<name>` for
   every directory under `compose/*/` that has a `docker-compose.yml` —
   no separate "which stacks exist" registry; it just iterates what's on
   disk, and each host's `compose_stacks` opt-in (unchanged) still decides
   who actually gets each one.

Every step here is also independently reachable as its own `make` target
(`tf-plan`, `tf-apply`, `ansible-provision`, `provision-env`,
`compose-deploy`) for when you want to review or scope a change instead
of converging everything.

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
  the `community.sops` lookup plugin. It is never decrypted to disk on the
  control node.
- Both are encrypted against the same age keypair (`scripts/age-keygen.sh`,
  configured in `.sops.yaml`).
