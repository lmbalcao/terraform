# Dev And Prod Reality Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the Terraform repository to a final `dev + prod` architecture, remove `lab/staging` from the active model, correct inventory/docs/runtime contracts, and verify the real operational status with real credentials and real provider access before the final architecture report.

**Architecture:** The work is split into four streams: environment normalization, stack/runtime contract correction, real-environment verification, and documentation/reporting. `proxmox-base` remains the core provisioning stack, `openwrt-dns` remains the DNS/OpenWrt stack, and `ansible`/`pbs` stay as minimal handoff stacks with explicitly limited scope.

**Tech Stack:** Terraform CLI 1.5.x, Telmate/proxmox provider, joneshf/openwrt provider, Python 3 helper scripts, YAML inventory, shell verification scripts

---

### Task 1: Capture Current Reality And Safety Baseline

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/superpowers/plans/2026-03-27-dev-prod-reality-alignment.md`
- Check: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform`

- [ ] **Step 1: Record current git status**

Run:

```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform status --short
```

Expected: existing local modifications are visible and noted before changing shared files.

- [ ] **Step 2: Record current repo baseline validation**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-repo.sh
```

Expected: `Repository baseline validation passed.`

- [ ] **Step 3: Record current inventory validation output**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh
```

Expected: JSON summary of currently discovered environments and workloads.

- [ ] **Step 4: Save a short operator note in the implementation log**

Add a short dated note to this plan file under a temporary `Execution Notes` heading with:

```md
## Execution Notes

- Initial git status captured before edits.
- Baseline repo validation captured.
- Initial inventory validation captured.
```

- [ ] **Step 5: Re-run git status to ensure only intended tracking/log changes occurred**

Run:

```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform status --short
```

Expected: no accidental file creation outside the intended plan/spec/docs paths.

## Execution Notes

- 2026-03-27: initial git status captured with existing modifications in `README.md`, `docs/migration-runbook.md`, `env/lab/proxmox-base.tfvars.example`, `scripts/plan-stack.sh`, `stacks/proxmox-base/main.tf`, `stacks/proxmox-base/variables.tf`, plus new `docs/local-credentials.md`, `docs/superpowers/plans/2026-03-27-dev-prod-reality-alignment.md`, `scripts/render-local-tfvars.py`, and `tests/`.
- 2026-03-27: repository baseline validation passed via `bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-repo.sh`.
- 2026-03-27: inventory validation returned `{"environment": "lab", "cts": ["homarr"], "vms": ["vm-template"], "traefik_instances": []}` via `bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh`.
- 2026-03-27: final `git status --short` still showed the same existing modifications and untracked paths; no additional files were introduced by the Task 1 log edit.
- 2026-03-27: Task 2 review follow-up moved the preserved `lab` content into explicit archive paths under `env/legacy/lab/` and `inventory/legacy/lab/`, updated active docs/scripts to `dev` + `prod`, and removed `staging` from the active flow.
- 2026-03-27: Task 4 real proof on `dev-terraform-101` succeeded through `/opt/terraform/docker-compose.run.yml`; `stacks/proxmox-base` planned with exit code 0, no warnings, `target_node = "dev-proxmox"` and `ostemplate = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"`.

### Task 2: Normalize Active Environments To Dev And Prod

