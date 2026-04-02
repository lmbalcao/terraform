output "id" {
  value = proxmox_virtual_environment_vm.this.id
}

output "vmid" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "target_node" {
  value = proxmox_virtual_environment_vm.this.node_name
}

output "network_address" {
  value = var.network_address
}
