###############################################################################
# restore_restic.tf - Restore condicional do /opt via Restic
# Executa DEPOIS da criação do CT e ANTES do deploy das apps
###############################################################################

locals {
  # Só CTs enabled + com restore permitido (default: true se não existir controlo_manual)
  enabled_cts_restore_restic = {
    for name, ct in local.enabled_cts : name => ct
    if try(ct.controlo_manual.run_restic_restore, true)
  }
}


resource "null_resource" "restore_restic" {
  for_each = local.enabled_cts_restore_restic

  triggers = {
    vmid        = tonumber("${each.value.vlan}${each.value.ultimo_octeto}")
    target_node = each.value.target_node
    hostname    = each.value.hostname
  }

  depends_on = [
    proxmox_lxc.cts,
  ]

  connection {
    type        = "ssh"
    host        = var.proxmox_nodes[each.value.target_node]
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "VMID='${each.value.vlan}${each.value.ultimo_octeto}'",
      "HOSTNAME='${each.value.hostname}'",
      "echo '================================================================='",
      "echo \"RESTORE RESTIC - VMID $VMID ($HOSTNAME)\"",
      "echo '================================================================='",
      "# Verificar se Restic está instalado",
      "if ! command -v restic >/dev/null 2>&1; then",
      "  echo '[AVISO] Restic não instalado no node, skip restore'",
      "  exit 0",
      "fi",
      "export RESTIC_PASSWORD='${var.restic_password}'",
      "export RESTIC_REPOSITORY='${var.restic_repository}'",
      "# Verificar se existe backup para este VMID",
      "echo \"[INFO] A verificar se existe backup para VMID $VMID...\"",
      "if ! restic snapshots --tag \"vmid=$VMID\" --last 1 >/dev/null 2>&1; then",
      "  echo \"[INFO] Sem backup para VMID $VMID, continuar sem restore\"",
      "  exit 0",
      "fi",
      "SNAPSHOT_ID=$(restic snapshots --tag \"vmid=$VMID\" --last 1 --json | jq -r '.[0].id')",
      "SNAPSHOT_TIME=$(restic snapshots --tag \"vmid=$VMID\" --last 1 --json | jq -r '.[0].time')",
      "echo \"[INFO] Backup encontrado: $SNAPSHOT_ID (criado em $SNAPSHOT_TIME)\"",
      "echo '[INFO] A iniciar processo de restore...'",
      "# Parar Docker no container",
      "echo \"[INFO] A parar Docker no VMID $VMID...\"",
      "pct exec \"$VMID\" -- systemctl stop docker 2>/dev/null || true",
      "# Desmontar preventivamente",
      "pct unmount \"$VMID\" 2>/dev/null || true",
      "# Montar filesystem do container",
      "echo \"[INFO] A montar filesystem do VMID $VMID...\"",
      "MOUNTPOINT=$(pct mount \"$VMID\" | awk '{print $NF}' | tr -d \"'\\\"\")",
      "if [[ -z \"$MOUNTPOINT\" ]]; then",
      "  echo '[ERRO] Falha ao montar VMID'",
      "  exit 0",
      "fi",
      "echo \"[INFO] Montado em: $MOUNTPOINT\"",
      "# Limpar /opt atual (sobrescrever)",
      "echo '[INFO] A limpar /opt atual...'",
      "rm -rf \"$MOUNTPOINT/opt\"",
      "mkdir -p \"$MOUNTPOINT/opt\"",
      "# Fazer restore",
      "echo \"[INFO] A restaurar snapshot $SNAPSHOT_ID...\"",
      "if restic restore \"$SNAPSHOT_ID\" --target \"$MOUNTPOINT\" --include \"/opt\" --no-owner 2>&1; then",
      "  echo '[SUCESSO] Restore concluído com sucesso!'",
      "else",
      "  echo '[AVISO] Restore falhou, continuar sem dados antigos'",
      "fi",
      "# Corrigir ownership para LXC unprivileged",
      "echo '[INFO] A corrigir permissões para LXC unprivileged...'",
      "chown -R 100000:100000 \"$MOUNTPOINT/opt\"",
      "chmod -R 755 \"$MOUNTPOINT/opt\"",
      "# Desmontar",
      "echo '[INFO] A desmontar filesystem...'",
      "pct unmount \"$VMID\" 2>/dev/null || true",
      "# Reiniciar Docker",
      "echo \"[INFO] A reiniciar Docker no VMID $VMID...\"",
      "pct exec \"$VMID\" -- systemctl start docker 2>/dev/null || true",
      "echo \"[INFO] Processo de restore concluído para VMID $VMID\"",
      "echo '================================================================='",
    ]
  }
}