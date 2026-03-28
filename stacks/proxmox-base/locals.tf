locals {
  inventory_root_dir = (
    startswith(var.inventory_root, "/")
    ? var.inventory_root
    : abspath("${path.root}/${var.inventory_root}")
  )
  inventory_env_dir = "${local.inventory_root_dir}/${var.environment}"
  docker_apps_root  = var.docker_apps_root == null ? null : (
    startswith(var.docker_apps_root, "/")
    ? var.docker_apps_root
    : abspath("${path.root}/${var.docker_apps_root}")
  )

  defaults_document = yamldecode(file("${local.inventory_env_dir}/defaults.yaml"))
  nodes_document    = yamldecode(file("${local.inventory_env_dir}/nodes.yaml"))
  networks_document = yamldecode(file("${local.inventory_env_dir}/networks.yaml"))

  ct_files = sort(fileset(local.inventory_env_dir, "cts/*.yaml"))
  vm_files = sort(fileset(local.inventory_env_dir, "vms/*.yaml"))

  ct_documents = [for rel in local.ct_files : yamldecode(file("${local.inventory_env_dir}/${rel}"))]
  vm_documents = [for rel in local.vm_files : yamldecode(file("${local.inventory_env_dir}/${rel}"))]

  defaults = try(local.defaults_document.defaults, {})
  nodes    = try(local.nodes_document.nodes, {})
  networks = try(local.networks_document.networks, {})

  raw_cts = { for doc in local.ct_documents : doc.name => doc }
  raw_vms = { for doc in local.vm_documents : doc.name => doc }

  cts = {
    for name, ct in local.raw_cts : name => merge(
      try(local.defaults.common, {}),
      try(local.defaults.ct, {}),
      ct,
      {
        tags     = try(ct.tags, try(local.defaults.common.tags, []))
        apps     = try(ct.apps, try(local.defaults.common.apps, []))
        services = try(ct.services, try(local.defaults.common.services, []))
        operations = merge(
          try(local.defaults.common.operations, {}),
          try(ct.operations, {})
        )
        boot = merge(
          try(local.defaults.ct.boot, {}),
          try(ct.boot, {})
        )
        resources = merge(
          try(local.defaults.ct.resources, {}),
          try(ct.resources, {})
        )
        storage = merge(
          try(local.defaults.ct.storage, {}),
          try(ct.storage, {})
        )
        lxc = merge(
          try(local.defaults.ct.lxc, {}),
          try(ct.lxc, {})
        )
        network = merge(
          try(local.networks[ct.network.segment], {}),
          try(local.defaults.ct.network, {}),
          try(ct.network, {}),
          {
            bridge     = try(ct.network.bridge, try(local.networks[ct.network.segment].bridge, var.network_bridge))
            dns_domain = try(ct.network.dns_domain, try(local.networks[ct.network.segment].dns_domain, var.default_search_domain))
            dns_servers = try(
              ct.network.dns_servers,
              try(local.networks[ct.network.segment].dns_servers, [])
            )
          }
        )
      }
    ) if try(ct.enabled, try(local.defaults.ct.enabled, true))
  }

  vms = {
    for name, vm in local.raw_vms : name => merge(
      try(local.defaults.common, {}),
      try(local.defaults.vm, {}),
      vm,
      {
        tags     = try(vm.tags, try(local.defaults.common.tags, []))
        apps     = try(vm.apps, try(local.defaults.common.apps, []))
        services = try(vm.services, try(local.defaults.common.services, []))
        operations = merge(
          try(local.defaults.common.operations, {}),
          try(vm.operations, {})
        )
        boot = merge(
          try(local.defaults.vm.boot, {}),
          try(vm.boot, {})
        )
        resources = merge(
          try(local.defaults.vm.resources, {}),
          try(vm.resources, {})
        )
        storage = merge(
          try(local.defaults.vm.storage, {}),
          try(vm.storage, {})
        )
        qemu = merge(
          try(local.defaults.vm.qemu, {}),
          try(vm.qemu, {})
        )
        network = merge(
          try(local.networks[vm.network.segment], {}),
          try(local.defaults.vm.network, {}),
          try(vm.network, {}),
          {
            bridge     = try(vm.network.bridge, try(local.networks[vm.network.segment].bridge, var.network_bridge))
            dns_domain = try(vm.network.dns_domain, try(local.networks[vm.network.segment].dns_domain, var.default_search_domain))
            dns_servers = try(
              vm.network.dns_servers,
              try(local.networks[vm.network.segment].dns_servers, [])
            )
          }
        )
      }
    ) if try(vm.enabled, try(local.defaults.vm.enabled, true))
  }

  all_vmids = concat(
    [for ct in values(local.cts) : ct.vmid],
    [for vm in values(local.vms) : vm.vmid]
  )

  ct_unknown_nodes = [for name, ct in local.cts : name if !contains(keys(local.nodes), ct.node)]
  vm_unknown_nodes = [for name, vm in local.vms : name if !contains(keys(local.nodes), vm.node)]

  ct_unknown_segments = [for name, ct in local.cts : name if !contains(keys(local.networks), ct.network.segment)]
  vm_unknown_segments = [for name, vm in local.vms : name if !contains(keys(local.networks), vm.network.segment)]

  ct_missing_templates = [
    for name, ct in local.cts : name
    if try(ct.lxc.template, null) == null && var.default_lxc_template == null
  ]

  ct_invalid_static_networks = [
    for name, ct in local.cts : name
    if ct.network.mode == "static" && (try(ct.network.address, null) == null || try(ct.network.gateway, null) == null)
  ]

  ct_missing_app_compose_files = distinct(flatten([
    for name, ct in local.cts : [
      for app in try(ct.apps, []) : format("%s:%s", name, app)
      if local.docker_apps_root == null || !fileexists("${local.docker_apps_root}/${app}/docker-compose.yml")
    ]
  ]))

  ct_app_compose_documents = {
    for name, ct in local.cts : name => {
      for app in try(ct.apps, []) : app => yamldecode(file("${local.docker_apps_root}/${app}/docker-compose.yml"))
      if local.docker_apps_root != null && fileexists("${local.docker_apps_root}/${app}/docker-compose.yml")
    }
  }

  ct_app_mount_candidates = {
    for name, ct in local.cts : name => distinct(flatten([
      for app, compose in try(local.ct_app_compose_documents[name], {}) : flatten([
        for service in values(try(compose.services, {})) : [
          for volume in try(service.volumes, []) : (
            can(keys(volume))
            ? (
              try(volume.type, null) == "bind" && try(startswith(tostring(volume.source), "/"), false)
              ? tostring(volume.source)
              : null
            )
            : (
              try(startswith(trimspace(split(":", tostring(volume))[0]), "/"), false)
              ? trimspace(split(":", tostring(volume))[0])
              : null
            )
          )
        ]
      ])
    ]))
  }

  ct_declared_mounts = {
    for name, ct in local.cts : name => [
      for mount in try(ct.lxc.mounts, []) : {
        key       = try(mount.key, format("mp%d", tonumber(mount.slot)))
        slot      = tonumber(mount.slot)
        mp        = try(mount.mp, try(mount.guest_path, null))
        storage   = try(mount.storage, ct.storage.rootfs_storage)
        size      = try(mount.size, try(mount.size_gb, null) == null ? null : format("%sG", mount.size_gb))
        backup    = try(mount.backup, false)
        quota     = try(mount.quota, false)
        replicate = try(mount.replicate, false)
        shared    = try(mount.shared, false)
        acl       = try(mount.acl, false)
      }
    ]
  }

  ct_app_mounts = {
    for name, ct in local.cts : name => [
      for index, mp in local.ct_app_mount_candidates[name] : {
        key       = format("mp%d", index)
        slot      = index
        mp        = mp
        storage   = ct.storage.rootfs_storage
        size      = format("%sG", ct.storage.rootfs_size_gb)
        backup    = false
        quota     = false
        replicate = false
        shared    = false
        acl       = false
      }
      if mp != null && !contains([for declared in local.ct_declared_mounts[name] : declared.mp], mp)
    ]
  }

  ct_mountpoints = {
    for name, ct in local.cts : name => concat(local.ct_declared_mounts[name], local.ct_app_mounts[name])
  }

  ct_features = {
    for name, ct in local.cts : name => {
      nesting = try(ct.lxc.features.nesting, null)
      keyctl  = try(ct.lxc.features.keyctl, try(ct.lxc.features_manual.keyctl, null))
      fuse    = try(ct.lxc.features.fuse, try(ct.lxc.features_manual.fuse, null))
      mknod   = try(ct.lxc.features.mknod, null)
      mount   = try(ct.lxc.features.mount, null)
    }
  }

  vm_invalid_static_networks = [
    for name, vm in local.vms : name
    if vm.network.mode == "static" && (try(vm.network.address, null) == null || try(vm.network.gateway, null) == null)
  ]

  ct_traefik_services = {
    for name, ct in local.cts : name => [
      for service in try(ct.services, []) : {
        traefik_tag   = try(service.traefik_tag, null)
        traefik_label = try(service.traefik_label, null)
        uri           = try(service.uri, null)
        port          = try(service.port, null)
      }
      if try(service.traefik_tag, null) != null && try(service.traefik_label, null) != null && try(service.uri, null) != null && try(service.port, null) != null
    ]
  }

  ct_description_tags = {
    for name, services in local.ct_traefik_services : name => distinct([for service in services : service.traefik_tag])
  }

  ct_descriptions = {
    for name, ct in local.cts : name => (
      length(local.ct_traefik_services[name]) == 0
      ? null
      : join("\n\n", concat(
        [try(ct.notes_title, ct.hostname, ct.name)],
        [for tag in local.ct_description_tags[name] : format("%s.enable=true", tag)],
        flatten([
          for service in local.ct_traefik_services[name] : [
            format("%s.http.routers.%s.rule=Host(`%s`)", service.traefik_tag, service.traefik_label, service.uri),
            format("%s.http.routers.%s.entrypoints=websecure", service.traefik_tag, service.traefik_label),
            format("%s.http.routers.%s.middlewares=compression@file", service.traefik_tag, service.traefik_label),
            format("%s.http.routers.%s.tls=true", service.traefik_tag, service.traefik_label),
            format("%s.http.routers.%s.tls.certresolver=le", service.traefik_tag, service.traefik_label),
            format("%s.http.services.%s.loadbalancer.server.port=%s", service.traefik_tag, service.traefik_label, service.port),
          ]
        ])
      ))
    )
  }
}
