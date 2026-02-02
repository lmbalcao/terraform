###############################################################################
# Outputs estruturados (visíveis no terminal)
###############################################################################

output "created_cts" {
  description = "CTs criados pelo Terraform"
  value = {
    for name, ct in local.enabled_cts : name => {
      hostname         = ct.hostname
      ip               = "192.168.${ct.vlan}.${ct.ultimo_octeto}"
      vlan             = ct.vlan
      vmid             = proxmox_lxc.cts[name].vmid
      node             = proxmox_lxc.cts[name].target_node
      apps_deployed    = try(length(ct.apps) > 0, false)
      backup_restored  = try(null_resource.restore_restic[name].id != null, false)
      docker_installed = try(null_resource.setup_docker[name].id != null, false)
    }
  }
}

output "rundeck_jobs_triggered" {
  description = "Jobs Rundeck disparados pelo Terraform"
  value = {
    for name, ct in local.enabled_cts : name => {
      job_id    = var.rundeck_job_id
      project   = var.rundeck_project
      target_ip = "192.168.${ct.vlan}.${ct.ultimo_octeto}"
      triggered = try(null_resource.run_rundeck_job_per_ct[name].id != null, false)
    }
  }
}