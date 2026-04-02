data "http" "app_compose" {
  for_each = local.docker_apps_root == null ? toset(local.app_names) : toset([])

  url = local.app_compose_urls[each.key]

  request_headers = {
    Accept = "text/plain, text/yaml, */*"
  }
}

check "app_compose_sources_resolved" {
  assert {
    condition     = length(local.app_missing_local_compose_files) == 0
    error_message = format("Each declared app must resolve to docker-compose.yml: %s", join(", ", local.app_missing_local_compose_files))
  }
}

check "app_compose_mounts_deterministic" {
  assert {
    condition     = length(local.workload_app_analysis_errors) == 0
    error_message = join("\n", concat(["App docker-compose analysis failed:"], local.workload_app_analysis_errors))
  }
}

resource "terraform_data" "ct_declared_host_path" {
  for_each = toset(
    local.proxmox_ssh_host_effective != null ? local.ct_declared_host_paths : []
  )

  triggers_replace = [each.value, tostring(local.proxmox_ssh_host_effective)]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/../../scripts/create-host-paths.sh"

    environment = {
      HOST_PATHS           = each.value
      PROXMOX_SSH_HOST     = local.proxmox_ssh_host_effective
      PROXMOX_SSH_PORT     = tostring(var.proxmox_ssh_port)
      PROXMOX_SSH_USER     = var.proxmox_ssh_user
      PROXMOX_SSH_KEY_PATH = var.proxmox_ssh_private_key_path != null ? var.proxmox_ssh_private_key_path : ""
    }
  }
}

check "ct_app_path_preparation_runner_configured" {
  assert {
    condition     = length(local.ct_workloads_with_app_paths) == 0 || local.proxmox_ssh_host_effective != null
    error_message = "CT workloads with apps require proxmox_ssh_host (or a resolvable proxmox_api_url) so terraform can run pct exec and prepare compose bind-mount paths."
  }
}

check "vm_app_path_preparation_static_address" {
  assert {
    condition     = length(local.vm_workloads_missing_static_address_for_apps) == 0
    error_message = format("VM workloads with apps require static network.address so terraform can prepare compose bind-mount paths: %s", join(", ", local.vm_workloads_missing_static_address_for_apps))
  }
}

check "vm_app_path_preparation_runner_configured" {
  assert {
    condition     = length(local.vm_workloads_with_app_paths) == 0 || trimspace(coalesce(var.guest_ssh_private_key_path, "")) != ""
    error_message = "VM workloads with apps require guest_ssh_private_key_path so terraform can prepare compose bind-mount paths over SSH."
  }
}

resource "terraform_data" "ct_app_paths" {
  for_each = local.ct_workloads_with_app_paths

  input = {
    workload_name = each.key
    workload_kind = "ct"
    target_node   = module.cts[each.key].target_node
    vmid          = module.cts[each.key].vmid
    path_lines    = local.workload_app_path_lines[each.key]
  }

  triggers_replace = [
    tostring(module.cts[each.key].id),
    sha256(local.workload_app_path_lines[each.key]),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/../../scripts/prepare-workload-app-paths.sh"

    environment = {
      WORKLOAD_KIND        = "ct"
      WORKLOAD_NAME        = each.key
      WORKLOAD_VMID        = tostring(module.cts[each.key].vmid)
      WORKLOAD_PATH_LINES  = local.workload_app_path_lines[each.key]
      PROXMOX_SSH_HOST     = local.proxmox_ssh_host_effective != null ? local.proxmox_ssh_host_effective : ""
      PROXMOX_SSH_PORT     = tostring(var.proxmox_ssh_port)
      PROXMOX_SSH_USER     = var.proxmox_ssh_user
      PROXMOX_SSH_KEY_PATH = coalesce(var.proxmox_ssh_private_key_path, "")
      GUEST_SSH_HOST       = ""
      GUEST_SSH_PORT       = tostring(var.guest_ssh_port)
      GUEST_SSH_USER       = var.guest_ssh_user
      GUEST_SSH_KEY_PATH   = coalesce(var.guest_ssh_private_key_path, "")
    }
  }
}

resource "terraform_data" "vm_app_paths" {
  for_each = local.vm_workloads_with_app_paths

  input = {
    workload_name = each.key
    workload_kind = "vm"
    vmid          = module.vms[each.key].vmid
    guest_host    = local.vm_workload_hosts[each.key]
    path_lines    = local.workload_app_path_lines[each.key]
  }

  triggers_replace = [
    tostring(module.vms[each.key].id),
    local.vm_workload_hosts[each.key],
    sha256(local.workload_app_path_lines[each.key]),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/../../scripts/prepare-workload-app-paths.sh"

    environment = {
      WORKLOAD_KIND        = "vm"
      WORKLOAD_NAME        = each.key
      WORKLOAD_VMID        = tostring(module.vms[each.key].vmid)
      WORKLOAD_PATH_LINES  = local.workload_app_path_lines[each.key]
      PROXMOX_SSH_HOST     = local.proxmox_ssh_host_effective != null ? local.proxmox_ssh_host_effective : ""
      PROXMOX_SSH_PORT     = tostring(var.proxmox_ssh_port)
      PROXMOX_SSH_USER     = var.proxmox_ssh_user
      PROXMOX_SSH_KEY_PATH = coalesce(var.proxmox_ssh_private_key_path, "")
      GUEST_SSH_HOST       = local.vm_workload_hosts[each.key]
      GUEST_SSH_PORT       = tostring(var.guest_ssh_port)
      GUEST_SSH_USER       = var.guest_ssh_user
      GUEST_SSH_KEY_PATH   = coalesce(var.guest_ssh_private_key_path, "")
    }
  }
}
