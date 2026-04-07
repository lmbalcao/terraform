resource "proxmox_lxc" "this" {
  target_node  = var.target_node
  vmid         = var.vmid
  description  = var.description
  tags         = length(var.tags) > 0 ? join(",", var.tags) : null
  unprivileged = var.unprivileged
  start        = var.start
  onboot       = var.on_boot
  ostemplate   = var.ostemplate
  hostname     = var.hostname
  password     = var.root_password
  ssh_public_keys = length(var.ssh_public_keys) > 0 ? join("\n", var.ssh_public_keys) : null
  nameserver   = var.nameserver
  searchdomain = var.searchdomain
  cores        = var.cores
  memory       = var.memory_mb
  swap         = var.swap_mb

  rootfs {
    storage = var.rootfs_storage
    size    = "${var.rootfs_size_gb}G"
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    tag    = try(var.network_tag > 0, false) ? var.network_tag : null
    ip     = var.network_mode == "dhcp" ? "dhcp" : var.network_ip_cidr
    gw     = var.network_mode == "dhcp" ? null : var.network_gateway
  }

  dynamic "mountpoint" {
    for_each = { for i, m in var.mountpoints : tostring(i) => m }
    content {
      key     = mountpoint.key
      slot    = tonumber(mountpoint.key)
      storage = mountpoint.value.volume
      mp      = mountpoint.value.path
      size    = try(mountpoint.value.size, "0T")
      backup  = try(mountpoint.value.backup, false)
      quota   = try(mountpoint.value.quota, false)
    }
  }

  dynamic "features" {
    for_each = (
      try(var.features.nesting, false) == true ||
      try(var.features.keyctl, false) == true ||
      try(var.features.fuse, false) == true ||
      try(var.features.mount, null) != null
    ) ? [var.features] : []
    content {
      nesting = try(features.value.nesting, false)
      keyctl  = try(features.value.keyctl, false)
      fuse    = try(features.value.fuse, false)
      mount   = try(features.value.mount, null)
    }
  }

  lifecycle {
    ignore_changes = [
      ostemplate,
      rootfs,
    ]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_ip_cidr != null && var.network_gateway != null)
      error_message = "Static CT workloads must define network_ip_cidr and network_gateway."
    }
  }
}