**Files:**
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/common.tfvars`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/common.tfvars.example`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/proxmox-base.tfvars`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/proxmox-base.tfvars.example`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/openwrt-dns.tfvars`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/openwrt-dns.tfvars.example`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/ansible.tfvars.example`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/pbs.tfvars.example`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/defaults.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/nodes.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/networks.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/ingress.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/cts/homarr.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/vms/vm-template.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/defaults.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/nodes.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/networks.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/ingress.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/cts/.gitkeep`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/prod/vms/.gitkeep`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/lab/*`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/staging/.gitkeep`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/lab/*`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/staging/.gitkeep`

- [ ] **Step 1: Copy current `lab` environment files to `dev` equivalents**

Use file content from current `env/lab/*` and `inventory/lab/*` as the starting point, adjusting:

```hcl
environment = "dev"
```

and directory naming so that all active references move from `lab` to `dev`.

- [ ] **Step 2: Create a structurally complete `prod` inventory**

Add minimal but valid files for `prod`:

```yaml
version: 1
defaults:
  common:
    tags: []
    services: []
    operations:
      ansible_enabled: false
      backup_policy: null
      bootstrap_profile: null
  ct:
    enabled: true
    boot:
      on_boot: true
      start: true
    resources:
      swap_mb: 1024
    lxc:
      unprivileged: true
      features:
        nesting: true
      features_manual: {}
      mounts: []
  vm:
    enabled: true
    boot:
      on_boot: true
      start_state: running
    qemu:
      sockets: 1
      agent_enabled: false
      source: {}
      disks: []
```

and empty-but-valid `nodes.yaml`, `networks.yaml`, `ingress.yaml` mappings consistent with the current schema.

- [ ] **Step 3: Update any active file paths that hardcode `lab` or `staging`**

Search:

```bash
grep -RInE '\blab\b|\bstaging\b' /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/{README.md,docs,scripts,env,inventory,stacks} | sed -n '1,240p'
```

Expected: a concrete list to update or intentionally keep only in legacy/history sections.

- [ ] **Step 4: Remove `staging` as an active environment**

Delete active references and placeholder directories for `staging`, but keep legacy mentions only where historical context is explicitly labeled as such.

- [ ] **Step 5: Validate environment discovery**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh
```

Expected: only `dev` and `prod` are discovered as environments.

### Task 3: Correct Inventory To Match Verified Runtime Intent

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/defaults.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/nodes.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/networks.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/ingress.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/cts/homarr.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/vms/vm-template.yaml`

- [ ] **Step 1: Collect current contradictory values from docs, state and inventory**

Run:

```bash
grep -RInE 'homarr|vm-template|vm_template|traefik-int|192\\.168\\.|node:' /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/{inventory,docs,stacks/*/terraform.tfstate,legacy/root-module} | sed -n '1,260p'
```

Expected: a single comparison set for `homarr`, `vm-template`, ingress and network values.

- [ ] **Step 2: Decide final `dev` inventory values only from real evidence**

Use this decision rule:

```text
real provider-backed plan/apply evidence > active state evidence > current inventory > outdated docs > legacy defaults
```

Record the chosen values in the inventory files and remove contradictory leftovers.

- [ ] **Step 3: Align Traefik/OpenWrt fields if services are truly active**

If real evidence proves `homarr` has exposed Traefik services, add a concrete `services` block to `inventory/dev/cts/homarr.yaml` and matching `traefik_instances` to `inventory/dev/ingress.yaml`. If not proved, keep them absent and ensure docs/state are corrected to match.

- [ ] **Step 4: Keep `vm-template` disabled unless real evidence requires activation**

The VM inventory should remain:

```yaml
enabled: false
```

unless real plan/apply evidence proves it belongs active in `dev`.

- [ ] **Step 5: Re-run inventory validation**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh dev
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh prod
```

Expected: both environments validate successfully.

### Task 4: Fix Stack Contracts Around CT Features, Mounts, And Minimal Handoff

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/main.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/locals.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/variables.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-ct/main.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-ct/variables.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.py`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/ansible/main.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/pbs/main.tf`

- [ ] **Step 1: Decide the `mounts` contract**

Choose one outcome based on what can be implemented and verified with real data:

```text
A. Implement `mounts` end-to-end in stack + validation + proof
B. Remove non-empty `mounts` from the active contract and document them as unsupported
```

Use option A only if you can verify it against real Proxmox behavior.

- [ ] **Step 2: Make CT manual feature reconciliation explicit and accurate**

Ensure code and docs consistently describe that `nesting`, `keyctl`, `fuse`, `mount`, `description`, `nameserver`, and `searchdomain` are reconciled by `terraform_data + local-exec + apply-proxmox-ct-features.py`, not by pure provider-native provisioning alone.

- [ ] **Step 3: Keep `ansible` and `pbs` minimal but explicit**

If helpful, add concise comments like:

```hcl
# Minimal handoff stack: only filters exported targets, does not manage external systems directly.
```

without changing their intentionally small runtime behavior.

- [ ] **Step 4: Re-run Terraform validation for active stacks**

Run:

```bash
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base init -backend=false
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base validate
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns init -backend=false
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns validate
```

Expected: both stacks validate successfully after contract corrections.

- [ ] **Step 5: Re-run inventory validation after contract corrections**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh
```

Expected: validator and stack contract agree.

### Task 5: Update Scripted Execution Paths To Dev And Prod

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/plan-stack.sh`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/cutover-lab.sh`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/test-openwrt-lab.sh`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/render-local-tfvars.py`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/tests/test_render_local_tfvars.py`

- [ ] **Step 1: Remove active `lab`/`staging` assumptions from operator scripts**

Search and replace active environment handling so scripts default to `dev` where appropriate and support `prod` explicitly.

- [ ] **Step 2: Either migrate or clearly legacy-label one-off migration scripts**

For `cutover-lab.sh` and `test-openwrt-lab.sh`, choose:

```text
A. Rename/adapt to `dev`
B. Move to legacy or mark historical-only in help text and docs
```

Prefer A only if the script remains operationally useful in the final repo.

- [ ] **Step 3: Keep tfvars rendering aligned with final environment names**

Update `render-local-tfvars.py` and its test so generated file names and examples match final supported environment naming.

- [ ] **Step 4: Run the script unit test**

