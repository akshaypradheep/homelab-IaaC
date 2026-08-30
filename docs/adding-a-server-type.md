# Adding a server type

Types are free-form strings — "prod"/"staging"/"uat" are just what this
template ships with. Adding a new one (say "dr" or "edge") takes one step,
no Terraform or role changes required.

## 1. Use the new type

```hcl
servers = {
  backup-dr-01 = {
    type = "dr"
    # ...
  }
}
```

## 2. Run it

```bash
make apply
```

This creates `ansible/inventory/group_vars/env_dr.yml` for you (a stub, only
the first time):

```yaml
# Auto-created by scripts/scaffold-inventory.sh — edit freely.
type_packages: []
common_auto_reboot: false
```

Edit it for whatever `dr` actually needs:

```yaml
type_packages:
  - some-dr-specific-tool
```

Then apply again (or `make provision-env ENV=dr` to scope just that type)
to install what you added.

## Why nothing else needs to change

- The inventory template creates one `env_<type>` group per distinct `type`
  it finds — it doesn't need to know valid types in advance.
- The `packages` role just reads `type_packages` from whatever `group_vars`
  file matches the host's group — normal Ansible precedence.
- No Terraform module hard-codes a type string; `type` is passed through as
  a plain tag.

## If a type needs more than packages

E.g. a "dr" host needs a backup agent none of the others run. Add a role to
`ansible/playbooks/site.yml`, gated on the group:

```yaml
- role: some-role
  when: "'env_dr' in group_names"
```
