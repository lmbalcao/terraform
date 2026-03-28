#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/lmbalcao/Documentos/vscode-workspace/repos/terraform"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

INV="$TMP_DIR/inventory/dev"
APPS="$TMP_DIR/docker-apps"
mkdir -p "$INV/cts" "$INV/vms" "$APPS/rdtclient"

cat >"$INV/defaults.yaml" <<'EOF'
version: 1
defaults:
  common:
    tags: []
    services: []
    operations: {}
  ct:
    enabled: true
    boot:
      on_boot: false
      start: true
    resources:
      cpu_cores: 1
      memory_mb: 512
      swap_mb: 0
    storage:
      rootfs_storage: local-lvm
      rootfs_size_gb: 4
    lxc:
      unprivileged: true
      features:
        nesting: true
      mounts: []
EOF

cat >"$INV/nodes.yaml" <<'EOF'
version: 1
nodes:
  dev-proxmox:
    address: 192.168.99.100
EOF

cat >"$INV/networks.yaml" <<'EOF'
version: 1
networks:
  vlan-99:
    bridge: vmbr0
    dns_domain: lbtec.org
    dns_servers:
      - 192.168.99.200
EOF

cat >"$INV/ingress.yaml" <<'EOF'
version: 1
traefik_instances: {}
EOF

cat >"$INV/cts/testapp.yaml" <<'EOF'
version: 1
kind: ct
enabled: true
vmid: 102
name: testapp
hostname: testapp
node: dev-proxmox
apps:
  - rdtclient
network:
  segment: vlan-99
  mode: dhcp
resources:
  cpu_cores: 1
  memory_mb: 512
  swap_mb: 128
boot:
  on_boot: false
  start: true
storage:
  rootfs_storage: local-lvm
  rootfs_size_gb: 4
lxc:
  template: local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
  unprivileged: true
  features:
    nesting: true
    keyctl: true
    fuse: false
  mounts:
    - slot: 9
      mp: /srv/manual
      storage: local-lvm
      size_gb: 2
      backup: true
services: []
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
EOF

cat >"$APPS/rdtclient/docker-compose.yml" <<'EOF'
services:
  rdtclient:
    image: rogerfar/rdtclient
    volumes:
      - /opt/rdtclient:/data/db
      - /mnt/data:/data/data
      - /mnt/downloads:/data/downloads
EOF

VALIDATION_OUTPUT="$TMP_DIR/validate.json"
python3 "$ROOT/scripts/validate-inventory.py" --inventory-root "$TMP_DIR/inventory" dev >"$VALIDATION_OUTPUT"
grep -q '"cts": \["testapp"\]' "$VALIDATION_OUTPUT"

CONSOLE_OUTPUT="$TMP_DIR/console.json"
"$ROOT/.tools/bin/terraform" -chdir="$ROOT/stacks/proxmox-base" console \
  -var 'environment=dev' \
  -var "inventory_root=$TMP_DIR/inventory" \
  -var "docker_apps_root=$APPS" \
  -var 'proxmox_api_url=https://example.invalid:8006/api2/json' \
  -var 'proxmox_api_token_id=root@pam!dummy' \
  -var 'proxmox_api_token=dummy' \
  -var 'root_password=dummy' \
  <<< 'jsonencode({features=local.ct_features["testapp"], mountpoints=local.ct_mountpoints["testapp"]})' >"$CONSOLE_OUTPUT"

python3 - "$CONSOLE_OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data = json.loads(payload)

assert data["features"]["keyctl"] is True
assert data["features"]["nesting"] is True
mounts = {item["mp"]: item for item in data["mountpoints"]}
assert mounts["/opt/rdtclient"]["size"] == "4G"
assert mounts["/mnt/data"]["size"] == "4G"
assert mounts["/mnt/downloads"]["size"] == "4G"
assert mounts["/srv/manual"]["size"] == "2G"
assert mounts["/srv/manual"]["backup"] is True
PY
