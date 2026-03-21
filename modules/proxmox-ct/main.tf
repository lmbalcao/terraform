resource "proxmox_lxc" "this" {
  target_node = var.target_node
  hostname    = var.hostname
  tags        = length(var.tags) > 0 ? join(";", var.tags) : null
  ostemplate  = var.ostemplate

  unprivileged = var.unprivileged
  vmid         = var.vmid
  password     = var.root_password

  cores  = var.cores
  memory = var.memory_mb
  swap   = var.swap_mb

  onboot = var.on_boot
  start  = var.start

  features {
    nesting = try(var.features.nesting, true)
  }

  ssh_public_keys = length(var.ssh_public_keys) > 0 ? join("\n", var.ssh_public_keys) : null
  nameserver      = var.nameserver
  searchdomain    = var.searchdomain

  rootfs {
    storage = var.rootfs_storage
    size    = "${var.rootfs_size_gb}G"
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    tag    = var.network_tag
    ip     = var.network_mode == "dhcp" ? "dhcp" : var.network_ip_cidr
    gw     = var.network_mode == "dhcp" ? null : var.network_gateway
  }

  lifecycle {
    ignore_changes = [password]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_ip_cidr != null && var.network_gateway != null)
      error_message = "Static CT workloads must define network_ip_cidr and network_gateway."
    }
  }
}
