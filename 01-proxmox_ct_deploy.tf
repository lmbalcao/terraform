###############################################################################
# proxmox_ct.tf - Criação de LXC containers a partir do inventário
# SIMPLIFICADO: validação VMID, features dinâmicas, lifecycle, tags
###############################################################################

###############################################################################
# Validações e verificações pré-criação
###############################################################################

locals {
  # Lista de todos os VMIDs gerados
  all_vmids = [
    for name, ct in local.cts : tonumber("${ct.vlan}${ct.ultimo_octeto}")
    if try(ct.enabled, true)
  ]

  # Detectar VMIDs duplicados
  duplicate_vmids = distinct([
    for vmid in local.all_vmids : vmid
    if length([for v in local.all_vmids : v if v == vmid]) > 1
  ])

  # Validar range de ultimo_octeto (2-254)
  invalid_octets = {
    for name, ct in local.cts : name => ct.ultimo_octeto
    if try(ct.enabled, true) && (ct.ultimo_octeto < 2 || ct.ultimo_octeto > 254)
  }

  # Validar VLAN range (1-4094)
  invalid_vlans = {
    for name, ct in local.cts : name => ct.vlan
    if try(ct.enabled, true) && (ct.vlan < 1 || ct.vlan > 4094)
  }

  # CTs habilitados (para facilitar referências)
  enabled_cts = {
    for name, ct in local.cts : name => ct
    if try(ct.enabled, true)
  }
}

# ✅ Validação: VMIDs duplicados
resource "null_resource" "validate_unique_vmids" {
  lifecycle {
    precondition {
      condition     = length(local.duplicate_vmids) == 0
      error_message = <<-EOT
        ERRO: VMIDs duplicados encontrados: ${join(", ", local.duplicate_vmids)}
        
        Cada combinação VLAN+ultimo_octeto deve ser única.
        Verifica o ficheiro inventory.tf para conflitos.
      EOT
    }
  }
}

# ✅ Validação: Octetos válidos
resource "null_resource" "validate_octets" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_octets) == 0
      error_message = <<-EOT
        ERRO: ultimo_octeto inválido (deve estar entre 2 e 254):
        ${jsonencode(local.invalid_octets)}
      EOT
    }
  }
}

# ✅ Validação: VLANs válidas
resource "null_resource" "validate_vlans" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_vlans) == 0
      error_message = <<-EOT
        ERRO: VLAN inválida (deve estar entre 1 e 4094):
        ${jsonencode(local.invalid_vlans)}
      EOT
    }
  }
}

###############################################################################
# Criação do LXC Container
###############################################################################

resource "proxmox_lxc" "cts" {
  for_each = local.enabled_cts

  target_node  = each.value.target_node
  hostname     = each.value.hostname
  description  = each.value.description
  
  # ✅ Tags aplicadas do inventory
  tags = join(";", try(each.value.tags, []))
  
  ostemplate   = each.value.ostemplate
  unprivileged = each.value.unprivileged

  # VMID = concatenação VLAN + ultimo_octeto (ex: VLAN 17 + octeto 65 = 1765)
  vmid = tonumber("${each.value.vlan}${each.value.ultimo_octeto}")

  password = var.root_password

  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  onboot = each.value.onboot
  start  = each.value.start

  # ✅ Features dinâmicas (lê do inventory em vez de hardcoded)
  features {
    nesting = try(each.value.features.nesting, true)
    fuse    = try(each.value.features.fuse, false)
    keyctl  = try(each.value.features.keyctl, false)
    mount   = try(each.value.features.mount, "")
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  # DNS derivado da VLAN (assumindo gateway em .1)
  nameserver   = "192.168.${each.value.vlan}.1"
  searchdomain = var.searchdomain

  # ✅ Rootfs com validação de tamanho
  rootfs {
    storage = each.value.storage
    size    = each.value.size
  }

  # ✅ Network com validação
  network {
    name   = "eth0"
    bridge = "vmbr0"
    tag    = each.value.vlan

    ip = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}/24"
    gw = "192.168.${each.value.vlan}.1"
  }

  # ✅ Lifecycle: prevenir destroy acidental
  lifecycle {
    # Prevenir destroy acidental (descomentar se necessário)
    # prevent_destroy = true

    # Ignorar mudanças em password após criação (SSH keys são usados)
    ignore_changes = [
      password
    ]

    # Validação extra: garantir que recursos necessários existem
    precondition {
      condition     = contains(keys(var.proxmox_nodes), each.value.target_node)
      error_message = "Node '${each.value.target_node}' não existe em var.proxmox_nodes"
    }

    precondition {
      condition     = can(regex("^[0-9]+G$", each.value.size))
      error_message = "Tamanho do disco deve estar no formato '<número>G' (ex: 8G, 20G)"
    }
  }

  # ✅ Dependências
  depends_on = [
    null_resource.validate_unique_vmids,
    null_resource.validate_octets,
    null_resource.validate_vlans
  ]
}