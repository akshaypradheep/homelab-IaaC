# Clones var.template via cloud-init and applies static networking so the
# `ip` in var.servers is the address Ansible will actually connect to —
# no DHCP-then-discover step needed between tf apply and ansible-provision.

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node
  vm_id     = var.vmid
  tags      = concat(["terraform", "env-${var.type}"], var.tags)

  clone {
    vm_id = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full  = true
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    interface    = "scsi0"
    size         = tonumber(trimsuffix(var.disk_size, "G"))
    file_format  = "raw"
    datastore_id = "local-lvm"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns
    }
    user_account {
      username = "ansible"
      keys     = [var.ssh_public_key]
    }
  }

  # cloud-init only re-runs on boot; changing these post-create requires a
  # reboot Terraform won't force on you automatically, so drift here is
  # expected and intentionally ignored rather than fought on every plan.
  lifecycle {
    ignore_changes = [
      clone,
    ]
  }
}

data "proxmox_virtual_environment_vms" "template" {
  filter {
    name   = "name"
    values = [var.template]
  }
  node_name = var.node
}