Run:

```bash
python3 -m unittest -q /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/tests/test_render_local_tfvars.py
```

Expected: `OK`

- [ ] **Step 5: Smoke-test the plan wrapper against `dev`**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/plan-stack.sh proxmox-base dev
```

Expected: either a real provider-backed plan attempt with real credentials, or a precise early failure if required real credentials are still missing.

### Task 6: Prove Real Provider Behavior With Real Credentials

**Files:**
- Check: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/*`
- Check: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/prod/*`
- Check: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base`
- Check: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns`

- [ ] **Step 1: Verify real credentials are available for `dev`**

Run the relevant operator commands or inspect the real tfvars location documented in the repo, then confirm that placeholders are gone for:

```text
proxmox_api_url
proxmox_api_token_id
proxmox_api_token
root_password
openwrt_hostname
openwrt_password
```

- [ ] **Step 2: Run a real `proxmox-base` dev plan**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/plan-stack.sh proxmox-base dev
```

Expected: a real provider-backed plan result, not just static validation.

- [ ] **Step 3: Run a real `openwrt-dns` dev plan**

Run:

```bash
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns plan \
  -var-file=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/common.tfvars \
  -var-file=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/env/dev/openwrt-dns.tfvars \
  -var environment=dev \
  -var inventory_root=../../inventory
```

Expected: a real provider-backed plan result against OpenWrt.

- [ ] **Step 4: Record evidence for specific feature claims**

From plan output, state, and any successful provider interactions, record whether the following are:

```text
defined
plan-proved
apply/state-proved
not proved
```

for CT provisioning, VM provisioning, Traefik notes, CT manual features, mounts, OpenWrt DNS, OpenWrt firewall, Proxmox provider, OpenWrt provider, and helper scripts.

- [ ] **Step 5: Repeat for `prod` if real data exists**

If real credentials/data exist for `prod`, run equivalent real plans. If not, explicitly record `prod` as structurally prepared but not operationally proved.

### Task 7: Correct States, Drift Narrative, And Main Documentation

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/README.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/stack-boundaries.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/inventory-schema.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/migration-runbook.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/state-migration-map-lab.md`
- Modify or Replace: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/local-credentials.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/CHANGELOG.md`

- [ ] **Step 1: Remove or replace docs that state obsolete `lab/staging` reality**

Docs must describe only:

```text
active final model
explicitly historical legacy notes
evidence-backed operational status
```

- [ ] **Step 2: Replace misleading migration notes**

`state-migration-map-lab.md` should either be:

```text
A. replaced by a final `dev` migration/state note
B. moved to historical/legacy context with explicit labeling
```

Do not leave it as if it described current reality.

- [ ] **Step 3: Rewrite top-level docs around the final stack model**

The README and architecture docs should make clear that:

```text
proxmox-base = base infra
openwrt-dns = DNS/firewall derived stack
ansible/pbs = minimal handoff stacks
legacy root module = historical only
```

- [ ] **Step 4: Update changelog only with factual repository changes**

Add a short entry summarizing the alignment work without claiming unproved runtime success.

- [ ] **Step 5: Re-read the changed docs for contradiction**

Run:

```bash
grep -RInE '\blab\b|\bstaging\b|Rundeck|Portainer|Restic|Vault' /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/{README.md,docs} | sed -n '1,260p'
```

Expected: remaining mentions are either removed or clearly labeled historical/legacy.

### Task 8: Produce Final Architecture Report And Fresh Verification Evidence

**Files:**
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/architecture-report-dev-prod.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/superpowers/plans/2026-03-27-dev-prod-reality-alignment.md`

- [ ] **Step 1: Write the final report from fresh evidence only**

The report must include:

```text
simple overview
real architecture diagram
environment map
CT generation flow
configuration application map
feature status table
providers/addons status
practical execution flow
risks/debt/confusion
2-minute summary sections
```

and must separate `defined`, `plan-proved`, `applied`, and `not proved`.

- [ ] **Step 2: Run the full verification set again**

Run:

```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-repo.sh
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base validate
./.tools/bin/terraform -chdir=/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns validate
python3 -m unittest -q /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/tests/test_render_local_tfvars.py
```

Plus fresh real plan commands for `dev`, and for `prod` if credentials exist.

- [ ] **Step 3: Compare the final report against the spec**

Check that every required correction from the approved design is reflected:

```text
dev + prod only
ansible/pbs minimal
no false claims
real-evidence classification
corrected docs
corrected drift narrative
```

- [ ] **Step 4: Capture final git status**

Run:

```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform status --short
```

Expected: only intended repository changes remain.

- [ ] **Step 5: Prepare completion summary with evidence**

The final user-facing summary must cite:

```text
what changed
what was verified
what was not possible to prove
where the final report lives
```
