#!/usr/bin/env bash
# Instala docker.io + docker-compose-plugin num CT via pct exec no host Proxmox.
# Variáveis de ambiente:
#   WORKLOAD_VMID          — VMID do CT
#   WORKLOAD_TARGET_NODE   — nó Proxmox onde o CT corre (opcional se monocluster)
#   PROXMOX_SSH_HOST       — host SSH do Proxmox
#   PROXMOX_SSH_PORT       — porta SSH (default 22)
#   PROXMOX_SSH_USER       — utilizador SSH (default root)
#   PROXMOX_SSH_KEY_PATH   — chave SSH privada (opcional)
set -euo pipefail

vmid="${WORKLOAD_VMID:-}"
target_node="${WORKLOAD_TARGET_NODE:-}"
proxmox_host="${PROXMOX_SSH_HOST:-}"
proxmox_port="${PROXMOX_SSH_PORT:-22}"
proxmox_user="${PROXMOX_SSH_USER:-root}"
key_path="${PROXMOX_SSH_KEY_PATH:-}"

if [[ -z "$vmid" || -z "$proxmox_host" || -z "$proxmox_user" ]]; then
  echo "[install-docker-ct] WORKLOAD_VMID, PROXMOX_SSH_HOST e PROXMOX_SSH_USER são obrigatórios" >&2
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

echo "[install-docker-ct] A verificar/instalar docker no CT ${vmid}..."

run_in_ct '
set -e
if command -v docker >/dev/null 2>&1; then
  echo "[docker] já instalado: $(docker --version)"
  exit 0
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends docker.io docker-compose-plugin
systemctl enable --now docker
echo "[docker] instalado com sucesso"
'

echo "[install-docker-ct] Docker pronto no CT ${vmid}"
