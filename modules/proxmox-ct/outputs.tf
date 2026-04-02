output "id" {
  value = proxmox_virtual_environment_container.this.id
}

output "vmid" {
  value = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  value = proxmox_virtual_environment_container.this.initialization[0].hostname
}

output "target_node" {
  value = proxmox_virtual_environment_container.this.node_name
}

output "ipv4_address" {
  value = var.network_mode == "dhcp" ? null : split("/", var.network_ip_cidr)[0]
}
