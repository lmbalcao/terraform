resource "proxmox_vm_qemu" "this" {
  target_node = var.target_node
  name        = var.name
  tags        = length(var.tags) > 0 ? join(";", var.tags) : null
  vmid        = var.vmid

  vm_state           = var.vm_state
  start_at_node_boot = var.start_at_node_boot
  clone              = var.source_clone
  full_clone         = var.source_clone != null ? true : null

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = "host"
  }

  memory = var.memory_mb

  network {
    id     = 0
    model  = "virtio"
    bridge = var.network_bridge
    tag    = var.network_tag
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.rootfs_storage
          size    = "${var.rootfs_size_gb}G"
        }
      }
    }
  }
}
