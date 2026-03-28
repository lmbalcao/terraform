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

check "proxmox_credentials_declared" {
  assert {
    condition = alltrue([
      trimspace(var.proxmox_api_url) != "",
      trimspace(var.proxmox_api_token_id) != "",
      trimspace(var.proxmox_api_token) != "",
    ])
    error_message = "proxmox-base requires declared Proxmox credentials. Without valid Proxmox credentials, terraform plan cannot validate provider-backed behavior for this stack."
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
  network_tag     = try(each.value.network.vlan, null)
  network_mode    = each.value.network.mode
  network_ip_cidr = try(each.value.network.address, null)
  network_gateway = try(each.value.network.gateway, null)
}

resource "terraform_data" "ct_manual_features" {
  for_each = local.cts_with_manual_features

  # The active CT contract still reconciles nesting/keyctl/fuse and selected
  # config fields after creation via the Proxmox API or local pct.

  input = {
    ct_name      = each.key
    node         = module.cts[each.key].target_node
    vmid         = module.cts[each.key].vmid
    nesting      = each.value.nesting
    keyctl       = each.value.keyctl
    fuse         = each.value.fuse
    description  = each.value.description
    nameserver   = each.value.nameserver
    searchdomain = each.value.searchdomain
  }

  triggers_replace = [
    tostring(module.cts[each.key].id),
    sha256(jsonencode(each.value)),
  ]

  provisioner "local-exec" {
    command     = <<-EOT
      if ! command -v python3 >/dev/null 2>&1; then
        apk add --no-cache python3 >/dev/null
      fi

      set -- \
        python3 \
        ${path.root}/../../scripts/apply-proxmox-ct-features.py \
        --node "$CT_NODE" \
        --vmid "$CT_VMID"

      if [ "$CT_NESTING" = "1" ]; then
        set -- "$@" --nesting
      fi
      if [ "$CT_KEYCTL" = "1" ]; then
        set -- "$@" --keyctl
      fi
      if [ "$CT_FUSE" = "1" ]; then
        set -- "$@" --fuse
      fi
      if [ -n "$CT_DESCRIPTION" ]; then
        set -- "$@" --description "$CT_DESCRIPTION"
      else
        set -- "$@" --delete-description
      fi
      if [ -n "$CT_NAMESERVER" ]; then
        set -- "$@" --nameserver "$CT_NAMESERVER"
      else
        set -- "$@" --delete-nameserver
      fi
      if [ -n "$CT_SEARCHDOMAIN" ]; then
        set -- "$@" --searchdomain "$CT_SEARCHDOMAIN"
      else
        set -- "$@" --delete-searchdomain
      fi

      exec "$@"
    EOT
    interpreter = ["/bin/sh", "-c"]
    environment = {
      CT_NODE                  = module.cts[each.key].target_node
      CT_VMID                  = tostring(module.cts[each.key].vmid)
      CT_NESTING               = each.value.nesting ? "1" : "0"
      CT_KEYCTL                = each.value.keyctl ? "1" : "0"
      CT_FUSE                  = each.value.fuse ? "1" : "0"
      CT_DESCRIPTION           = each.value.description
      CT_NAMESERVER            = each.value.nameserver
      CT_SEARCHDOMAIN          = each.value.searchdomain
      PROXMOX_API_URL          = var.proxmox_api_url
      PROXMOX_API_TOKEN_ID     = var.proxmox_api_token_id
      PROXMOX_API_TOKEN_SECRET = var.proxmox_api_token
      PROXMOX_TLS_INSECURE     = tostring(var.proxmox_tls_insecure)
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
  kvm_enabled = try(each.value.qemu.kvm_enabled, true)
  scsi_hardware = try(each.value.qemu.scsi_hardware, "lsi")

  start_at_node_boot = each.value.boot.on_boot
  vm_state           = each.value.boot.start_state

  network_bridge  = each.value.network.bridge
  network_tag     = try(each.value.network.vlan, null)
  network_mode    = each.value.network.mode
  network_address = try(each.value.network.address, null)
  network_gateway = try(each.value.network.gateway, null)
  nameserver      = try(length(each.value.network.dns_servers) > 0 ? each.value.network.dns_servers[0] : null, null)
  searchdomain    = try(each.value.network.dns_domain, null)

  rootfs_storage = each.value.storage.rootfs_storage
  rootfs_size_gb = each.value.storage.rootfs_size_gb
  source_clone   = try(each.value.qemu.source.clone, null)
}
