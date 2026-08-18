# GENERATED FILE — do not hand-edit.
# Source: terraform/templates/inventory.tpl, rendered by terraform/main.tf
# (local_file.ansible_inventory) from the `servers` variable on every apply.
# Rendered: ${generated}
#
# To change a host's group membership, edit its entry in servers.auto.tfvars
# and re-run `make tf-apply`. Manually-added, non-Terraform hosts belong in
# ansible/inventory/hosts.static.yml instead — ansible.cfg merges both files.
all:
  children:
    all_servers:
      hosts:
%{ for name, s in servers ~}
        ${name}:
          ansible_host: ${split("/", s.ip)[0]}
          server_type: ${s.type}
%{ endfor ~}
    docker_hosts:
      hosts:
%{ for name, s in servers ~}
        ${name}: {}
%{ endfor ~}
%{ for t in distinct([for s in values(servers) : s.type]) ~}
    env_${t}:
      hosts:
%{ for name, s in servers ~}
%{ if s.type == t ~}
        ${name}: {}
%{ endif ~}
%{ endfor ~}
%{ endfor ~}
