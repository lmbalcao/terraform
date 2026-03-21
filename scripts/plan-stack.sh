#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <stack> <environment> [extra terraform args...]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK="$1"
ENVIRONMENT="$2"
shift 2

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

if ! TERRAFORM_BIN="$(resolve_terraform)"; then
  echo "terraform CLI is required to run this script." >&2
  echo "Install terraform or place a local binary at $ROOT_DIR/.tools/bin/terraform." >&2
  exit 2
fi

STACK_DIR="$ROOT_DIR/stacks/$STACK"
COMMON_VARS="$ROOT_DIR/env/$ENVIRONMENT/common.tfvars"
STACK_VARS="$ROOT_DIR/env/$ENVIRONMENT/$STACK.tfvars"

if [[ ! -d "$STACK_DIR" ]]; then
  echo "Unknown stack: $STACK_DIR" >&2
  exit 1
fi

"$TERRAFORM_BIN" -chdir="$STACK_DIR" init -backend=false

plan_args=(
  -var "environment=$ENVIRONMENT"
  -var "inventory_root=../../inventory"
)

if [[ -f "$COMMON_VARS" ]]; then
  plan_args+=(-var-file "$COMMON_VARS")
fi

if [[ -f "$STACK_VARS" ]]; then
  plan_args+=(-var-file "$STACK_VARS")
fi

"$TERRAFORM_BIN" -chdir="$STACK_DIR" plan "${plan_args[@]}" "$@"
