# main.tf — orchestration only. All provider-specific VM logic lives in
# modules/server so swapping Proxmox for something else later is a
# module-boundary change, not a rewrite of this file.

terraform {
  # >= 1.9.0 (not 1.7.0): variables.tf uses multiple `validation` blocks
  # per variable, only supported from 1.9.0 onward.
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # 3-component constraint deliberately: for a pre-1.0 provider, a
      # 2-component "~> 0.66" allows anything up to <1.0 (any 0.x minor) —
      # this repo was actually running 0.111.1 under that constraint
      # without anyone deciding to upgrade. Pinned to what's verified
      # working; bump deliberately (and re-verify) to move it.
      version = "~> 0.111.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

module "server" {
  source = "./modules/server"

  for_each = var.servers

  name           = each.key
  type           = each.value.type
  node           = each.value.node
  template       = each.value.template
  vmid           = each.value.vmid
  cores          = each.value.cores
  memory         = each.value.memory
  disk_size      = each.value.disk_size
  datastore_id   = each.value.datastore_id
  ip             = each.value.ip
  gateway        = each.value.gateway
  dns            = each.value.dns
  tags           = each.value.tags
  ssh_public_key = var.ssh_public_key
}

# Single hand-off point to Ansible. This file is gitignored and regenerated
# on every apply — never hand-edit it, edit var.servers instead.
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    servers   = var.servers
    generated = timestamp()
  })
  filename        = "${path.module}/../ansible/inventory/hosts.generated.yml"
  file_permission = "0640"
}

# Prometheus file_sd target list, keyed the same way as the inventory so the
# monitoring stack's host labels line up with Ansible's env_<type> groups.
resource "local_file" "prometheus_targets" {
  # Trailing newline deliberately appended: jsonencode() alone produces
  # none. Without it this never byte-matches what's already deployed on a
  # host, so deploy-compose.yml's push task reports "changed" (and
  # force-recreates the container) on literally every single deploy,
  # whether or not any target actually changed — see docs/architecture.md.
  content = "${jsonencode([
    for name, s in var.servers : {
      targets = ["${split("/", s.ip)[0]}:9100"]
      labels = {
        host = name
        type = s.type
      }
    }
  ])}\n"
  filename        = "${path.module}/../compose/monitoring/targets.generated.json"
  file_permission = "0640"
}
