##############################################
# 20-docker_deploy.tf
# Deploy de stacks Docker via Portainer
##############################################

locals {
  portainer_stacks = merge([
    for ct_key, ct_config in local.enabled_cts : {
      for app in lookup(ct_config, "apps", []) :
      "${ct_key}-${app}" => {
        ct_key = ct_key
        app    = app
      }
    }
  ]...)
}

resource "portainer_stack" "apps" {
  for_each = local.portainer_stacks

  name            = each.value.app
  deployment_type = "standalone"
  method          = "repository"
  endpoint_id     = portainer_environment.docker_cts[each.value.ct_key].id

  repository_url            = var.apps_repo_url
  repository_username       = var.forgejo_user
  repository_password       = var.forgejo_token
  repository_reference_name = "refs/heads/${var.apps_repo_branch}"
  file_path_in_repository   = "apps/${each.value.app}/docker-compose.yml"

  git_repository_authentication = var.forgejo_token != "" ? true : false

  stack_webhook   = true
  update_interval = "10m"
  pull_image      = true
  force_update    = var.force_redeploy_timestamp != "" ? true : false

  depends_on = [
    portainer_environment.docker_cts,
    null_resource.restore_restic
  ]
}

output "portainer_stacks" {
  value = {
    for k, v in portainer_stack.apps : k => {
      id          = v.id
      name        = v.name
      endpoint_id = v.endpoint_id
      webhook_url = v.webhook_url
    }
  }
  sensitive = true
}
