##############################################
# 30-portainer_endpoints.tf
# Adiciona endpoints Docker automaticamente ao Portainer
##############################################

# Lê certificados copiados para o filesystem local
# (em vez de file(), que falha no plan quando os ficheiros são criados no apply)

data "local_file" "docker_ca" {
  for_each   = local.enabled_cts
  filename   = "${path.module}/output/docker-certs/${each.key}-ca.pem"
  depends_on = [null_resource.fetch_docker_certs]
}

data "local_file" "docker_cert" {
  for_each   = local.enabled_cts
  filename   = "${path.module}/output/docker-certs/${each.key}-cert.pem"
  depends_on = [null_resource.fetch_docker_certs]
}

data "local_file" "docker_key" {
  for_each   = local.enabled_cts
  filename   = "${path.module}/output/docker-certs/${each.key}-key.pem"
  depends_on = [null_resource.fetch_docker_certs]
}

resource "portainer_environment" "docker_cts" {
  for_each = local.enabled_cts

  name                = replace(each.key, "_", "-")
  environment_address = "tcp://${split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]}:2376"
  public_ip           = split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]
  type                = 1
  group_id            = 1

  tls_enabled            = true
  tls_skip_verify        = false
  tls_skip_client_verify = false

  tls_ca_cert = data.local_file.docker_ca[each.key].content
  tls_cert    = data.local_file.docker_cert[each.key].content
  tls_key     = data.local_file.docker_key[each.key].content

  depends_on = [null_resource.fetch_docker_certs]
}

output "portainer_endpoints" {
  description = "IDs dos endpoints Docker criados no Portainer"
  value = {
    for k, v in portainer_environment.docker_cts : k => {
      id   = v.id
      name = v.name
      url  = v.environment_address
    }
  }
}
