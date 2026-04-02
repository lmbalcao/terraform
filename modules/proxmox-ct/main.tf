resource "proxmox_virtual_environment_container" "this" {
  node_name    = var.target_node
  vm_id        = var.vmid
  description  = var.description
  tags         = length(var.tags) > 0 ? var.tags : null
  unprivileged = var.unprivileged
  started      = var.start
  start_on_boot = var.on_boot

  operating_system {
    template_file_id = var.ostemplate
    type             = "unmanaged"
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.rootfs_storage
    size         = var.rootfs_size_gb
  }

  initialization {
    hostname = var.hostname

    dynamic "dns" {
      for_each = var.nameserver != null || var.searchdomain != null ? [1] : []
      content {
        servers = var.nameserver != null ? [var.nameserver] : []
        domain  = var.searchdomain
      }
    }

    ip_config {
      ipv4 {
        address = var.network_mode == "dhcp" ? "dhcp" : var.network_ip_cidr
        gateway = var.network_mode == "dhcp" ? null : var.network_gateway
      }
    }

    user_account {
      password = var.root_password
      keys     = length(var.ssh_public_keys) > 0 ? var.ssh_public_keys : null
    }
  }

  network_interface {
    name    = "eth0"
    bridge  = var.network_bridge
    vlan_id = try(var.network_tag > 0, false) ? var.network_tag : null
  }

  dynamic "mount_point" {
    for_each = var.mountpoints
    content {
      volume    = mount_point.value.volume
      path      = mount_point.value.path
      size      = try(mount_point.value.size, null)
      backup    = try(mount_point.value.backup, null)
      quota     = try(mount_point.value.quota, null)
      replicate = try(mount_point.value.replicate, null)
      shared    = try(mount_point.value.shared, null)
      acl       = try(mount_point.value.acl, null)
      read_only = try(mount_point.value.read_only, null)
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
      nesting = try(features.value.nesting, null)
      keyctl  = try(features.value.keyctl, null)
      fuse    = try(features.value.fuse, null)
      mount   = try(features.value.mount, null) != null ? toset(split(";", features.value.mount)) : null
    }
  }

  lifecycle {
    ignore_changes = [
      operating_system,
      initialization,
      disk[0].datastore_id,
    ]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_ip_cidr != null && var.network_gateway != null)
      error_message = "Static CT workloads must define network_ip_cidr and network_gateway."
    }
  }
}
