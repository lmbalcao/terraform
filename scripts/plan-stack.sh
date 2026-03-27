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
RUNNER_MODE=""
RUNNER_ROOT=""
COMPOSE_FILE=""

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

resolve_compose_file() {
  local candidates=(
    "${TERRAFORM_COMPOSE_FILE:-}"
    "$ROOT_DIR/../docker-compose.run.yml"
    "$ROOT_DIR/../docker-compose.yml"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  return 1
}

if TERRAFORM_BIN="$(resolve_terraform)"; then
  RUNNER_MODE="local"
  RUNNER_ROOT="$ROOT_DIR"
elif COMPOSE_FILE="$(resolve_compose_file)" && command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  RUNNER_MODE="docker-compose"
  RUNNER_ROOT="/workspace"
else
  echo "terraform CLI is required to run this script." >&2
  echo "Install terraform, place a local binary at $ROOT_DIR/.tools/bin/terraform, or run from a host with docker compose and $ROOT_DIR/../docker-compose.run.yml available." >&2
  exit 2
fi

STACK_DIR="$ROOT_DIR/stacks/$STACK"
COMMON_VARS_DEFAULT="$ROOT_DIR/env/$ENVIRONMENT/common.tfvars"
STACK_VARS_DEFAULT="$ROOT_DIR/env/$ENVIRONMENT/$STACK.tfvars"
COMMON_VARS="${COMMON_VARS_FILE:-$COMMON_VARS_DEFAULT}"
STACK_VARS="${STACK_VARS_FILE:-$STACK_VARS_DEFAULT}"
TF_STACK_DIR="$RUNNER_ROOT/stacks/$STACK"

if [[ ! -d "$STACK_DIR" ]]; then
  echo "Unknown stack: $STACK_DIR" >&2
  exit 1
fi

tfvars_string_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  python3 - "$file" "$key" <<'PYCODE'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
if path.suffix == ".json":
    data = json.loads(path.read_text(encoding="utf-8"))
    value = data.get(key)
    if isinstance(value, bool):
        print("true" if value else "false")
        raise SystemExit(0)
    if value is None:
        raise SystemExit(1)
    print(str(value))
    raise SystemExit(0)
pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$')
for line in path.read_text(encoding="utf-8").splitlines():
    match = pattern.match(line)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
PYCODE
}

ensure_non_placeholder() {
  local label="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "Missing required value for $label." >&2
    return 1
  fi

  case "$value" in
    REPLACE_ME|"<proxmox-api-url>"|"<proxmox-user@realm!token-name>"|"<proxmox-api-token-id>"|"<proxmox-api-token-secret>"|"<ct-root-password>")
      echo "Placeholder value detected for $label: $value" >&2
      return 1
      ;;
  esac
}

to_runner_path() {
  local path="$1"

  if [[ "$RUNNER_MODE" != "docker-compose" ]]; then
    printf "%s\n" "$path"
    return 0
  fi

  case "$path" in
    "$ROOT_DIR")
      printf "%s\n" "$RUNNER_ROOT"
      ;;
    "$ROOT_DIR"/*)
      printf "%s\n" "$RUNNER_ROOT/${path#"$ROOT_DIR"/}"
      ;;
    /mnt/data)
      printf "%s\n" "/opt/data"
      ;;
    /mnt/data/*)
      printf "%s\n" "/opt/data/${path#/mnt/data/}"
      ;;
    *)
      printf "%s\n" "$path"
      ;;
  esac
}

run_terraform() {
  if [[ "$RUNNER_MODE" == "local" ]]; then
    "$TERRAFORM_BIN" "$@"
    return 0
  fi

  docker compose -f "$COMPOSE_FILE" run --rm -T -v "$ROOT_DIR:/workspace" terraform "$@"
}

if [[ "$STACK" == "proxmox-base" ]]; then
  proxmox_api_url="${TF_VAR_proxmox_api_url:-$(tfvars_string_value "$STACK_VARS" "proxmox_api_url" 2>/dev/null || true)}"
  proxmox_api_token_id="${TF_VAR_proxmox_api_token_id:-$(tfvars_string_value "$STACK_VARS" "proxmox_api_token_id" 2>/dev/null || true)}"
  proxmox_api_token="${TF_VAR_proxmox_api_token:-$(tfvars_string_value "$STACK_VARS" "proxmox_api_token" 2>/dev/null || true)}"
  root_password="${TF_VAR_root_password:-$(tfvars_string_value "$STACK_VARS" "root_password" 2>/dev/null || true)}"

  if ! ensure_non_placeholder "proxmox_api_url" "$proxmox_api_url" \
    || ! ensure_non_placeholder "proxmox_api_token_id" "$proxmox_api_token_id" \
    || ! ensure_non_placeholder "proxmox_api_token" "$proxmox_api_token" \
    || ! ensure_non_placeholder "root_password" "$root_password"; then
    cat >&2 <<'EOF'
proxmox-base requires real Proxmox credentials and bootstrap secrets before terraform plan can run meaningfully.
Provide them in env/<environment>/proxmox-base.tfvars or via TF_VAR_proxmox_api_url, TF_VAR_proxmox_api_token_id, TF_VAR_proxmox_api_token, and TF_VAR_root_password.
Without valid Proxmox credentials, terraform plan does not validate provider-backed behavior for this stack.
EOF
    exit 1
  fi
fi

run_terraform -chdir="$TF_STACK_DIR" init -backend=false

plan_args=(
  -var "environment=$ENVIRONMENT"
  -var "inventory_root=../../inventory"
)

if [[ -f "$COMMON_VARS" ]]; then
  plan_args+=(-var-file "$(to_runner_path "$COMMON_VARS")")
fi

if [[ -f "$STACK_VARS" ]]; then
  plan_args+=(-var-file "$(to_runner_path "$STACK_VARS")")
fi

run_terraform -chdir="$TF_STACK_DIR" plan "${plan_args[@]}" "$@"
