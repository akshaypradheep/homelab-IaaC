# Adding a server type

Types are free-form strings — "prod"/"staging"/"uat" are just the ones
this template ships with. Adding a new one (say, "dr" or "edge") requires
exactly one thing, and no changes to any Terraform module or Ansible
role:

1. **Use `type = "dr"` on any server in `terraform/servers.auto.tfvars`:**

   ```hcl
   servers = {
     backup-dr-01 = {
       type = "dr"
       # ...
     }
   }
   ```

2. `make apply`. `scripts/scaffold-inventory.sh` (which it runs first)
   sees `dr` has no `ansible/inventory/group_vars/env_dr.yml` yet and
   creates a stub:

   ```yaml
   # Auto-created by scripts/scaffold-inventory.sh — edit freely.
   # See docs/adding-a-server-type.md.
   type_packages: []
   common_auto_reboot: false
   ```

   It never overwrites a file that's already there, so this only happens
   once per type. Go back and edit it for whatever packages `dr` actually
   needs:

   ```yaml
   type_packages:
     - some-dr-specific-tool
   ```

   The filename has to match `env_<type>`, because that's the group name
   the inventory template (`terraform/templates/inventory.tpl`) derives
   from whatever string you put in `type` — same reason the scaffold
   script names the stub that way.

   Then `make apply` again (or `make provision-env ENV=dr` to scope just
   that type) to actually install the packages you added.

## Why nothing else needs to change

- The inventory template builds one `env_<type>` group per *distinct*
  `type` value it finds in `var.servers` — it doesn't know the list of
  valid types in advance, so a new one just falls out of the loop.
- The `packages` role reads `type_packages` from whatever `group_vars`
  file matched the host's `env_<type>` group — normal Ansible precedence,
  not something this repo special-cases per type.
- No Terraform module references specific type strings; `type` is passed
  through as an opaque tag.

If a new type needs a role beyond packages (e.g. a "dr" host needs a
backup agent none of the others run), add it to `ansible/playbooks/site.yml`
gated on the group, following the commented-out example already there:

```yaml
- role: some-role
  when: "'env_dr' in group_names"
```
