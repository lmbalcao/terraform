# Historical Lab External Credentials Implementation Plan

> Historical execution artifact. This file records a dated plan around the former `lab` naming and `/mnt/data/terraform-lab/` layout. It is not the operational architecture document for the current repo.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materializar credenciais locais dos hosts externos do lab fora do git e ligar os stacks ativos a `tfvars` gerados a partir de um manifesto consolidado.

**Architecture:** Um manifesto JSON consolidado guarda os segredos e metadados de acesso no CT Terraform. Um helper local do repo gera os `tfvars` válidos para `proxmox-base` e `openwrt-dns`, além do inventário de acesso aos restantes hosts.

**Tech Stack:** Python 3, Terraform tfvars JSON, SSH, Proxmox VE CLI, PBS CLI, OpenWrt shell

---

### Task 1: Add the local tfvars renderer

**Files:**
- Create: `scripts/render-local-tfvars.py`
- Test: `tests/test_render_local_tfvars.py`

- [x] **Step 1: Write the failing test**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Write minimal implementation**
- [x] **Step 4: Run test to verify it passes**

### Task 2: Create local credential artifacts

**Files:**
- Create: `/mnt/data/terraform-lab/credentials/lab-credentials.json`
- Create: `/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json`
- Create: `/mnt/data/terraform-lab/tfvars/lab-openwrt-dns.tfvars.json`
- Create: `/mnt/data/terraform-lab/tfvars/lab-external-hosts.json`

- [ ] **Step 1: Ensure SSH key material exists on the Terraform CT**
- [ ] **Step 2: Create or rotate API/password credentials on Proxmox, PBS, and OpenWrt**
- [ ] **Step 3: Render stack tfvars from the consolidated manifest**
- [ ] **Step 4: Write the rendered outputs into `/mnt/data`**

### Task 3: Sanitize the local workspace

**Files:**
- Modify: `env/lab/openwrt-dns.tfvars`
- Create: `docs/local-credentials.md`

- [ ] **Step 1: Remove local cleartext credentials from the workspace checkout**
- [ ] **Step 2: Document the `/mnt/data` credential flow for operators**
- [ ] **Step 3: Re-run the helper test and repo validation relevant to the new helper**
