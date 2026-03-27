# Terraform Proxmox Platform

Repositorio Terraform para gerir infraestrutura Proxmox a partir de inventario YAML por ambiente.

## O Que O Repo Faz Hoje

- `stacks/proxmox-base` modela e planeia CTs e VMs Proxmox a partir de `inventory/<environment>/`
- `stacks/openwrt-dns` deriva registos DNS e regras agregadas de firewall OpenWrt a partir de `services[]` e `ingress.yaml`
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
- o `apply` ainda nao converge de ponta a ponta no runtime testado; a fase `terraform_data.ct_manual_features` continua a sair com erro apos a criacao do CT

### `openwrt-dns`

Prova real obtida no mesmo CT e com credenciais reais.

Resultado provado:

- o provider oficial `joneshf/openwrt` entra no `plan`
- o `plan` falha ao criar o cliente LuCI RPC
- o host real responde:
  - `/cgi-bin/luci/rpc/auth` -> `404`
  - `/cgi-bin/luci/admin/ubus` -> `200`
- o binario oficial encontrado no workspace contem `/cgi-bin/luci/rpc/auth`
- o stack atual nao expoe qualquer variavel para trocar esse path para `/cgi-bin/luci/admin/ubus`

Conclusao suportada: a falha atual e de compatibilidade do provider com o endpoint real exposto por este OpenWrt, nao de reachability nem de password errada.

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
