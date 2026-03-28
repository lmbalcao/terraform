resource "proxmox_vm_qemu" "this" {
  target_node = var.target_node
  name        = var.name
  tags        = length(var.tags) > 0 ? join(";", var.tags) : null
  description = var.description
  vmid        = var.vmid

  ciuser             = var.ci_user
  vm_state           = var.vm_state
  start_at_node_boot = var.start_at_node_boot
  clone              = var.source_clone
  full_clone         = var.source_clone != null
  kvm                = var.kvm_enabled
  nameserver         = var.nameserver
  searchdomain       = var.searchdomain
  scsihw             = var.scsi_hardware
  ipconfig0          = var.network_mode == "dhcp" ? "ip=dhcp" : "ip=${var.network_address},gw=${var.network_gateway}"

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
    tag    = try(var.network_tag > 0, false) ? var.network_tag : null
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

  lifecycle {
    ignore_changes = [sshkeys]

    precondition {
      condition     = var.network_mode == "dhcp" || (var.network_address != null && var.network_gateway != null)
      error_message = "Static VM workloads must define network_address and network_gateway."
    }
  }
}
