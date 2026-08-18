# Adding a server type

Types are free-form strings — "prod"/"staging"/"uat" are just the ones
this template ships with. Adding a new one (say, "dr" or "edge") requires
exactly two things, and no changes to any Terraform module or Ansible
role:

1. **Create `ansible/inventory/group_vars/env_dr.yml`:**

   ```yaml
   type_packages:
     - some-dr-specific-tool
   ```

   The filename must match `env_<type>`, because that's the group name the
   inventory template (`terraform/templates/inventory.tpl`) derives from
   whatever string you put in `type` — see step 2.

2. **Use `type = "dr"` on any server in `terraform/servers.auto.tfvars`:**

   ```hcl
   servers = {
     backup-dr-01 = {
       type = "dr"
       # ...
     }
   }
   ```

3. `make tf-apply` (regenerates the inventory with a new `env_dr` group)
   then `make ansible-provision` or `make provision-env ENV=dr`.

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
