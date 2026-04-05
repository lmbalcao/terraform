locals {
  inventory_root_dir = (
    startswith(var.inventory_root, "/")
    ? var.inventory_root
    : abspath("${path.root}/${var.inventory_root}")
  )
  inventory_env_dir = "${local.inventory_root_dir}/${var.environment}"
  docker_apps_root = var.docker_apps_root == null ? null : (
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

  workloads = merge(
    {
      for name, ct in local.cts : name => merge(ct, {
        workload_kind = "ct"
      })
    },
    {
      for name, vm in local.vms : name => merge(vm, {
        workload_kind = "vm"
      })
    }
  )

  workload_app_pairs = flatten([
    for workload_name, workload in local.workloads : [
      for app in try(workload.apps, []) : {
        workload_name = workload_name
        workload_kind = workload.workload_kind
        app           = app
      }
    ]
  ])

  app_names = distinct([for pair in local.workload_app_pairs : pair.app])

  app_compose_file_paths = {
    for app in local.app_names : app => (
      local.docker_apps_root == null
      ? null
      : "${local.docker_apps_root}/${app}/docker-compose.yml"
    )
  }

  app_compose_urls = {
    for app in local.app_names : app => format("%s/%s/docker-compose.yml", trimsuffix(var.compose_source_base_url, "/"), app)
  }

  app_missing_local_compose_files = [
    for app in local.app_names : app
    if local.docker_apps_root != null && !fileexists(local.app_compose_file_paths[app])
  ]

  app_compose_documents = {
    for app in local.app_names : app => yamldecode(
      local.docker_apps_root != null
      ? file(local.app_compose_file_paths[app])
      : data.http.app_compose[app].response_body
    )
  }

  app_service_environment_maps = {
    for app, compose in local.app_compose_documents : app => {
      for service_name, service in try(compose.services, {}) : service_name => merge(
        can(keys(try(service.environment, {})))
        ? {
          for key, value in try(service.environment, {}) :
          tostring(key) => value == null ? "" : trimspace(tostring(value))
        }
        : {},
        !can(keys(try(service.environment, {})))
        ? {
          for entry in try(service.environment, []) :
          regexall("^([^=]+)=(.*)$", trimspace(tostring(entry)))[0][0] => regexall("^([^=]+)=(.*)$", trimspace(tostring(entry)))[0][1]
          if length(regexall("^([^=]+)=(.*)$", trimspace(tostring(entry)))) > 0
        }
        : {}
      )
    }
  }

  app_service_user_matches = {
    for app, compose in local.app_compose_documents : app => {
      for service_name, service in try(compose.services, {}) :
      service_name => regexall("^([0-9]+)(?::([0-9]+))?$", trimspace(tostring(try(service.user, ""))))
    }
  }

  app_service_puid_matches = {
    for app, services in local.app_service_environment_maps : app => {
      for service_name, env_map in services :
      service_name => regexall("^([0-9]+)$", trimspace(try(env_map["PUID"], "")))
    }
  }

  app_service_pgid_matches = {
    for app, services in local.app_service_environment_maps : app => {
      for service_name, env_map in services :
      service_name => regexall("^([0-9]+)$", trimspace(try(env_map["PGID"], "")))
    }
  }

  app_service_identities = {
    for app, compose in local.app_compose_documents : app => {
      for service_name, service in try(compose.services, {}) : service_name => (
        length(local.app_service_user_matches[app][service_name]) > 0
        ? {
          uid    = tonumber(local.app_service_user_matches[app][service_name][0][0])
          gid    = tonumber(local.app_service_user_matches[app][service_name][0][1] == null ? local.app_service_user_matches[app][service_name][0][0] : local.app_service_user_matches[app][service_name][0][1])
          source = "service.user"
        }
        : (
          length(local.app_service_puid_matches[app][service_name]) > 0 && length(local.app_service_pgid_matches[app][service_name]) > 0
          ? {
            uid    = tonumber(local.app_service_puid_matches[app][service_name][0][0])
            gid    = tonumber(local.app_service_pgid_matches[app][service_name][0][0])
            source = "environment.PUID/PGID"
          }
          : null
        )
      )
    }
  }

  app_service_bind_mount_flags = {
    for app, compose in local.app_compose_documents : app => {
      for service_name, service in try(compose.services, {}) : service_name => anytrue([
        for volume in try(service.volumes, []) : (
          can(keys(volume))
          ? try(volume.type, null) == "bind"
          : (
            length(split(":", tostring(volume))) >= 2 &&
            (
              startswith(trimspace(split(":", tostring(volume))[0]), "/") ||
              startswith(trimspace(split(":", tostring(volume))[0]), "./") ||
              startswith(trimspace(split(":", tostring(volume))[0]), "../")
            )
          )
        )
      ])
    }
  }

  app_service_identity_errors = flatten([
    for app, compose in local.app_compose_documents : flatten([
      for service_name, service in try(compose.services, {}) : (
        local.app_service_bind_mount_flags[app][service_name]
        ? concat(
          trimspace(tostring(try(service.user, ""))) != "" && length(local.app_service_user_matches[app][service_name]) == 0
          ? [format("%s/%s: service.user must be numeric `uid` or `uid:gid` to infer mount ownership safely", app, service_name)]
          : [],
          (
            contains(keys(local.app_service_environment_maps[app][service_name]), "PUID") || contains(keys(local.app_service_environment_maps[app][service_name]), "PGID")
            ) && !(
            length(local.app_service_puid_matches[app][service_name]) > 0 && length(local.app_service_pgid_matches[app][service_name]) > 0
          )
          ? [format("%s/%s: PUID and PGID must both exist and both be numeric to infer mount ownership safely", app, service_name)]
          : [],
          local.app_service_identities[app][service_name] == null
          ? [format("%s/%s: missing deterministic mount owner; declare numeric `user:` or numeric `PUID` + `PGID`", app, service_name)]
          : []
        )
        : []
      )
    ])
  ])

  all_vmids = concat(
    [for ct in values(local.cts) : ct.vmid],
    [for vm in values(local.vms) : vm.vmid]
  )

  ct_unknown_nodes = [for name, ct in local.cts : name if !contains(keys(local.nodes), ct.node)]
  vm_unknown_nodes = [for name, vm in local.vms : name if !contains(keys(local.nodes), vm.node)]

  ct_unknown_segments = [for name, ct in local.cts : name if !contains(keys(local.networks), try(ct.network.segment, ""))]
  vm_unknown_segments = [for name, vm in local.vms : name if !contains(keys(local.networks), try(vm.network.segment, ""))]

  ct_missing_templates = [
    for name, ct in local.cts : name
    if try(ct.lxc.template, null) == null && var.default_lxc_template == null
  ]

  ct_invalid_static_networks = [
    for name, ct in local.cts : name
    if ct.network.mode == "static" && (try(ct.network.address, null) == null || try(ct.network.gateway, null) == null)
  ]

  app_bind_mount_entries = {
    for app, compose in local.app_compose_documents : app => flatten([
      for service_name, service in try(compose.services, {}) : [
        for volume in try(service.volumes, []) : (
          can(keys(volume))
          ? (
            try(volume.type, null) == "bind"
            ? [
              merge(
                {
                  app          = app
                  service_name = service_name
                  raw          = jsonencode(volume)
                  source_path  = trimspace(tostring(try(volume.source, "")))
                  target_path  = trimspace(tostring(try(volume.target, "")))
                  syntax       = "long"
                },
                local.app_service_identities[app][service_name] == null ? {
                  uid             = null
                  gid             = null
                  identity_source = null
                  } : {
                  uid             = local.app_service_identities[app][service_name].uid
                  gid             = local.app_service_identities[app][service_name].gid
                  identity_source = local.app_service_identities[app][service_name].source
                }
              )
            ]
            : []
          )
          : (
            length(split(":", tostring(volume))) >= 2 && (
              startswith(trimspace(split(":", tostring(volume))[0]), "/") ||
              startswith(trimspace(split(":", tostring(volume))[0]), "./") ||
              startswith(trimspace(split(":", tostring(volume))[0]), "../")
            )
            ? [
              merge(
                {
                  app          = app
                  service_name = service_name
                  raw          = tostring(volume)
                  source_path  = trimspace(split(":", tostring(volume))[0])
                  target_path  = trimspace(split(":", tostring(volume))[1])
                  syntax       = "short"
                },
                local.app_service_identities[app][service_name] == null ? {
                  uid             = null
                  gid             = null
                  identity_source = null
                  } : {
                  uid             = local.app_service_identities[app][service_name].uid
                  gid             = local.app_service_identities[app][service_name].gid
                  identity_source = local.app_service_identities[app][service_name].source
                }
              )
            ]
            : []
          )
        )
      ]
    ])
  }

  app_bind_mount_errors = flatten([
    for app, entries in local.app_bind_mount_entries : concat(
      [
        for entry in entries :
        format("%s/%s: relative bind mount source `%s` is ambiguous; use an absolute path", app, entry.service_name, entry.source_path)
        if startswith(entry.source_path, "./") || startswith(entry.source_path, "../")
      ],
      [
        for entry in entries :
        format("%s/%s: bind mount `%s` is missing a source path", app, entry.service_name, entry.raw)
        if entry.source_path == ""
      ],
      [
        for entry in entries :
        format("%s/%s: bind mount `%s` is missing a target path", app, entry.service_name, entry.raw)
        if entry.target_path == ""
      ],
      [
        for path in distinct([for entry in entries : entry.source_path if startswith(entry.source_path, "/")]) :
        format("%s: bind mount path `%s` maps to multiple UID/GID values (%s)", app, path, join(", ", distinct([
          for entry in entries : format("%s:%s", entry.uid, entry.gid)
          if entry.source_path == path && entry.uid != null && entry.gid != null
        ])))
        if length(distinct([
          for entry in entries : format("%s:%s", entry.uid, entry.gid)
          if entry.source_path == path && entry.uid != null && entry.gid != null
        ])) > 1
      ],
      [
        for entry in entries :
        format("%s/%s: bind mount path `%s` has no deterministic UID/GID owner", app, entry.service_name, entry.source_path)
        if startswith(entry.source_path, "/") && (entry.uid == null || entry.gid == null)
      ]
    )
  ])

  ct_declared_mounts = {
    for name, ct in local.cts : name => [
      for mount in try(ct.lxc.mounts, []) : {
        volume    = try(mount.volume, mount.storage, null)
        path      = try(mount.path, mount.mp, try(mount.guest_path, null))
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
    for name, ct in local.cts : name => []
  }

  ct_mountpoints = {
    for name, ct in local.cts : name => concat(local.ct_declared_mounts[name], local.ct_app_mounts[name])
  }

  ct_declared_host_paths = distinct(flatten([
    for name, mounts in local.ct_declared_mounts : [
      for mount in mounts : mount.volume
      if mount.volume != null && startswith(tostring(mount.volume), "/")
    ]
  ]))

  proxmox_ssh_host_effective = (
    var.proxmox_ssh_host != null && trimspace(var.proxmox_ssh_host) != ""
    ? trimspace(var.proxmox_ssh_host)
    : try(regex("https?://([^:/]+)", var.proxmox_api_url)[0], null)
  )

  workload_app_bind_entries = {
    for workload_name, workload in local.workloads : workload_name => flatten([
      for app in try(workload.apps, []) : [
        for entry in try(local.app_bind_mount_entries[app], []) : merge(entry, {
          workload_name = workload_name
          workload_kind = workload.workload_kind
        })
      ]
    ])
  }

  workload_app_path_specs = {
    for workload_name, workload in local.workloads : workload_name => [
      for source_path in distinct([
        for entry in local.workload_app_bind_entries[workload_name] : entry.source_path
        if startswith(entry.source_path, "/")
        ]) : {
        path = source_path
        uid = one(distinct([
          for entry in local.workload_app_bind_entries[workload_name] : entry.uid
          if entry.source_path == source_path && entry.uid != null && entry.gid != null
        ]))
        gid = one(distinct([
          for entry in local.workload_app_bind_entries[workload_name] : entry.gid
          if entry.source_path == source_path && entry.uid != null && entry.gid != null
        ]))
      }
      if length(distinct([
        for entry in local.workload_app_bind_entries[workload_name] : format("%s:%s", entry.uid, entry.gid)
        if entry.source_path == source_path && entry.uid != null && entry.gid != null
      ])) == 1
    ]
  }

  workload_app_analysis_errors = concat(
    local.app_service_identity_errors,
    local.app_bind_mount_errors
  )

  ct_workloads_with_app_paths = {
    for name, ct in local.cts : name => ct
    if length(local.workload_app_path_specs[name]) > 0
  }

  vm_workloads_with_app_paths = {
    for name, vm in local.vms : name => vm
    if length(local.workload_app_path_specs[name]) > 0
  }

  vm_workloads_missing_static_address_for_apps = [
    for name, vm in local.vm_workloads_with_app_paths : name
    if vm.network.mode != "static" || try(vm.network.address, null) == null
  ]

  vm_workload_hosts = {
    for name, vm in local.vm_workloads_with_app_paths : name => split("/", vm.network.address)[0]
    if vm.network.mode == "static" && try(vm.network.address, null) != null
  }

  workload_app_path_lines = {
    for workload_name, specs in local.workload_app_path_specs :
    workload_name => join("\n", [for spec in specs : format("%s\t%s\t%s", spec.path, spec.uid, spec.gid)])
  }

  ct_features = {
    for name, ct in local.cts : name => {
      nesting = try(ct.lxc.features.nesting, false)
      keyctl  = try(ct.lxc.features.keyctl, try(ct.lxc.features_manual.keyctl, false))
      fuse    = try(ct.lxc.features.fuse, try(ct.lxc.features_manual.fuse, false))
      mknod   = try(ct.lxc.features.mknod, false)
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

  vm_traefik_services = {
    for name, vm in local.vms : name => [
      for service in try(vm.services, []) : {
        traefik_tag   = try(service.traefik_tag, null)
        traefik_label = try(service.traefik_label, null)
        uri           = try(service.uri, null)
        port          = try(service.port, null)
      }
      if try(service.traefik_tag, null) != null && try(service.traefik_label, null) != null && try(service.uri, null) != null && try(service.port, null) != null
    ]
  }

  vm_description_tags = {
    for name, services in local.vm_traefik_services : name => distinct([for service in services : service.traefik_tag])
  }

  vm_descriptions = {
    for name, vm in local.vms : name => (
      length(local.vm_traefik_services[name]) == 0
      ? null
      : join("\n\n", concat(
        [try(vm.notes_title, vm.name)],
        [for tag in local.vm_description_tags[name] : format("%s.enable=true", tag)],
        flatten([
          for service in local.vm_traefik_services[name] : [
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
