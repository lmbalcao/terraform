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
  count = var.openwrt_firewall_enabled ? 1 : 0

  input = {
    dns_records       = local.dns_records
    traefik_instances = local.traefik_instances
    firewall_apply    = var.openwrt_firewall_apply
  }

  triggers_replace = [
    sha256(jsonencode(local.dns_records)),
    sha256(jsonencode(local.traefik_instances)),
    tostring(var.openwrt_firewall_apply),
    plantimestamp(),
  ]

  provisioner "local-exec" {
    command = join(" ", compact([
      "python3",
      "${path.root}/../../scripts/ensure-openwrt-firewall.py",
      "--environment",
      var.environment,
      "--inventory-root",
      abspath("${path.root}/${var.inventory_root}"),
      var.openwrt_firewall_apply ? "--apply" : "",
    ]))
    interpreter = ["/bin/bash", "-lc"]

    environment = {
      OPENWRT_HOSTNAME         = coalesce(var.openwrt_firewall_ssh_host, var.openwrt_hostname)
      OPENWRT_PORT             = tostring(var.openwrt_firewall_ssh_port)
      OPENWRT_SCHEME           = var.openwrt_scheme
      OPENWRT_USERNAME         = var.openwrt_firewall_ssh_user
      OPENWRT_PASSWORD         = var.openwrt_password
      OPENWRT_TLS_INSECURE     = "true"
      PROXMOX_API_URL          = coalesce(var.proxmox_api_url, "")
      PROXMOX_API_TOKEN_ID     = coalesce(var.proxmox_api_token_id, "")
      PROXMOX_API_TOKEN_SECRET = coalesce(var.proxmox_api_token, "")
      PROXMOX_TLS_INSECURE     = tostring(var.proxmox_tls_insecure)
    }
  }

  depends_on = [openwrt_dhcp_domain.records]
}
