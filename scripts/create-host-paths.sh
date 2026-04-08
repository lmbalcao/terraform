#!/usr/bin/env bash
set -euo pipefail

host_paths="${HOST_PATHS:-}"
proxmox_ssh_host="${PROXMOX_SSH_HOST:-}"
proxmox_ssh_port="${PROXMOX_SSH_PORT:-22}"
proxmox_ssh_user="${PROXMOX_SSH_USER:-root}"
proxmox_ssh_key_path="${PROXMOX_SSH_KEY_PATH:-}"
host_path_uid="${HOST_PATH_UID:-}"

if [[ -z "$host_paths" ]]; then
  exit 0
fi

if [[ -z "$proxmox_ssh_host" || -z "$proxmox_ssh_user" ]]; then
  echo "PROXMOX_SSH_HOST and PROXMOX_SSH_USER are required" >&2
  exit 1
fi

ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -p "$proxmox_ssh_port"
)

if [[ -n "$proxmox_ssh_key_path" ]]; then
  ssh_opts+=(-i "$proxmox_ssh_key_path")
fi

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  echo "Creating host path: $path"
  ssh "${ssh_opts[@]}" "${proxmox_ssh_user}@${proxmox_ssh_host}" mkdir -p -- "$path"
  if [[ -n "$host_path_uid" ]]; then
    ssh "${ssh_opts[@]}" "${proxmox_ssh_user}@${proxmox_ssh_host}" chown "$host_path_uid" -- "$path"
  fi
done <<< "$host_paths"
