###############################################################################
# rundeck.tf — Execução de job Rundeck após deploy completo
# - Executa DEPOIS de restore_restic e deploy_apps
# - Chama job 1x por CT passando target_ip e hostname
###############################################################################

locals {
  # Só CTs enabled + com rundeck permitido (default: true se não existir controlo_manual)
  enabled_cts_rundeck = {
    for name, ct in local.cts : name => ct
    if try(ct.enabled, true) && try(ct.controlo_manual.run_rundeck, true)
  }
}



resource "null_resource" "run_rundeck_job_per_ct" {
  for_each = local.enabled_cts_rundeck

  triggers = {
    project   = var.rundeck_project
    job_id    = var.rundeck_job_id
    hostname  = each.value.hostname
    target_ip = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      IP="192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
      HOSTNAME="${each.value.hostname}"

      echo "================================================================="
      echo "RUNDECK JOB - $HOSTNAME ($IP)"
      echo "================================================================="

      # ✅ Executar job Rundeck
      RESPONSE=$(curl -sS -X POST \
        -H "X-Rundeck-Auth-Token: ${var.rundeck_api_token}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        "${var.rundeck_url}/api/44/job/${var.rundeck_job_id}/run?project=${var.rundeck_project}" \
        -d "{\"options\":{\"target_ip\":\"$IP\",\"target_hostname\":\"$HOSTNAME\"}}" \
        2>&1)

      # ✅ Validar resposta mas continuar se falhar
      if echo "$RESPONSE" | grep -q '"id"'; then
        EXECUTION_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)
        echo "[SUCESSO] Job Rundeck executado: ID $EXECUTION_ID"
        echo "================================================================="
        exit 0
      else
        echo "[AVISO] Job Rundeck falhou ou API indisponível"
        echo "Resposta: $RESPONSE"
        echo "[INFO] Continuar sem bloquear pipeline..."
        echo "================================================================="
        exit 0  # ✅ Continuar mesmo com erro
      fi
    EOT

    on_failure = continue # ✅ Garantir que não bloqueia Terraform
  }

  depends_on = [
  null_resource.setup_docker_tls_api]
}