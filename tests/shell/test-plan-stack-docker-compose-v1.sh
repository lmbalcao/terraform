#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKEBIN="$TMP_DIR/fakebin"
mkdir -p "$FAKEBIN"

TEST_ROOT="$TMP_DIR/repo"
mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/stacks/openwrt-dns" "$TEST_ROOT/env/dev" "$TEST_ROOT/inventory/dev"
cp "$SOURCE_ROOT/scripts/plan-stack.sh" "$TEST_ROOT/scripts/plan-stack.sh"

cat >"$FAKEBIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
  echo "docker: 'compose' is not a docker command." >&2
  exit 1
fi
echo "unexpected docker invocation: $*" >&2
exit 99
EOF

cat >"$FAKEBIN/docker-compose" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "docker-compose version 1.29.2, build test"
  exit 0
fi
printf '%s\n' "\$*" >>"$TMP_DIR/docker-compose.log"
exit 0
EOF

chmod +x "$FAKEBIN/docker" "$FAKEBIN/docker-compose"

COMPOSE_FILE="$TMP_DIR/docker-compose.run.yml"
cat >"$COMPOSE_FILE" <<'EOF'
services:
  terraform:
    image: hashicorp/terraform:1.5.7
EOF

export PATH="$FAKEBIN:/usr/bin:/bin"
export TERRAFORM_COMPOSE_FILE="$COMPOSE_FILE"

OUTPUT="$TMP_DIR/output.log"
if ! bash "$TEST_ROOT/scripts/plan-stack.sh" openwrt-dns dev >"$OUTPUT" 2>&1; then
  cat "$OUTPUT" >&2
  exit 1
fi

grep -q "run --rm -T -v $TEST_ROOT:/workspace terraform -chdir=/workspace/stacks/openwrt-dns init -backend=false" "$TMP_DIR/docker-compose.log"
grep -q "run --rm -T -v $TEST_ROOT:/workspace terraform -chdir=/workspace/stacks/openwrt-dns plan -var environment=dev -var inventory_root=../../inventory" "$TMP_DIR/docker-compose.log"
