# Terraform Proxmox Platform

Repositorio Terraform para gerir infraestrutura Proxmox a partir de inventario YAML por ambiente.

## O Que O Repo Faz Hoje

- `stacks/proxmox-base` modela e planeia CTs e VMs Proxmox a partir de `inventory/<environment>/`
- `stacks/openwrt-dns` deriva registos DNS e regras agregadas de firewall OpenWrt a partir de `services[]` e `ingress.yaml`
- `stacks/proxmox-base` prepara notes/description Proxmox compatíveis com o `traefik-proxmox-provider` para CTs e VMs
- `stacks/ansible` e `stacks/pbs` sao stacks minimos de handoff; filtram outputs do core, mas nao gerem sistemas externos diretamente
- `legacy/root-module/` existe apenas para referencia historica e apoio a migracao de state

## Ambientes Ativos

- `dev`: unico ambiente com inventario real e prova operacional neste workspace
- `prod`: ambiente estruturalmente preparado no repo, sem prova operacional neste workspace

Em `/mnt/data` e no CT atual nao foram encontrados manifestos ou `tfvars` reais de `prod`.

Conteudo historico de `lab` foi arquivado em `env/legacy/lab/` e `inventory/legacy/lab/`.

## Estado Verificado

### `proxmox-base`

Prova real obtida em `2026-03-27` no CT `dev-terraform-101`, usando `docker compose` em `/opt/terraform/docker-compose.run.yml` e credenciais reais montadas de `/mnt/data`.

Resultado provado:

- `plan` com exit code `0`
- sem warnings
- CT `homarr` planeado com:
  - `target_node = "dev-proxmox"`
  - `vmid = 6011`
  - `ostemplate = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"`
- neste contexto de teste, o inventario ativo nao declara `vlan` e os workloads Terraform ficam na rede `192.168.99.0/24`
- `apply` cria fisicamente o CT `6011` e deixa-o `running` no Proxmox real
- a reconciliacao `terraform_data.ct_manual_features` depende de `python3`; no runtime real do CT Terraform isso passou a ser bootstrapado no proprio provisioner quando a imagem `hashicorp/terraform` nao o inclui

### `openwrt-dns`

Evidência atual no workspace:

- o source Terraform continua a ser `joneshf/openwrt`
- o repo suporta override local do provider com `dev_overrides` para o fork `../terraform-provider-openwrt`
- o fork local implementa fallback para `/cgi-bin/luci/admin/ubus`

Validação estrutural local é suportada com:

```bash
terraform -chdir=stacks/openwrt-dns init -backend=false
terraform -chdir=stacks/openwrt-dns validate
```

Quando o OpenWrt real exigir o fork local:

```bash
bash scripts/sync-local-openwrt-provider.sh
OPENWRT_PROVIDER_DEV_OVERRIDE=1 bash scripts/plan-stack.sh openwrt-dns dev
```

Sem credenciais reais e reachability nao ha prova honesta de `plan/apply` completos.

### `ansible` e `pbs`

Ativos apenas como handoff minimo. O comportamento atual e filtrar outputs do `proxmox-base`.

## Layout

```text
inventory/
  dev/
  prod/
  legacy/
    lab/
modules/
  proxmox-ct/
  proxmox-vm/
stacks/
  proxmox-base/
  openwrt-dns/
  ansible/
  pbs/
env/
  dev/
  prod/
  legacy/
    lab/
docs/
legacy/
  root-module/
```

## Inventario Ativo

`inventory/<environment>/` usa:

- `defaults.yaml`
- `nodes.yaml`
- `networks.yaml`
- `ingress.yaml`
- `cts/*.yaml`
- `vms/*.yaml`

No estado atual:

- `inventory/dev/cts/homarr.yaml` define o unico CT ativo provado no fluxo novo
- `inventory/dev/vms/vm-template.yaml` existe, mas esta com `enabled: false`
- o perfil de teste do inventario ativo usa `1 GB RAM`; no CT ativo `homarr` usa ainda `1024 swap` e disco minimo de teste
- `inventory/dev/ingress.yaml` esta vazio
- `inventory/prod/` e apenas um esqueleto valido

## Validacao

Estrutural:

```bash
bash scripts/validate-repo.sh
bash scripts/validate-inventory.sh
terraform -chdir=stacks/proxmox-base init -backend=false
terraform -chdir=stacks/proxmox-base validate
terraform -chdir=stacks/openwrt-dns init -backend=false
terraform -chdir=stacks/openwrt-dns validate
python3 -m unittest -q tests/test_render_local_tfvars.py
```

Plano real de `dev` no CT `dev-terraform-101`:

```bash
STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json \
bash scripts/plan-stack.sh proxmox-base dev
```

## Execucao No CT Terraform

No host `dev-terraform-101`:

- o Terraform corre via `docker compose`
- o compose vive em `/opt/terraform/docker-compose.run.yml`
- `/mnt/data` do host e montado como `/opt/data` no contentor
- `scripts/plan-stack.sh` faz fallback para `docker compose` quando nao existe `terraform` no host

## Segredos E Backends

- segredos reais nao devem ficar no git
- neste workspace, a fonte operacional real fica em `/mnt/data`
- o repo ativo nao tem `backend` Terraform declarado nos stacks atuais
- qualquer referencia a backend remoto na documentacao deve ser lida como objetivo operacional, nao como implementacao atual em codigo

## Docs Principais

- `docs/stack-boundaries.md`
- `docs/inventory-schema.md`
- `docs/migration-runbook.md`
- `docs/state-migration-map-lab.md`
- `docs/local-credentials.md`
- `docs/architecture-report-dev-prod.md`
- `docs/integrations/openwrt-provider.md`
- `docs/integrations/traefik-proxmox-provider.md`
- `docs/integrations/secrets-and-runtime.md`
