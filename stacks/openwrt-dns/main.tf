check "document_versions" {
  assert {
    condition = try(local.defaults_document.version, 0) == 1 && try(local.ingress_document.version, 0) == 1 && alltrue([
      for doc in concat(local.ct_documents, local.vm_documents) : try(doc.version, 0) == 1
    ])
    error_message = "All inventory documents must declare version 1."
  }
}

check "known_traefik_instances" {
  assert {
    condition     = length(local.unknown_traefik_instances) == 0
    error_message = format("Unknown traefik_tag references found: %s", join(", ", local.unknown_traefik_instances))
  }
}

check "unique_uri_targets" {
  assert {
    condition     = length(local.conflicting_uris) == 0
    error_message = format("Each URI must map to a single Traefik instance: %s", join(", ", local.conflicting_uris))
  }
}

resource "openwrt_dhcp_domain" "records" {
  for_each = local.dns_records

  id   = each.value.section_id
  name = each.key
  ip   = each.value.address
}

resource "terraform_data" "firewall_rules" {
  count = var.openwrt_firewall_enabled && length(local.traefik_services) > 0 ? 1 : 0

  input = {
    dns_records       = local.dns_records
    traefik_instances = local.traefik_instances
    firewall_apply    = var.openwrt_firewall_apply
    firewall_ssh_host = coalesce(var.openwrt_firewall_ssh_host, var.openwrt_hostname)
    firewall_ssh_port = var.openwrt_firewall_ssh_port
    firewall_ssh_user = var.openwrt_firewall_ssh_user
  }

  triggers_replace = [
    sha256(jsonencode(local.dns_records)),
    sha256(jsonencode(local.traefik_instances)),
    coalesce(var.openwrt_firewall_ssh_host, var.openwrt_hostname),
    tostring(var.openwrt_firewall_ssh_port),
    var.openwrt_firewall_ssh_user,
    tostring(var.openwrt_firewall_apply),
  ]

  provisioner "local-exec" {
    command = join(" ", compact([
      "python3",
      "${path.root}/../../scripts/ensure-openwrt-firewall.py",
      "--environment",
      var.environment,
      "--inventory-root",
      var.inventory_root,
      "--openwrt-host",
      coalesce(var.openwrt_firewall_ssh_host, var.openwrt_hostname),
      "--openwrt-user",
      var.openwrt_firewall_ssh_user,
      "--openwrt-port",
      tostring(var.openwrt_firewall_ssh_port),
      var.openwrt_firewall_apply ? "--apply" : "",
    ]))
    interpreter = ["/bin/bash", "-lc"]
  }

  depends_on = [openwrt_dhcp_domain.records]
}
