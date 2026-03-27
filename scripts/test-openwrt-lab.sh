#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: scripts/test-openwrt-lab.sh [terraform plan args...]

Deprecated compatibility wrapper.
Use scripts/test-openwrt-dev.sh for the active dev target.
EOF
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

printf '%s\n' "Deprecated compatibility wrapper: use scripts/test-openwrt-dev.sh" >&2
exec "$ROOT_DIR/scripts/test-openwrt-dev.sh" "$@"
