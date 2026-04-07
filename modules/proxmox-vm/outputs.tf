output "id" {
  value = proxmox_vm_qemu.this.id
}

output "vmid" {
  value = proxmox_vm_qemu.this.vmid
}

output "name" {
  value = proxmox_vm_qemu.this.name
}

output "target_node" {
  value = proxmox_vm_qemu.this.target_node
}

output "network_address" {
  value = var.network_address
}
