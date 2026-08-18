# variables.tf — the single input surface for the whole homelab.
# Everything Ansible knows about a host is derived from `servers` below;
# there is no second place that declares a server.

variable "servers" {
  description = <<-EOT
    One entry per server. `type` drives both the Ansible inventory group
    (env_<type>) and which group_vars/env_<type>.yml package layer applies.
    Adding a server = adding one entry here; adding a type = adding one
    group_vars/env_<type>.yml file (see docs/adding-a-server-type.md).
  EOT
  type = map(object({
    type      = string           # prod | staging | uat | ... (free-form, must match a group_vars/env_<type>.yml)
    node      = string           # Proxmox node to create the VM on
    template  = string           # name of the Proxmox VM template to clone
    vmid      = optional(number) # pin a VMID; omitted lets Proxmox pick one
    cores     = optional(number, 2)
    memory    = optional(number, 2048) # MiB
    disk_size = optional(string, "20G")
    ip        = string # CIDR, e.g. "10.0.0.10/24" — static, matches homelab convention
    gateway   = string
    dns       = optional(list(string), ["1.1.1.1", "9.9.9.9"])
    tags      = optional(list(string), [])
  }))
}

variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://pve.homelab.lan:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=uuid). Comes from the decrypted tfvars, never committed."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification against the Proxmox API — homelabs commonly run self-signed certs."
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "Public key injected into every VM via cloud-init; Ansible connects with the matching private key."
  type        = string
}
