# Full Reseed CT Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local `terraform` repository the single source of truth, align Forgejo to that exact revision, fully reseed the `dev` lab from scratch, and prove CT provisioning behavior end-to-end in the rebuilt real environment.

**Architecture:** The work proceeds in strict order: first stabilize and publish the local repository, then destroy prior runtime state, then rebuild the Terraform runtime via `dev-install`, and finally run real CT validation against that rebuilt environment. All corrections are made in the local repository, republished, and revalidated in the live lab until the target behaviors pass with evidence.

**Tech Stack:** Git, Forgejo, Proxmox VE, LXC/VM tooling (`pct`, `qm`), Docker Compose, Terraform CLI, Telmate Proxmox provider, Joneshf OpenWrt provider, shell/Python helper scripts, YAML inventory.

---

### Task 1: Consolidate And Publish The Local Repository

**Files:**
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/README.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/architecture-report-dev-prod.md`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/ingress.yaml`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-ct/main.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-vm/main.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-vm/variables.tf`
- Modify: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/main.tf`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/cts/wikijs.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/vms/rdtclient.yaml`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/cts/homarr.yaml`
- Delete: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/vms/vm-template.yaml`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/superpowers/specs/2026-03-28-full-reseed-ct-validation-design.md`
- Create: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/superpowers/plans/2026-03-28-full-reseed-ct-validation.md`

- [ ] **Step 1: Inspect the working tree and recent history**

Run:
```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform status --short --branch
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform log --oneline --decorate -n 10
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform diff --stat
```

Expected: local `main` ahead of `origin/main` with the pending dev alignment changes visible.

- [ ] **Step 2: Run the repo validation entrypoints that do not require remote lab access**

Run:
```bash
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-repo.sh
bash /home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.sh dev
```

Expected: schema/repo checks succeed and `dev` inventory renders the intended active objects.

- [ ] **Step 3: Commit the repository state that will become the source of truth**

Run:
```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform add README.md docs/architecture-report-dev-prod.md inventory/dev/ingress.yaml modules/proxmox-ct/main.tf modules/proxmox-vm/main.tf modules/proxmox-vm/variables.tf stacks/proxmox-base/main.tf inventory/dev/cts/wikijs.yaml inventory/dev/vms/rdtclient.yaml inventory/dev/cts/homarr.yaml inventory/dev/vms/vm-template.yaml docs/superpowers/specs/2026-03-28-full-reseed-ct-validation-design.md docs/superpowers/plans/2026-03-28-full-reseed-ct-validation.md
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform commit -m "feat: align dev reseed workflow and ct validation"
```

Expected: a new commit capturing the exact local state to publish.

- [ ] **Step 4: Push the source-of-truth revision to Forgejo**

Run:
```bash
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform push origin main
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform rev-parse HEAD
git -C /home/lmbalcao/Documentos/vscode-workspace/repos/terraform rev-parse origin/main
```

Expected: local `HEAD` and `origin/main` resolve to the same commit.

### Task 2: Capture And Wipe The Existing Lab Runtime

**Files:**
- Modify if needed after evidence: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/docs/architecture-report-dev-prod.md`

- [ ] **Step 1: Inventory the current Proxmox runtime before deletion**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'hostname && pct list && qm list && ls -la /var/lib/vz/snippets || true'
```

Expected: an evidence snapshot of current CTs, VMs and snippet/config residue.

- [ ] **Step 2: Destroy every existing CT and VM in Proxmox**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'for id in $(pct list | awk "NR>1 {print \$1}"); do pct stop "$id" >/dev/null 2>&1 || true; pct destroy "$id" --purge 1; done; for id in $(qm list | awk "NR>1 {print \$1}"); do qm stop "$id" >/dev/null 2>&1 || true; qm destroy "$id" --purge 1 --destroy-unreferenced-disks 1; done'
```

Expected: `pct list` and `qm list` return only headers or no remaining workloads.

- [ ] **Step 3: Remove residual Proxmox snippets and ad hoc config leftovers**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'rm -f /var/lib/vz/snippets/* || true; find /etc/pve -maxdepth 3 \\( -name "*dev-terraform*" -o -name "*wikijs*" -o -name "*rdtclient*" -o -name "*homarr*" \\) -print'
```

Expected: snippets removed and any remaining PVE-managed config references visible for follow-up.

### Task 3: Clean OpenWrt And Traefik Residue

**Files:**
- No code changes planned; this task validates and cleans runtime state only.

- [ ] **Step 1: Discover the real OpenWrt target from the published tfvars and current docs**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'python3 - <<\"PY\"\nimport json\nfrom pathlib import Path\np = Path(\"/mnt/data/terraform-lab/tfvars/lab-openwrt-dns.tfvars.json\")\nprint(p.read_text())\nPY'
```

Expected: the real OpenWrt hostname, port and credentials source are visible from the lab tfvars.

