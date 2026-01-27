# ct.tf (ou lxc.tf) - Recurso único que cria N CTs a partir do inventário

resource "proxmox_lxc" "cts" {
  for_each = {
  for name, ct in local.cts : name => ct
  if try(ct.enabled, true)
  }

  target_node  = each.value.target_node
  hostname     = each.value.hostname
  description  = each.value.description
  ostemplate   = each.value.ostemplate
  unprivileged = each.value.unprivileged

  # vmid = concat(vlan, campo_meu)  (ex.: 25 + 200 -> 25200; 14 + 13 -> 1413)
  vmid = tonumber("${each.value.vlan}${each.value.campo_meu}")

  password = var.root_password

  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  onboot = each.value.onboot
  start  = each.value.start

  features {
    nesting = true
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  # DNS derivado da VLAN
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

    ip = "192.168.${each.value.vlan}.${each.value.campo_meu}/24"
    gw = "192.168.${each.value.vlan}.1"
  }
}
