output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "ip" {
  value = split("/", var.ip)[0]
}
