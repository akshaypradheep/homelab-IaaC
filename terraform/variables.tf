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
    type         = string           # prod | staging | uat | ... (free-form, must match a group_vars/env_<type>.yml)
    node         = string           # Proxmox node to create the VM on
    template     = string           # name of the Proxmox VM template to clone
    vmid         = optional(number) # pin a VMID; omitted lets Proxmox pick one
    cores        = optional(number, 2)
    memory       = optional(number, 2048) # MiB
    disk_size    = optional(string, "20G")
    datastore_id = optional(string, "local-lvm") # Proxmox storage to create the disk on
    ip           = string # CIDR, e.g. "10.0.0.10/24" — static, matches homelab convention
    gateway      = string
    dns          = optional(list(string), ["1.1.1.1", "9.9.9.9"])
    tags         = optional(list(string), [])
  }))

  # Server names (map keys) end up as: the Proxmox VM name, the Ansible
  # inventory hostname, and a filename in both scripts/scaffold-inventory.sh
  # (host_vars/<name>.yml) and Terraform's own state. Keeping this to a safe
  # charset up front turns a typo into one clear error instead of a
  # confusing failure somewhere downstream.
  validation {
    condition = alltrue([
      for name in keys(var.servers) : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name))
    ])
    error_message = "Server names (the map keys in `servers`) must be lowercase alphanumeric with internal hyphens only, e.g. \"web-prod-01\" — they become a Proxmox VM name, an Ansible hostname, and a filename."
  }

  # `type` becomes an `env_<type>.yml` filename (scripts/scaffold-inventory.sh
  # and docs/adding-a-server-type.md) and a Proxmox tag (`env-<type>`) — same
  # reasoning as the server-name check above.
  validation {
    condition = alltrue([
      for s in values(var.servers) : can(regex("^[a-z0-9_-]+$", s.type))
    ])
    error_message = "Each server's `type` must be lowercase alphanumeric with hyphens/underscores only — it becomes an env_<type>.yml filename and a Proxmox tag."
  }

  # modules/server/main.tf parses this with trimsuffix(..., "G") — GB only,
  # no unit conversion exists for anything else. Catch a malformed value
  # (wrong case, wrong/missing unit) here with a clear message instead of a
  # cryptic tonumber() failure mid-apply.
  validation {
    condition = alltrue([
      for s in values(var.servers) : can(regex("^[0-9]+G$", s.disk_size))
    ])
    error_message = "Each server's `disk_size` must be a whole number of gigabytes followed by an uppercase G, e.g. \"20G\" (no other unit is supported)."
  }
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
  description = <<-EOT
    Skip TLS verification against the Proxmox API. Defaults to true because
    homelabs commonly run self-signed certs — but this means the highly
    privileged `proxmox_api_token` above is sent over a connection that
    doesn't verify the server's identity, which is a real MITM exposure on
    a shared/untrusted network. If you put a real cert on Proxmox (or trust
    its self-signed cert via your OS/CA bundle instead), set this to false.
  EOT
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "Public key injected into every VM via cloud-init; Ansible connects with the matching private key."
  type        = string
}
