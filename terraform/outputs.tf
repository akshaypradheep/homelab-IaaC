output "server_ips" {
  description = "Map of server name -> assigned IP, handy for a quick sanity check after apply."
  value       = { for name, s in var.servers : name => split("/", s.ip)[0] }
}

output "inventory_path" {
  description = "Where the generated Ansible inventory landed."
  value       = local_file.ansible_inventory.filename
}
