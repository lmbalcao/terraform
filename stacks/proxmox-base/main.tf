check "document_versions" {
  assert {
    condition = try(local.defaults_document.version, 0) == 1 && try(local.nodes_document.version, 0) == 1 && try(local.networks_document.version, 0) == 1 && alltrue([
      for doc in concat(local.ct_documents, local.vm_documents) : try(doc.version, 0) == 1
    ])
    error_message = "All inventory documents must declare version 1."
  }
}

check "unique_names" {
  assert {
    condition     = length(local.ct_documents) == length(keys(local.raw_cts)) && length(local.vm_documents) == length(keys(local.raw_vms))
    error_message = "Duplicate workload names detected in inventory."
  }
}

check "unique_vmids" {
  assert {
    condition     = length(local.all_vmids) == length(distinct(local.all_vmids))
    error_message = "Duplicate VMIDs detected across CTs and VMs."
  }
}

check "known_nodes" {
  assert {
    condition     = length(local.ct_unknown_nodes) == 0 && length(local.vm_unknown_nodes) == 0
    error_message = "Unknown node references found in inventory."
  }
}

check "known_segments" {
  assert {
    condition     = length(local.ct_unknown_segments) == 0 && length(local.vm_unknown_segments) == 0
    error_message = "Unknown network segment references found in inventory."
  }
}

check "ct_templates_resolved" {
  assert {
    condition     = length(local.ct_missing_templates) == 0
    error_message = "Every enabled CT must resolve an LXC template from inventory or fallback variable."
  }
}

check "static_networks_complete" {
  assert {
    condition     = length(local.ct_invalid_static_networks) == 0 && length(local.vm_invalid_static_networks) == 0
    error_message = "Static workloads must define address and gateway."
  }
}

module "cts" {
  for_each = local.cts
  source   = "../../modules/proxmox-ct"

  target_node   = each.value.node
  hostname      = try(each.value.hostname, each.value.name)
  vmid          = each.value.vmid
  tags          = try(each.value.tags, [])
  description   = try(local.ct_descriptions[each.key], null)
  ostemplate    = try(each.value.lxc.template, var.default_lxc_template)
  root_password = var.root_password
  unprivileged  = try(each.value.lxc.unprivileged, true)

  cores     = each.value.resources.cpu_cores
  memory_mb = each.value.resources.memory_mb
  swap_mb   = try(each.value.resources.swap_mb, 0)

  on_boot = each.value.boot.on_boot
  start   = each.value.boot.start

  ssh_public_keys = var.ssh_public_keys
  nameserver      = try(length(each.value.network.dns_servers) > 0 ? each.value.network.dns_servers[0] : null, null)
  searchdomain    = try(each.value.network.dns_domain, null)

  rootfs_storage = each.value.storage.rootfs_storage
  rootfs_size_gb = each.value.storage.rootfs_size_gb

  network_bridge  = each.value.network.bridge
  network_tag     = each.value.network.vlan
  network_mode    = each.value.network.mode
  network_ip_cidr = try(each.value.network.address, null)
  network_gateway = try(each.value.network.gateway, null)
  features        = try(each.value.lxc.features, {})
}

resource "terraform_data" "ct_manual_features" {
  for_each = local.cts_with_manual_features

  input = {
    ct_name      = each.key
    node         = module.cts[each.key].target_node
    vmid         = module.cts[each.key].vmid
    nesting      = each.value.nesting
    keyctl       = each.value.keyctl
    fuse         = each.value.fuse
    mount        = each.value.mount
    description  = each.value.description
    nameserver   = each.value.nameserver
    searchdomain = each.value.searchdomain
  }

  triggers_replace = [
    tostring(module.cts[each.key].id),
    sha256(jsonencode(each.value)),
  ]

  provisioner "local-exec" {
    command = join(" ", compact([
      "python3",
      "${path.root}/../../scripts/apply-proxmox-ct-features.py",
      "--node",
      module.cts[each.key].target_node,
      "--vmid",
      tostring(module.cts[each.key].vmid),
      each.value.nesting ? "--nesting" : "",
      each.value.keyctl ? "--keyctl" : "",
      each.value.fuse ? "--fuse" : "",
      each.value.mount != "" ? format("--mount %s", jsonencode(each.value.mount)) : "",
      each.value.description != "" ? format("--description %s", jsonencode(each.value.description)) : "--delete-description",
      each.value.nameserver != "" ? format("--nameserver %s", jsonencode(each.value.nameserver)) : "--delete-nameserver",
      each.value.searchdomain != "" ? format("--searchdomain %s", jsonencode(each.value.searchdomain)) : "--delete-searchdomain",
    ]))
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      PROXMOX_API_URL          = var.proxmox_api_url
      PROXMOX_API_TOKEN_ID     = var.proxmox_api_token_id
      PROXMOX_API_TOKEN_SECRET = var.proxmox_api_token
      PROXMOX_TLS_INSECURE     = "true"
    }
  }
}

module "vms" {
  for_each = local.vms
  source   = "../../modules/proxmox-vm"

  target_node = each.value.node
  name        = each.value.name
  vmid        = each.value.vmid
  tags        = try(each.value.tags, [])

  cpu_cores   = each.value.resources.cpu_cores
  cpu_sockets = try(each.value.resources.cpu_sockets, try(each.value.qemu.sockets, 1))
  memory_mb   = each.value.resources.memory_mb

  start_at_node_boot = each.value.boot.on_boot
  vm_state           = each.value.boot.start_state

  network_bridge  = each.value.network.bridge
  network_tag     = each.value.network.vlan
  network_address = try(each.value.network.address, null)

  rootfs_storage = each.value.storage.rootfs_storage
  rootfs_size_gb = each.value.storage.rootfs_size_gb
  source_clone   = try(each.value.qemu.source.clone, null)
}
