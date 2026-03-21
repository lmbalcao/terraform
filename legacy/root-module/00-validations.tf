###############################################################################
# 00-validations.tf - Validações para CTs e VMs
###############################################################################

locals {
  # Lista de todos os VMIDs de CTs
  all_ct_vmids = [
    for name, ct in local.enabled_cts : tonumber("${ct.vlan}${ct.ultimo_octeto}")
  ]

  # Detectar VMIDs duplicados em CTs
  duplicate_ct_vmids = distinct([
    for vmid in local.all_ct_vmids : vmid
    if length([for v in local.all_ct_vmids : v if v == vmid]) > 1
  ])

  # Validar range de ultimo_octeto (2-254) para CTs
  invalid_ct_octets = {
    for name, ct in local.enabled_cts : name => ct.ultimo_octeto
    if ct.ultimo_octeto < 2 || ct.ultimo_octeto > 254
  }

  # Validar VLAN range (1-4094) para CTs
  invalid_ct_vlans = {
    for name, ct in local.enabled_cts : name => ct.vlan
    if ct.vlan < 1 || ct.vlan > 4094
  }
}

# Validação: VMIDs únicos para CTs
resource "null_resource" "validate_unique_vmids" {
  lifecycle {
    precondition {
      condition     = length(local.duplicate_ct_vmids) == 0
      error_message = <<-EOT
        ERRO: VMIDs duplicados encontrados nos CTs: ${join(", ", local.duplicate_ct_vmids)}
        
        Cada combinação VLAN+ultimo_octeto deve ser única.
        Verifica o ficheiro 00-inventory.tf para conflitos.
      EOT
    }
  }
}

# Validação: Octetos válidos para CTs
resource "null_resource" "validate_octets" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_ct_octets) == 0
      error_message = <<-EOT
        ERRO: ultimo_octeto inválido nos CTs (deve estar entre 2 e 254):
        ${jsonencode(local.invalid_ct_octets)}
      EOT
    }
  }
}

# Validação: VLANs válidas para CTs
resource "null_resource" "validate_vlans" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_ct_vlans) == 0
      error_message = <<-EOT
        ERRO: VLAN inválida nos CTs (deve estar entre 1 e 4094):
        ${jsonencode(local.invalid_ct_vlans)}
      EOT
    }
  }
}