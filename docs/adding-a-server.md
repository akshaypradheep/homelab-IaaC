# Adding a server

Adding a server touches exactly one file.

## 1. Add an entry to `terraform/servers.auto.tfvars`

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

The map key (`app-staging-02`) becomes the hostname everywhere: the Proxmox
VM name, the Ansible inventory hostname, the `host_vars/` filename.

## 2. Run it

```bash
make apply
```

This creates the VM, regenerates the inventory, provisions every host, and
deploys every compose stack hosts opt into. For this new host, it also:

- Auto-creates `ansible/inventory/host_vars/app-staging-02.yml` (a stub —
  it never overwrites a file that's already there).
- Adds it to `common_compose_stacks` automatically (currently just
  `node-exporter`) — no edits needed for that.
- If `staging` is a brand-new type, also creates
  `ansible/inventory/group_vars/env_staging.yml` — see
  [`adding-a-server-type.md`](adding-a-server-type.md).

That's it — the new host is now in `all_servers`, `docker_hosts`, and
`env_staging`.

## Optional: extra packages just for this server

Edit `ansible/inventory/host_vars/app-staging-02.yml`:

```yaml
host_packages:
  - some-extra-tool
```

## Optional: run a Docker Compose stack on this server

Add to the same file:

```yaml
host_compose_stacks:
  - some-stack
```

This is *in addition to* whatever `common_compose_stacks`/`type_compose_stacks`
already give it, not a replacement — see
[`ansible-layout.md`](ansible-layout.md). Then:

```bash
make compose-deploy STACK=some-stack
```

## Prefer to step through it manually?

```bash
make tf-plan            # review what would change
make tf-apply            # create the VM, regenerate inventory
make ansible-provision   # or: make provision-env ENV=staging
```
