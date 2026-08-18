# This module is the ONLY place that speaks Proxmox. If the homelab ever
# moves to a different hypervisor/cloud, only this module's main.tf should
# need rewriting — the input contract here is deliberately provider-agnostic.

variable "name" {
  type = string
}

variable "type" {
  description = "prod | staging | uat | ... — carried through as a Proxmox tag so it's visible outside Terraform too."
  type        = string
}

variable "node" {
  type = string
}

variable "template" {
  type = string
}

variable "vmid" {
  type    = number
  default = null
}

variable "cores" {
  type = number
}

variable "memory" {
  type = number
}

variable "disk_size" {
  type = string
}

variable "ip" {
  type = string
}

variable "gateway" {
  type = string
}

variable "dns" {
  type = list(string)
}

variable "tags" {
  type = list(string)
}

variable "ssh_public_key" {
  type = string
}
