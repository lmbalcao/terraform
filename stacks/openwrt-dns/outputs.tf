output "planned_dns_records" {
  description = "DNS records derived from Traefik-exposed services."
  value = {
    for uri, record in local.dns_records : uri => {
      address       = record.address
      traefik_tag   = record.traefik_tag
      traefik_label = record.traefik_label
      workload_name = record.workload_name
      service_name  = record.service_name
    }
  }
}
