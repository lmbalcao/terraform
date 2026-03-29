#!/usr/bin/env bash
set -euo pipefail

workload_kind="${WORKLOAD_KIND:-}"
workload_name="${WORKLOAD_NAME:-}"
workload_vmid="${WORKLOAD_VMID:-}"
path_lines="${WORKLOAD_PATH_LINES:-}"

if [[ -z "$workload_kind" || -z "$workload_name" ]]; then
  echo "WORKLOAD_KIND and WORKLOAD_NAME are required" >&2
  exit 1
fi

if [[ -z "$path_lines" ]]; then
  exit 0
fi

ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

run_ct_path_prepare() {
  local path="$1"
  local uid="$2"
  local gid="$3"
  local target="${PROXMOX_SSH_USER}@${PROXMOX_SSH_HOST}"
  local -a ct_ssh_opts=("${ssh_opts[@]}")

  if [[ -z "${PROXMOX_SSH_HOST:-}" || -z "${PROXMOX_SSH_USER:-}" || -z "$workload_vmid" ]]; then
    echo "CT path preparation requires PROXMOX_SSH_HOST, PROXMOX_SSH_USER, and WORKLOAD_VMID" >&2
    exit 1
  fi

  if [[ -n "${PROXMOX_SSH_KEY_PATH:-}" ]]; then
    ct_ssh_opts+=(-i "$PROXMOX_SSH_KEY_PATH")
  fi

  ssh "${ct_ssh_opts[@]}" -p "${PROXMOX_SSH_PORT:-22}" "$target" /bin/sh -s -- "$workload_vmid" "$path" "$uid" "$gid" <<'EOF'
set -eu
vmid="$1"
path="$2"
uid="$3"
gid="$4"

pct exec "$vmid" -- mkdir -p -- "$path"
pct exec "$vmid" -- chown "${uid}:${gid}" -- "$path"
EOF
}

run_vm_path_prepare() {
  local path="$1"
  local uid="$2"
  local gid="$3"
  local target="${GUEST_SSH_USER}@${GUEST_SSH_HOST}"
  local -a vm_ssh_opts=("${ssh_opts[@]}")

  if [[ -z "${GUEST_SSH_HOST:-}" || -z "${GUEST_SSH_USER:-}" ]]; then
    echo "VM path preparation requires GUEST_SSH_HOST and GUEST_SSH_USER" >&2
    exit 1
  fi

  if [[ -z "${GUEST_SSH_KEY_PATH:-}" ]]; then
    echo "VM path preparation requires GUEST_SSH_KEY_PATH" >&2
    exit 1
  fi

  vm_ssh_opts+=(-i "$GUEST_SSH_KEY_PATH")

  ssh "${vm_ssh_opts[@]}" -p "${GUEST_SSH_PORT:-22}" "$target" /bin/sh -s -- "$path" "$uid" "$gid" <<'EOF'
set -eu
path="$1"
uid="$2"
gid="$3"

mkdir -p -- "$path"
chown "${uid}:${gid}" -- "$path"
EOF
}

while IFS=$'\t' read -r path uid gid; do
  [[ -z "$path" ]] && continue

  case "$workload_kind" in
    ct)
      run_ct_path_prepare "$path" "$uid" "$gid"
      ;;
    vm)
      run_vm_path_prepare "$path" "$uid" "$gid"
      ;;
    *)
      echo "Unsupported WORKLOAD_KIND: $workload_kind" >&2
      exit 1
      ;;
  esac
done <<< "$path_lines"