- [ ] **Step 2: Remove stale OpenWrt DHCP/DNS/firewall entries using real credentials**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'bash -lc '\''python3 /opt/terraform/workspace/scripts/test-openwrt-dev.sh --cleanup || true'\'''
```

Expected: stale runtime entries are removed or the script reports none to remove.

- [ ] **Step 3: Verify Traefik has no stale lab routes or file-provider entries**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'grep -RInE "wikijs|homarr|rdtclient|lbtec\\.org" /mnt/data /opt /etc 2>/dev/null | head -n 200'
```

Expected: either no relevant stale Traefik residue, or concrete file locations to clean before rebuild.

### Task 4: Recreate The Terraform Runtime With Dev-Install

**Files:**
- Modify if needed after evidence: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/*`

- [ ] **Step 1: Locate the authoritative dev-install source**

Run:
```bash
grep -RInE 'dev-install|curl .*github|dev-proxmox' /home/lmbalcao/Documentos/vscode-workspace/repos /home/lmbalcao/.config/superpowers 2>/dev/null | head -n 200
```

Expected: an exact repository/script URL or local reference for the bootstrap command.

- [ ] **Step 2: Run dev-install from dev-proxmox**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'curl -fsSL https://raw.githubusercontent.com/lmbalcao/scripts/master/scripts/dev-install.sh | bash'
```

Expected: a new Terraform CT is created from scratch by the bootstrap flow.

- [ ] **Step 3: Identify the new Terraform CT and verify its runtime**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'pct list'
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "hostname && docker --version && docker compose version && terraform version && git -C /opt/terraform/workspace rev-parse HEAD"'
```

Expected: the CT exists, Docker and Terraform are installed, and the cloned repo revision matches the Forgejo commit from Task 1.

### Task 5: Run Real CT Validation On The Rebuilt Runtime

**Files:**
- Modify if needed after failures: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/inventory/dev/cts/*.yaml`
- Modify if needed after failures: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/modules/proxmox-ct/main.tf`
- Modify if needed after failures: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/*.tf`
- Modify if needed after failures: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/openwrt-dns/*.tf`
- Modify if needed after failures: `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/*.sh`

- [ ] **Step 1: Prepare two real CT test definitions in the runtime inventory**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "cd /opt/terraform/workspace && ls inventory/dev/cts && ls /mnt/data/terraform-lab/tfvars"'
```

Expected: runtime inventory and tfvars are present for test CT creation.

- [ ] **Step 2: Create the test CTs and validate Proxmox runtime state**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "cd /opt/terraform/workspace && STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json bash scripts/plan-stack.sh proxmox-base dev"'
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "cd /opt/terraform/workspace/stacks/proxmox-base && /opt/terraform/workspace/.tools/bin/terraform apply -auto-approve -var-file=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json -var environment=dev -var inventory_root=../../inventory"'
```

Expected: the two CTs are created and visible in `pct list` with the declared runtime properties.

- [ ] **Step 3: Validate addons and side effects**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'pct list'
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'for id in $(pct list | awk '\''NR>1 {print $1}'\''); do pct config "$id"; done'
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "cd /opt/terraform/workspace/stacks/openwrt-dns && /opt/terraform/workspace/.tools/bin/terraform apply -auto-approve -var-file=/mnt/data/terraform-lab/tfvars/lab-openwrt-dns.tfvars.json -var environment=dev -var inventory_root=../../inventory"'
```

Expected: CT notes include Traefik data when `services[]` is present, OpenWrt receives the expected hostname and firewall/DNS state, and any app-driven mount behavior can be inspected with evidence.

- [ ] **Step 4: Edit and then destroy the test CTs**

Run:
```bash
ssh -i /home/lmbalcao/.ssh/id_ed25519_lab_hosts root@192.168.99.100 'CTID=$(pct list | awk '\''/dev-terraform/ {print $1; exit}'\''); pct exec "$CTID" -- bash -lc "cd /opt/terraform/workspace && git status --short && echo runtime-edit-phase"'
```

Expected: runtime inventory can be edited for a second apply and later returned to a clean post-test state.

### Task 6: Fix Failures Iteratively And Publish Final Evidence

**Files:**
- Modify as required by real failures under `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform`

- [ ] **Step 1: Reproduce each failure with concrete command output**

Run:
```bash
printf 'Use the exact failing command and capture the exact provider or runtime error before editing code.\n'
```

Expected: each defect is anchored to real evidence, not inference.

- [ ] **Step 2: Implement the minimal correction in the local repo and republish**

Run:
```bash
printf 'Edit only the files implicated by the failure, rerun local validation, commit, and push to origin/main before retesting the rebuilt lab.\n'
```

Expected: every runtime fix exists in the local repo and in Forgejo before the next real retest.

- [ ] **Step 3: Re-run the affected real tests until they pass or a hard external blocker is proved**

Run:
```bash
printf 'Repeat the specific remote Terraform/OpenWrt/Traefik verification commands tied to the failed behavior.\n'
```

Expected: final report distinguishes passed behavior, failed behavior, and proven external blockers.
