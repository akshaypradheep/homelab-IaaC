# Adding a server

Adding a server touches exactly one file (plus, optionally, a host_vars
file for per-server packages). Nothing else in the repo needs to change.

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

2. Create the VM and regenerate the inventory + monitoring targets:

   ```
   make tf-apply
   ```

3. Configure it:

   ```
   make ansible-provision
   ```

   (Or scope to just its type: `make provision-env ENV=staging`.)

That's it — the new host is now in `all_servers`, `docker_hosts`, and
`env_staging`, and it gets `common_packages` + `type_packages` from
`group_vars/env_staging.yml` automatically.

## If this one server also needs its own extra packages

Add `ansible/inventory/host_vars/app-staging-02.yml`:

```yaml
host_packages:
  - some-extra-tool
```

That's the only case that needs a second file — see
`docs/commands.md` and the deliverable checklist in the repo root README
for the other "what file do I touch" cases (all servers / one type /
one server).

## If this server should run a Docker Compose stack

Add `compose_stacks: [<stack-name>]` to its `host_vars/<name>.yml`, then:

```
make compose-deploy STACK=<stack-name>
```
