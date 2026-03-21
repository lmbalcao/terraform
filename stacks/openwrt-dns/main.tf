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
