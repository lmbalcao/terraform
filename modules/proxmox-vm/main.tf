resource "proxmox_vm_qemu" "this" {
  target_node = var.target_node
  vmid        = var.vmid
  name        = var.name
  desc        = var.description
  tags        = length(var.tags) > 0 ? join(",", var.tags) : null
  onboot      = var.start_at_node_boot
  scsihw      = var.scsi_hardware

  cores   = var.cpu_cores
  sockets = var.cpu_sockets
  cpu     = "host"
  memory  = var.memory_mb

  disk {
    type     = "scsi"
    slot     = 0
    storage  = var.rootfs_storage
    size     = "${var.rootfs_size_gb}G"
    format   = "raw"
    discard  = "on"
    iothread = var.scsi_hardware == "virtio-scsi-single" ? 1 : 0
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
    tag    = try(var.network_tag > 0, false) ? var.network_tag : -1
  }

  cloudinit_cdrom_storage = var.rootfs_storage
  nameserver              = var.nameserver
  searchdomain            = var.searchdomain
  ciuser                  = var.ci_user

  ipconfig0 = var.network_mode == "dhcp" ? "ip=dhcp" : format(
    "ip=%s,gw=%s",
    var.network_address,
    var.network_gateway
  )

  clone      = var.source_clone
  full_clone = var.source_clone != null ? true : null

  lifecycle {
    ignore_changes = [
      ipconfig0,
      nameserver,
      searchdomain,
      ciuser,
      cloudinit_cdrom_storage,
      clone,
      full_clone,
    ]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_address != null && var.network_gateway != null)
      error_message = "Static VM workloads must define network_address and network_gateway."
    }
  }
}
