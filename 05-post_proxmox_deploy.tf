###############################################################################
# 05-post_proxmox_deploy.tf (CORRIGIDO COMPLETO)
# - Aplica features manuais via pct set -features
# - Aplica bind mounts via pct set
###############################################################################

locals {
  cts_features_sed = {
    for name, ct in local.enabled_cts : name => merge(
      {
        vmid        = tonumber("${ct.vlan}${ct.ultimo_octeto}")
        target_node = ct.target_node
      },
      {
        # Features manuais adicionais
        manual_features = join(",", compact([
          try(ct.features_manual.fuse, false) ? "fuse=1" : "",
          try(ct.features_manual.keyctl, false) ? "keyctl=1" : "",
          try(ct.features_manual.create, false) ? "create=1" : "",
          try(ct.features_manual.mount, "") != "" ? "mount=${ct.features_manual.mount}" : "",
        ]))
      },
      {
        # Combina provider + manual
        features_str = join(",", compact([
          try(ct.features.nesting, false) ? "nesting=1" : "nesting=0",
          try(ct.features_manual.fuse, false) ? "fuse=1" : "",
          try(ct.features_manual.keyctl, false) ? "keyctl=1" : "",
          try(ct.features_manual.create, false) ? "create=1" : "",
          try(ct.features_manual.mount, "") != "" ? "mount=${ct.features_manual.mount}" : "",
        ]))
      }
    )
    if try(ct.enabled, true)
  }

  # Apenas CTs que têm features_manual para aplicar
  cts_with_manual_features = {
    for name, data in local.cts_features_sed : name => data
    if data.manual_features != ""
  }

  # CTs que têm bind mounts para aplicar via pct
  enabled_cts_with_pct_mounts = {
    for name, ct in local.enabled_cts : name => {
      vmid        = tonumber("${ct.vlan}${ct.ultimo_octeto}")
      target_node = ct.target_node
      pct_mounts  = try(ct.pct_mounts, [])
    }
    if length(try(ct.pct_mounts, [])) > 0
  }
}

###############################################################################
# Aplica features_manual via pct set -features no node alvo
###############################################################################

resource "null_resource" "apply_manual_features" {
  for_each = local.cts_with_manual_features

  provisioner "local-exec" {
    command = <<-EOT
      ssh root@${var.proxmox_nodes[each.value.target_node]} \
        "pct set ${proxmox_lxc.cts[each.key].vmid} -features '${each.value.features_str}'"
    EOT
  }

  depends_on = [proxmox_lxc.cts]
}

###############################################################################
# Aplica bind mounts com pct set via SSH (root no node alvo)
###############################################################################

resource "null_resource" "apply_pct_mounts" {
  for_each = local.enabled_cts_with_pct_mounts

  provisioner "local-exec" {
    command = <<-EOT
      ssh root@${var.proxmox_nodes[each.value.target_node]} 'set -euo pipefail; \
      ${join(" ; ", [
    for m in each.value.pct_mounts :
    (try(m.read_only, false)
      ? format("pct set %d -%s %q,mp=%q,backup=%d,ro=1", proxmox_lxc.cts[each.key].vmid, m.slot, m.host_path, m.guest_path, m.backup ? 1 : 0)
      : format("pct set %d -%s %q,mp=%q,backup=%d", proxmox_lxc.cts[each.key].vmid, m.slot, m.host_path, m.guest_path, m.backup ? 1 : 0)
    )
])}'
    EOT
  }

  depends_on = [proxmox_lxc.cts]
}
