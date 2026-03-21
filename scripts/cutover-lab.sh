#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTE=false

resolve_terraform() {
  if [[ -n "${TERRAFORM_BIN:-}" && -x "${TERRAFORM_BIN}" ]]; then
    printf "%s\n" "${TERRAFORM_BIN}"
    return 0
  fi

  if command -v terraform >/dev/null 2>&1; then
    command -v terraform
    return 0
  fi

  local candidates=(
    "$ROOT_DIR/.tools/bin/terraform"
    "$ROOT_DIR/.tools/terraform-1.5.7/terraform"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  return 1
}

usage() {
  cat <<EOF
Usage: scripts/cutover-lab.sh [--execute]

Without --execute, prints the exact cutover sequence for lab.
With --execute, runs validation and the offline state move steps using /tmp state files.

Required local files before --execute:
  env/lab/common.tfvars
  env/lab/proxmox-base.tfvars
EOF
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --execute)
    EXECUTE=true
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

STACK_DIR="$ROOT_DIR/stacks/proxmox-base"
COMMON_VARS="$ROOT_DIR/env/lab/common.tfvars"
STACK_VARS="$ROOT_DIR/env/lab/proxmox-base.tfvars"
LEGACY_STATE="/tmp/legacy-lab.tfstate"
NEW_STATE="/tmp/proxmox-base-lab.tfstate"

LEGACY_CT="proxmox_lxc.cts[\"homarr\"]"
NEW_CT="module.cts[\"homarr\"].proxmox_lxc.this"
LEGACY_VM="proxmox_vm_qemu.vms[\"vm_template\"]"
NEW_VM="module.vms[\"vm-template\"].proxmox_vm_qemu.this"

show_commands() {
  cat <<EOF
cd $ROOT_DIR
export PATH="$ROOT_DIR/.tools/bin:$PATH"

terraform -chdir="$STACK_DIR" init -backend=false
terraform -chdir="$STACK_DIR" validate
bash scripts/plan-stack.sh proxmox-base lab

terraform -chdir="$ROOT_DIR" state pull > "$LEGACY_STATE"
terraform -chdir="$STACK_DIR" state pull > "$NEW_STATE"

terraform state mv -state="$LEGACY_STATE" -state-out="$NEW_STATE" "$LEGACY_CT" "$NEW_CT"
terraform state mv -state="$LEGACY_STATE" -state-out="$NEW_STATE" "$LEGACY_VM" "$NEW_VM"

terraform -chdir="$STACK_DIR" plan -var-file="$COMMON_VARS" -var-file="$STACK_VARS" -var environment=lab -var inventory_root=../../inventory
EOF
}

if [[ "$EXECUTE" != true ]]; then
  show_commands
  exit 0
fi

if ! TERRAFORM_BIN="$(resolve_terraform)"; then
  echo "terraform CLI is required." >&2
  exit 2
fi

for file in "$COMMON_VARS" "$STACK_VARS"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file for execution: $file" >&2
    echo "Copy the corresponding .example file first." >&2
    exit 1
  fi
done

"$TERRAFORM_BIN" -chdir="$STACK_DIR" init -backend=false
"$TERRAFORM_BIN" -chdir="$STACK_DIR" validate
bash "$ROOT_DIR/scripts/plan-stack.sh" proxmox-base lab

"$TERRAFORM_BIN" -chdir="$ROOT_DIR" state pull > "$LEGACY_STATE"
"$TERRAFORM_BIN" -chdir="$STACK_DIR" state pull > "$NEW_STATE"

"$TERRAFORM_BIN" state mv -state="$LEGACY_STATE" -state-out="$NEW_STATE" "$LEGACY_CT" "$NEW_CT"
"$TERRAFORM_BIN" state mv -state="$LEGACY_STATE" -state-out="$NEW_STATE" "$LEGACY_VM" "$NEW_VM"

echo "Offline state move complete. Review $NEW_STATE before any state push or backend write." >&2
