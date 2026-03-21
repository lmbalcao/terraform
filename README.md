# Terraform Proxmox Platform

Repositorio Terraform para provisao Proxmox orientada por inventario YAML e stacks separados.

## Estado

O repositorio esta em transicao concluida para a estrutura alvo:

- `inventory/`
- `modules/`
- `stacks/`
- `env/`
- `docs/`
- `legacy/root-module/`

O root module antigo foi arquivado em `legacy/root-module/` apenas para referencia historica e apoio a migracoes. A versao ativa do repositorio vive fora desse diretorio.

## Arquitetura Ativa

- `stacks/proxmox-base`: provisao de CTs e VMs
- `stacks/openwrt-dns`: hostnames no OpenWrt para servicos expostos via Traefik
- `stacks/ansible`: handoff para configuracao pos-provisionamento
- `stacks/pbs`: handoff para politicas de backup

Componentes removidos do core:

- Vault
- Rundeck
- Portainer
- Restic
- bootstrap Docker global

## Layout

```text
inventory/
  lab/
  staging/
  prod/
modules/
  proxmox-ct/
  proxmox-vm/
stacks/
  proxmox-base/
  openwrt-dns/
  ansible/
  pbs/
env/
  lab/
  staging/
  prod/
docs/
legacy/
  root-module/
```

## Inventario

O inventario novo vive em `inventory/<environment>/` e usa um ficheiro por workload.

Documentacao principal:

- `docs/inventory-schema.md`
- `docs/stack-boundaries.md`
- `docs/migration-runbook.md`
- `docs/state-migration-map-lab.md`

`inventory/<environment>/ingress.yaml` define as instancias Traefik conhecidas e os seus IPs de entrada. Cada `services[]` exposto pode referenciar um `traefik_tag`; quando isso acontece, o hostname e publicado no OpenWrt pelo stack `openwrt-dns`.

## Validacao

Baseline do repositorio:

```bash
bash scripts/validate-repo.sh
```

Validacao do inventario:

```bash
bash scripts/validate-inventory.sh
bash scripts/validate-inventory.sh lab
```

Validacao local dos stacks ativos:

```bash
bash scripts/plan-stack.sh proxmox-base lab
terraform -chdir=stacks/openwrt-dns init -backend=false
terraform -chdir=stacks/openwrt-dns validate
bash scripts/cutover-lab.sh
```

O script tenta resolver o Terraform nesta ordem:

1. `TERRAFORM_BIN`
2. `terraform` no `PATH`
3. `./.tools/bin/terraform`
4. `./.tools/terraform-1.5.7/terraform`

## Requisitos

- Terraform CLI para `init`, `validate`, `plan` e `apply`
- Python 3 para scripts auxiliares
- o validador de inventario atual nao depende de `PyYAML` nem `jsonschema`

## Segredos e State

- nao versionar segredos em claro
- usar backend remoto por stack e ambiente
- usar `SOPS + age` para configuracao partilhada
- usar variaveis de ambiente ou CI para credenciais efemeras

Exemplo de variaveis do stack `openwrt-dns`:

- `openwrt_hostname`
- `openwrt_port`
- `openwrt_scheme`
- `openwrt_username`
- `openwrt_password`

## Nota Operacional

Este workspace ja inclui um Terraform local em `./.tools/bin/terraform`. Em CI ou num shell local normal, os stacks ativos devem ser validados com `init`, `validate`, `plan` e migracao de state antes de qualquer alteracao operacional.
