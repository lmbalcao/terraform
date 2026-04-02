resource "proxmox_virtual_environment_vm" "this" {
  node_name    = var.target_node
  vm_id        = var.vmid
  name         = var.name
  description  = var.description
  tags         = length(var.tags) > 0 ? var.tags : null
  started      = var.vm_state == "running"
  on_boot      = var.start_at_node_boot
  scsi_hardware = var.scsi_hardware

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.rootfs_storage
    size         = var.rootfs_size_gb
    file_format  = "raw"
    discard      = "on"
    iothread     = var.scsi_hardware == "virtio-scsi-single"
  }

  network_device {
    model   = "virtio"
    bridge  = var.network_bridge
    vlan_id = try(var.network_tag > 0, false) ? var.network_tag : null
  }

  initialization {
    datastore_id = var.rootfs_storage

    dynamic "dns" {
      for_each = var.nameserver != null || var.searchdomain != null ? [1] : []
      content {
        servers = var.nameserver != null ? [var.nameserver] : []
        domain  = var.searchdomain
      }
    }

    ip_config {
      ipv4 {
        address = var.network_mode == "dhcp" ? "dhcp" : var.network_address
        gateway = var.network_mode == "dhcp" ? null : var.network_gateway
      }
    }

    user_account {
      username = var.ci_user
    }
  }

  dynamic "clone" {
    for_each = var.source_clone != null ? [var.source_clone] : []
    content {
      vm_id = clone.value
      full  = true
    }
  }

  lifecycle {
    ignore_changes = [initialization]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_address != null && var.network_gateway != null)
      error_message = "Static VM workloads must define network_address and network_gateway."
    }
  }
}
