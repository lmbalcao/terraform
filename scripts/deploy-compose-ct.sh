#!/usr/bin/env bash
# Escreve docker-compose.yml em /opt/<APP>/ num CT via pct exec no host Proxmox.
# Variáveis de ambiente:
#   WORKLOAD_VMID          — VMID do CT
#   WORKLOAD_TARGET_NODE   — nó Proxmox onde o CT corre (opcional se monocluster)
#   PROXMOX_SSH_HOST       — host SSH do Proxmox
#   PROXMOX_SSH_PORT       — porta SSH (default 22)
#   PROXMOX_SSH_USER       — utilizador SSH (default root)
#   PROXMOX_SSH_KEY_PATH   — chave SSH privada (opcional)
#   APP_NAME               — nome da app (diretório destino: /opt/<APP_NAME>/)
#   APP_COMPOSE_B64        — conteúdo do docker-compose.yml codificado em base64
set -euo pipefail

vmid="${WORKLOAD_VMID:-}"
target_node="${WORKLOAD_TARGET_NODE:-}"
proxmox_host="${PROXMOX_SSH_HOST:-}"
proxmox_port="${PROXMOX_SSH_PORT:-22}"
proxmox_user="${PROXMOX_SSH_USER:-root}"
key_path="${PROXMOX_SSH_KEY_PATH:-}"
app_name="${APP_NAME:-}"
compose_b64="${APP_COMPOSE_B64:-}"

if [[ -z "$vmid" || -z "$proxmox_host" || -z "$app_name" || -z "$compose_b64" ]]; then
  echo "[deploy-compose-ct] WORKLOAD_VMID, PROXMOX_SSH_HOST, APP_NAME e APP_COMPOSE_B64 são obrigatórios" >&2
  exit 1
fi

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "$proxmox_port")
[[ -n "$key_path" ]] && ssh_opts+=(-i "$key_path")

run_in_ct() {
  local script="$1"
  if [[ -n "$target_node" ]]; then
    ssh "${ssh_opts[@]}" "${proxmox_user}@${proxmox_host}" \
      "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${target_node} pct exec ${vmid} -- bash -c $(printf '%q' "$script")"
  else
    ssh "${ssh_opts[@]}" "${proxmox_user}@${proxmox_host}" \
      "pct exec ${vmid} -- bash -c $(printf '%q' "$script")"
  fi
}

dest_dir="/opt/${app_name}"
dest_file="${dest_dir}/docker-compose.yml"

echo "[deploy-compose-ct] A escrever ${dest_file} no CT ${vmid}..."

# base64 só contém [A-Za-z0-9+/=] — seguro embutir em aspas simples dentro do script remoto
run_in_ct "mkdir -p '${dest_dir}' && printf '%s' '${compose_b64}' | base64 -d > '${dest_file}'"

echo "[deploy-compose-ct] ${dest_file} escrito com sucesso no CT ${vmid}"
