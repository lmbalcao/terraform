resource "proxmox_lxc" "cts" {
  for_each = local.enabled_cts

  target_node = each.value.target_node
  hostname    = each.value.hostname

  tags         = join(";", try(each.value.tags, []))
  ostemplate   = each.value.ostemplate
  unprivileged = each.value.unprivileged

  vmid = tonumber("${each.value.vlan}${each.value.ultimo_octeto}")

  password = var.root_password

  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  onboot = each.value.onboot
  start  = each.value.start

  features {
    nesting = try(each.value.features.nesting, true)
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  nameserver   = "192.168.${each.value.vlan}.1"
  searchdomain = var.searchdomain

  rootfs {
    storage = each.value.storage
    size    = each.value.size
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    tag    = each.value.vlan

    ip = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}/24"
    gw = "192.168.${each.value.vlan}.1"
  }

  # REMOVIDO:
  # dynamic "mountpoint" { ... }
  # Bind mounts serão aplicados via "pct set" (post step).

  lifecycle {
    ignore_changes = [
      password,
      # IMPORTANTE: como o mp0 vai ser criado fora do Terraform
      mountpoint,
    ]

    precondition {
      condition     = contains(keys(var.proxmox_nodes), each.value.target_node)
      error_message = "Node '${each.value.target_node}' não existe em var.proxmox_nodes"
    }

    precondition {
      condition     = can(regex("^[0-9]+G$", each.value.size))
      error_message = "Tamanho do disco deve estar no formato '<número>G' (ex: 8G, 20G)"
    }
  }

  depends_on = [
    null_resource.validate_unique_vmids,
    null_resource.validate_octets,
    null_resource.validate_vlans,
  ]
}
