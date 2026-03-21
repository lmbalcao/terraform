# Terraform Proxmox Platform

Repositorio Terraform para provisao Proxmox orientada por inventario YAML e stacks separados.

## Estado

O repositorio esta em transicao de um root module plano para a estrutura alvo:

- `inventory/`
- `modules/`
- `stacks/`
- `env/`
- `docs/`

O runtime legacy no root continua presente apenas para suportar a migracao controlada de state.

## Arquitetura Alvo

- `stacks/proxmox-base`: provisao de CTs e VMs
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
  ansible/
  pbs/
env/
  lab/
  staging/
  prod/
docs/
```

## Inventario

O inventario novo vive em `inventory/<environment>/` e usa um ficheiro por workload.

Documentacao principal:

- `docs/inventory-schema.md`
- `docs/stack-boundaries.md`
- `docs/migration-runbook.md`
- `docs/state-migration-map-lab.md`

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

Plan local do novo stack:

```bash
bash scripts/plan-stack.sh proxmox-base lab
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

## Nota Operacional

Este workspace ja inclui um Terraform local em `./.tools/bin/terraform`. O `plan` e o cutover do `lab` podem ser preparados com `bash scripts/plan-stack.sh proxmox-base lab` e `bash scripts/cutover-lab.sh`, mas neste sandbox os subcomandos reais continuam bloqueados por `bwrap: Unknown option --argv0`. Em CI ou num shell local normal, o stack novo deve ser validado com `init`, `validate`, `plan` e migracao de state antes da remocao do legado.
