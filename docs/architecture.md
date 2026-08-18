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

## Secrets

- `terraform/secrets.sops.yaml` (age-encrypted) -> decrypted by
  `scripts/decrypt-tf-secrets.sh` to a gitignored
  `terraform.auto.tfvars.json` right before plan/apply. Terraform state
  itself still contains secrets in plaintext (normal Terraform caveat) —
  keep state out of git and treat it as sensitive.
- `ansible/secrets.sops.yaml` (age-encrypted) -> read live by playbooks via
  the `community.sops` lookup plugin. It is never decrypted to disk on the
  control node.
- Both are encrypted against the same age keypair (`scripts/age-keygen.sh`,
  configured in `.sops.yaml`).
