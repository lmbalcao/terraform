#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="dev"
STACK="${STACK:-openwrt-dns}"
STACK_DIR="$ROOT_DIR/stacks/$STACK"
PROVIDER_DIR="${PROVIDER_DIR:-$ROOT_DIR/../terraform-provider-openwrt}"
PROXMOX_VERSION_URL="${PROXMOX_VERSION_URL:-https://192.168.99.100:8006/api2/json/version}"
OPENWRT_BASE_URL="${OPENWRT_BASE_URL:-http://192.168.99.200:80}"
OPENWRT_USERNAME="${OPENWRT_USERNAME:-root}"
OPENWRT_PASSWORD="${OPENWRT_PASSWORD:-sandman}"
TF_CLI_CONFIG_FILE_TMP="$(mktemp /tmp/openwrt-provider-XXXXXX.tfrc)"

usage() {
  cat <<EOF
Usage: scripts/test-openwrt-dev.sh [terraform plan args...]

Experimental helper for the `openwrt-dns` dev target.
This path depends on a local OpenWrt provider override and requires Go.
EOF
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

cleanup() {
  rm -f "$TF_CLI_CONFIG_FILE_TMP"
}
trap cleanup EXIT

log() {
  echo "[test-openwrt-dev] $*"
}
die() {
  log "ERROR: $*"
  exit 1
}
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}
resolve_terraform() {
  if [[ -n "${TERRAFORM_BIN:-}" && -x "$TERRAFORM_BIN" ]]; then
    echo "$TERRAFORM_BIN"
    return 0
  fi
  if command -v terraform >/dev/null 2>&1; then
    command -v terraform
    return 0
  fi
  for candidate in "$ROOT_DIR/.tools/bin/terraform" "$ROOT_DIR/.tools/terraform-1.5.7/terraform"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

write_tf_cli_config() {
  cat >"$TF_CLI_CONFIG_FILE_TMP" <<EOF
provider_installation {
  dev_overrides {
    "joneshf/openwrt" = "$PROVIDER_DIR"
  }

  direct {}
}
EOF
}
probe_hosts() {
  python3 - "$PROXMOX_VERSION_URL" "$OPENWRT_BASE_URL" "$OPENWRT_USERNAME" "$OPENWRT_PASSWORD" <<EOF
import json
import sys
import urllib.error
import urllib.request
proxmox_url, openwrt_base, username, password = sys.argv[1:]
def request(url, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {} if payload is None else {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.getcode(), response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
proxmox_status, proxmox_body = request(proxmox_url)
if proxmox_status != 200:
    raise SystemExit("Proxmox version probe failed: " + str(proxmox_status))
legacy_status, _ = request(openwrt_base + "/cgi-bin/luci/rpc/auth")
if legacy_status not in (200, 404):
    raise SystemExit("Unexpected legacy auth status: " + str(legacy_status))
payload = {"jsonrpc": "2.0", "id": 1, "method": "call", "params": ["00000000000000000000000000000000", "session", "login", {"username": username, "password": password}]}
status, body = request(openwrt_base + "/cgi-bin/luci/admin/ubus", payload)
if status != 200:
    raise SystemExit("admin/ubus login HTTP failed: " + str(status))
result = json.loads(body).get("result")
if not isinstance(result, list) or not result or result[0] != 0:
    raise SystemExit("admin/ubus login failed")
print("proxmox_ok")
print("openwrt_legacy_status=" + str(legacy_status))
print("openwrt_admin_ubus=ok")
EOF
}
show_inventory_state() {
  if grep -q "traefik_instances: {}" "$ROOT_DIR/inventory/$ENVIRONMENT/ingress.yaml"; then
    log "inventory/$ENVIRONMENT/ingress.yaml has no traefik_instances"
  fi
  if ! grep -Rqs "traefik_tag" "$ROOT_DIR/inventory/$ENVIRONMENT/cts" "$ROOT_DIR/inventory/$ENVIRONMENT/vms"; then
    log "inventory/$ENVIRONMENT has no services with traefik_tag; $STACK plan is expected to be empty"
  fi
}

ensure_local_provider_requirements() {
  need_cmd go
}

run_plan() {
  local terraform_bin common_vars stack_vars
  terraform_bin="$(resolve_terraform)" || die "terraform CLI is required"
  common_vars="$ROOT_DIR/env/$ENVIRONMENT/common.tfvars"
  stack_vars="$ROOT_DIR/env/$ENVIRONMENT/$STACK.tfvars"
  local plan_args=( -var "environment=$ENVIRONMENT" -var "inventory_root=../../inventory" )
  if [[ -f "$common_vars" ]]; then plan_args+=( -var-file "$common_vars" ); fi
  if [[ -f "$stack_vars" ]]; then plan_args+=( -var-file "$stack_vars" ); fi
  TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_FILE_TMP" "$terraform_bin" -chdir="$STACK_DIR" plan "${plan_args[@]}" "$@"
}
main() {
  need_cmd git
  need_cmd python3
  ensure_local_provider_requirements
  bash "$ROOT_DIR/scripts/sync-local-openwrt-provider.sh"
  write_tf_cli_config
  probe_hosts
  show_inventory_state
  run_plan "$@"
}
main "$@"
