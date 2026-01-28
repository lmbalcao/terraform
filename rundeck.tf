###############################################################################
# rundeck.tf — Modo 2: sem nodes/inventory, só API + opções
# - Proxmox cria CTs
# - Terraform espera SSH ficar disponível
# - Terraform chama Rundeck job 1x por CT passando target_ip
###############################################################################

locals {
  enabled_cts = {
    for name, ct in local.cts : name => ct
    if try(ct.enabled, true)
  }
}

resource "null_resource" "run_rundeck_job_per_ct" {
  for_each = local.enabled_cts

  triggers = {
    project   = var.rundeck_project
    job_id    = var.rundeck_job_id
    hostname  = each.value.hostname
    target_ip = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -euo pipefail

      IP="192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
      HOSTNAME="${each.value.hostname}"

      echo "Aguardar SSH em $IP:22 ..."
      for i in $(seq 1 60); do
        if timeout 2 bash -lc "</dev/tcp/$IP/22" 2>/dev/null; then
          echo "SSH disponível em $IP"
          break
        fi
        sleep 5
        if [ "$i" -eq 60 ]; then
          echo "Timeout à espera de SSH em $IP"
          exit 1
        fi
      done

      curl -sS -X POST \
        -H "X-Rundeck-Auth-Token: ${var.rundeck_api_token}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        "${var.rundeck_url}/api/44/job/${var.rundeck_job_id}/run?project=${var.rundeck_project}" \
        -d "{\"options\":{\"target_ip\":\"$IP\",\"target_hostname\":\"$HOSTNAME\"}}"
    EOT
  }

  depends_on = [
    proxmox_lxc.cts
  ]
}
