#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  README.md
  CHANGELOG.md
  AGENTS.md
  CONTRIBUTING.md
  SECURITY.md
  CODEOWNERS
  .editorconfig
  .gitattributes
  .gitignore
  .claude/settings.json
  .forgejo/workflows/validate.yml
  .forgejo/pull_request_template.md
  .forgejo/ISSUE_TEMPLATE/bug.yml
  .forgejo/ISSUE_TEMPLATE/feature.yml
  .forgejo/ISSUE_TEMPLATE/config.yml
  docs/inventory-schema.md
  docs/migration-runbook.md
  docs/state-migration-map-lab.md
  docs/stack-boundaries.md
  docs/architecture-decisions/0001-inventory-and-state.md
  schemas/inventory-environment.schema.json
  inventory/lab/ingress.yaml
  scripts/update-changelog.py
  scripts/validate-inventory.py
  scripts/validate-inventory.sh
  scripts/plan-stack.sh
  scripts/cutover-lab.sh
  stacks/openwrt-dns/versions.tf
  stacks/openwrt-dns/providers.tf
  stacks/openwrt-dns/variables.tf
  stacks/openwrt-dns/locals.tf
  stacks/openwrt-dns/main.tf
  stacks/openwrt-dns/outputs.tf
  env/lab/openwrt-dns.tfvars.example
  legacy/root-module/README.md
)

for path in "${required_files[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
done

required_dirs=(
  inventory
  modules
  stacks
  env
  docs
  legacy
)

for path in "${required_dirs[@]}"; do
  if [[ ! -d "$path" ]]; then
    echo "Missing required directory: $path" >&2
    exit 1
  fi
done

mapfile -t root_tf_files < <(find . -maxdepth 1 -type f -name "*.tf" | sort)
if (( ${#root_tf_files[@]} > 0 )); then
  printf "Root Terraform files must not exist outside legacy/:
" >&2
  printf "  %s
" "${root_tf_files[@]}" >&2
  exit 1
fi

if [[ -f .terraform.lock.hcl ]]; then
  echo "Root .terraform.lock.hcl must not exist outside legacy/" >&2
  exit 1
fi

if [[ -f .forgejo/workflows/release.yml && ! -f VERSION ]]; then
  echo "Missing VERSION for release-enabled repository" >&2
  exit 1
fi

if [[ -f VERSION ]]; then
  python3 - <<"PYCODE"
import re
from pathlib import Path
line = Path("VERSION").read_text(encoding="utf-8").splitlines()[0].strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", line):
    raise SystemExit("VERSION first line must be semantic version X.Y.Z")
PYCODE
fi

mapfile -t shell_files < <(find .claude .codex scripts -type f -name "*.sh" | sort)
if (( ${#shell_files[@]} > 0 )); then
  bash -n "${shell_files[@]}"
fi

mapfile -t python_files < <(find scripts -type f -name "*.py" | sort)
if (( ${#python_files[@]} > 0 )); then
  python3 -m py_compile "${python_files[@]}"
fi

python3 -m json.tool .claude/settings.json >/dev/null

echo "Repository baseline validation passed."
