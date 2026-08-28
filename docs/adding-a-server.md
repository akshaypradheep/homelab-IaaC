# Adding a server

Adding a server touches exactly one file. Nothing else in the repo
*needs* to change — `make apply` auto-creates the supporting `host_vars`
file for you (see below), though you'll usually go back and edit it for
per-server packages or compose stacks.

1. Open `terraform/servers.auto.tfvars` (copy from
   `servers.auto.tfvars.example` if you don't have one yet) and add an
   entry to the `servers` map:

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

   The map key (`app-staging-02`) becomes the hostname everywhere — Proxmox
   VM name, Ansible inventory hostname, `host_vars/` filename.

2. Converge everything in one command:

   ```
   make apply
   ```

   This creates the VM, regenerates the inventory + monitoring targets,
   auto-creates `ansible/inventory/host_vars/app-staging-02.yml` (a stub
   with `compose_stacks: []`, since one didn't exist yet —
   `scripts/scaffold-inventory.sh` never overwrites a file that's already
   there), runs `ansible-provision` against every host, and deploys every
   compose stack hosts opt into.

   If `staging` is a brand-new `type`, the matching
   `ansible/inventory/group_vars/env_staging.yml` gets auto-created the
   same way — see `docs/adding-a-server-type.md`.

That's it — the new host is now in `all_servers`, `docker_hosts`, and
`env_staging`, and it gets `common_packages` + `type_packages` from
`group_vars/env_staging.yml` automatically.

## If you'd rather step through it manually

`make apply` is a wrapper around these, in case you want to review a plan
before applying or scope a step narrowly:

```
make tf-plan                       # review what would change
make tf-apply                      # create the VM, regenerate inventory
make ansible-provision             # or: make provision-env ENV=staging
```

## If this one server also needs its own extra packages

Edit `ansible/inventory/host_vars/app-staging-02.yml` (auto-created by
`make apply`, or create it yourself if you're stepping through manually):

```yaml
host_packages:
  - some-extra-tool
```

See `docs/commands.md` and the deliverable checklist in the repo root
README for the other "what file do I touch" cases (all servers / one
type / one server).

## If this server should run a Docker Compose stack

Add `compose_stacks: [<stack-name>]` to its `host_vars/<name>.yml`, then
`make apply` (it deploys every stack any host opts into on every run) —
or, to push just that one stack without re-converging everything else:

```
make compose-deploy STACK=<stack-name>
```
