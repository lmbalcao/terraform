output "id" {
  value = proxmox_lxc.this.id
}

output "vmid" {
  value = proxmox_lxc.this.vmid
}

output "hostname" {
  value = proxmox_lxc.this.hostname
}

output "target_node" {
  value = proxmox_lxc.this.target_node
}

output "ipv4_address" {
  value = var.network_mode == "dhcp" ? null : split("/", var.network_ip_cidr)[0]
}
