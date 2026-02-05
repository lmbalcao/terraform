###############################################################################
# 02-deploy_vm.tf - Criação de VMs QEMU a partir do inventário
# SIMPLIFICADO: validação VMID, lifecycle, tags
###############################################################################

###############################################################################
# Validações e verificações pré-criação
###############################################################################

locals {
  # Lista de todos os VMIDs gerados
  all_vm_vmids = [
    for name, vm in local.vms : tonumber("${vm.vlan}${vm.ultimo_octeto}")
    if try(vm.enabled, true)
  ]

  # Detectar VMIDs duplicados
  duplicate_vm_vmids = distinct([
    for vmid in local.all_vm_vmids : vmid
    if length([for v in local.all_vm_vmids : v if v == vmid]) > 1
  ])

  # Validar range de ultimo_octeto (2-254)
  invalid_vm_octets = {
    for name, vm in local.vms : name => vm.ultimo_octeto
    if try(vm.enabled, true) && (vm.ultimo_octeto < 2 || vm.ultimo_octeto > 254)
  }

  # Validar VLAN range (1-4094)
  invalid_vm_vlans = {
    for name, vm in local.vms : name => vm.vlan
    if try(vm.enabled, true) && (vm.vlan < 1 || vm.vlan > 4094)
  }
}

# ✅ Validação: VMIDs duplicados
resource "null_resource" "validate_unique_vm_vmids" {
  lifecycle {
    precondition {
      condition     = length(local.duplicate_vm_vmids) == 0
      error_message = <<-EOT
        ERRO: VMIDs duplicados encontrados: ${join(", ", local.duplicate_vm_vmids)}
        
        Cada combinação VLAN+ultimo_octeto deve ser única.
        Verifica o ficheiro inventory.tf para conflitos.
      EOT
    }
  }
}

# ✅ Validação: Octetos válidos
resource "null_resource" "validate_vm_octets" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_vm_octets) == 0
      error_message = <<-EOT
        ERRO: ultimo_octeto inválido (deve estar entre 2 e 254):
        ${jsonencode(local.invalid_vm_octets)}
      EOT
    }
  }
}

# ✅ Validação: VLANs válidas
resource "null_resource" "validate_vm_vlans" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_vm_vlans) == 0
      error_message = <<-EOT
        ERRO: VLAN inválida (deve estar entre 1 e 4094):
        ${jsonencode(local.invalid_vm_vlans)}
      EOT
    }
  }
}

###############################################################################
# Criação da VM QEMU
###############################################################################

resource "proxmox_vm_qemu" "vms" {
  for_each = local.enabled_vms

  target_node = each.value.target_node
  name        = each.value.name

  # ✅ Tags aplicadas do inventory
  tags = join(";", try(each.value.tags, []))

  # VMID = concatenação VLAN + ultimo_octeto (ex: VLAN 17 + octeto 65 = 1765)
  vmid = tonumber("${each.value.vlan}${each.value.ultimo_octeto}")

  vm_state           = each.value.vm_state
  start_at_node_boot = each.value.start_at_node_boot

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "host"
  }

  memory = each.value.memory

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = each.value.vlan
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = each.value.storage
          size    = each.value.size
        }
      }
    }
  }

  # ✅ Lifecycle: prevenir destroy acidental
  lifecycle {
    # Prevenir destroy acidental (descomentar se necessário)
    # prevent_destroy = true

    # Validação extra: garantir que recursos necessários existem
    precondition {
      condition     = contains(keys(var.proxmox_nodes), each.value.target_node)
      error_message = "Node '${each.value.target_node}' não existe em var.proxmox_nodes"
    }

    precondition {
      condition     = can(regex("^[0-9]+G$", each.value.size))
      error_message = "Tamanho do disco deve estar no formato '<número>G' (ex: 32G, 100G)"
    }
  }

  # ✅ Dependências
  depends_on = [
    null_resource.validate_unique_vm_vmids,
    null_resource.validate_vm_octets,
    null_resource.validate_vm_vlans
  ]
}