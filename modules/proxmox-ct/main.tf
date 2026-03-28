resource "proxmox_lxc" "this" {
  target_node = var.target_node
  hostname    = var.hostname
  tags        = length(var.tags) > 0 ? join(";", var.tags) : null
  description = var.description
  ostemplate  = var.ostemplate

  unprivileged = var.unprivileged
  vmid         = var.vmid
  password     = var.root_password

  cores  = var.cores
  memory = var.memory_mb
  swap   = var.swap_mb

  onboot = var.on_boot
  start  = var.start

  ssh_public_keys = length(var.ssh_public_keys) > 0 ? join("\n", var.ssh_public_keys) : null
  nameserver      = var.nameserver
  searchdomain    = var.searchdomain

  dynamic "features" {
    for_each = length([
      for value in values(var.features) : value
      if value != null && value != false && value != ""
    ]) > 0 ? [var.features] : []
    content {
      nesting = try(features.value.nesting, null)
      keyctl  = try(features.value.keyctl, null)
      fuse    = try(features.value.fuse, null)
      mknod   = try(features.value.mknod, null)
      mount   = try(features.value.mount, null)
    }
  }

  rootfs {
    storage = var.rootfs_storage
    size    = "${var.rootfs_size_gb}G"
  }

  dynamic "mountpoint" {
    for_each = var.mountpoints
    content {
      key       = mountpoint.value.key
      slot      = mountpoint.value.slot
      mp        = mountpoint.value.mp
      storage   = try(mountpoint.value.storage, null)
      size      = try(mountpoint.value.size, null)
      backup    = try(mountpoint.value.backup, null)
      quota     = try(mountpoint.value.quota, null)
      replicate = try(mountpoint.value.replicate, null)
      shared    = try(mountpoint.value.shared, null)
      acl       = try(mountpoint.value.acl, null)
    }
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    tag    = try(var.network_tag > 0, false) ? var.network_tag : null
    ip     = var.network_mode == "dhcp" ? "dhcp" : var.network_ip_cidr
    gw     = var.network_mode == "dhcp" ? null : var.network_gateway
  }

  lifecycle {
    ignore_changes = [
      ostemplate,
      password,
      rootfs[0].storage,
    ]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_ip_cidr != null && var.network_gateway != null)
      error_message = "Static CT workloads must define network_ip_cidr and network_gateway."
    }
  }
}
