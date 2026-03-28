locals {
  inventory_root_dir = (
    startswith(var.inventory_root, "/")
    ? var.inventory_root
    : abspath("${path.root}/${var.inventory_root}")
  )
  inventory_env_dir = "${local.inventory_root_dir}/${var.environment}"

  defaults_document = yamldecode(file("${local.inventory_env_dir}/defaults.yaml"))
  ingress_document  = yamldecode(file("${local.inventory_env_dir}/ingress.yaml"))

  ct_files = sort(fileset(local.inventory_env_dir, "cts/*.yaml"))
  vm_files = sort(fileset(local.inventory_env_dir, "vms/*.yaml"))

  ct_documents = [for rel in local.ct_files : yamldecode(file("${local.inventory_env_dir}/${rel}"))]
  vm_documents = [for rel in local.vm_files : yamldecode(file("${local.inventory_env_dir}/${rel}"))]

  defaults          = try(local.defaults_document.defaults, {})
  traefik_instances = try(local.ingress_document.traefik_instances, {})

  cts = {
    for doc in local.ct_documents : doc.name => merge(
      try(local.defaults.common, {}),
      try(local.defaults.ct, {}),
      doc,
      {
        services = try(doc.services, try(local.defaults.common.services, []))
      }
    ) if try(doc.enabled, try(local.defaults.ct.enabled, true))
  }

  vms = {
    for doc in local.vm_documents : doc.name => merge(
      try(local.defaults.common, {}),
      try(local.defaults.vm, {}),
      doc,
      {
        services = try(doc.services, try(local.defaults.common.services, []))
      }
    ) if try(doc.enabled, try(local.defaults.vm.enabled, true))
  }

  service_candidates = flatten(concat(
    [
      for workload_name, workload in local.cts : [
        for service in try(workload.services, []) : {
          kind          = "ct"
          workload_name = workload_name
          service_name  = service.name
          port          = try(service.port, null)
          traefik_tag   = try(service.traefik_tag, null)
          traefik_label = try(service.traefik_label, null)
          uri           = try(service.uri, null)
        }
      ]
    ],
    [
      for workload_name, workload in local.vms : [
        for service in try(workload.services, []) : {
          kind          = "vm"
          workload_name = workload_name
          service_name  = service.name
          port          = try(service.port, null)
          traefik_tag   = try(service.traefik_tag, null)
          traefik_label = try(service.traefik_label, null)
          uri           = try(service.uri, null)
        }
      ]
    ]
  ))

  traefik_services = [
    for service in local.service_candidates : service
    if service.traefik_tag != null && service.traefik_label != null && service.uri != null
  ]

  unknown_traefik_instances = [
    for service in local.traefik_services : format("%s/%s", service.workload_name, service.service_name)
    if !contains(keys(local.traefik_instances), service.traefik_tag)
  ]

  uri_to_tags = {
    for uri in distinct([for service in local.traefik_services : service.uri]) : uri => distinct([
      for service in local.traefik_services : service.traefik_tag
      if service.uri == uri
    ])
  }

  conflicting_uris = [
    for uri, tags in local.uri_to_tags : uri
    if length(tags) > 1
  ]

  dns_records = {
    for service in local.traefik_services : service.uri => merge(service, {
      address    = local.traefik_instances[service.traefik_tag].address
      section_id = substr(replace(replace(replace(lower(format("dns-%s-%s", service.traefik_tag, service.uri)), ".", "_"), "-", "_"), ":", "_"), 0, 63)
    })
    if contains(keys(local.traefik_instances), service.traefik_tag)
  }
}
