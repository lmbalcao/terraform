# Migration Runbook

Este runbook define como migrar do root module legacy para a nova arquitetura sem recriacao acidental de recursos.

## 1. Preconditions

- Inventario novo preenchido para o ambiente piloto
- `stacks/proxmox-base` implementado
- backend remoto e locking decididos
- politica de segredos decidida
- `terraform` ou `tofu` disponivel no operador ou CI
- snapshot do state atual guardado fora do repositorio
- `env/lab/common.tfvars` e `env/lab/proxmox-base.tfvars` preenchidos fora do git

## 2. Freeze

1. Congelar mudanças funcionais no root legacy.
2. Capturar:
   - `terraform state pull`
   - `terraform providers`
   - `terraform plan`
   - lockfile atual
3. Confirmar os identificadores operacionais de cada workload:
   - `vmid`
   - `name`
   - `node`
   - `ip`
   - `storage`
   - `tags`

## 3. Paridade de Inventario

1. Converter os workloads de `00-inventory.tf` para `inventory/<env>/`.
2. Preservar os valores atuais, mesmo quando o desenho novo permita melhorias.
3. Nao introduzir novos `services`, `backup_policy` ou `bootstrap_profile` sem fonte real.

## 4. Validacao Estrutural

1. Executar `bash scripts/validate-repo.sh`
2. Executar `bash scripts/validate-inventory.sh`
3. Executar validacao Terraform no novo stack:
   - `terraform -chdir=stacks/proxmox-base init -backend=false`
   - `terraform -chdir=stacks/proxmox-base validate`

## 5. Plano Comparativo

1. Gerar `plan` do root legacy.
2. Gerar `plan` do `stacks/proxmox-base`.
3. Comparar:
   - `vmid`
   - `target_node`
   - tags
   - rootfs
   - network segment e VLAN
   - argumentos sensiveis do provider Proxmox
4. Bloquear migracao se o novo stack quiser destruir ou recriar recursos existentes sem razao documentada.

## 6. Migracao de State

Usar primeiro `state mv` quando a origem e o destino representam o mesmo recurso logico.

Exemplos de mapeamento esperado:

- `proxmox_lxc.cts["homarr"]` -> `module.cts["homarr"].proxmox_lxc.this`
- `proxmox_vm_qemu.vms["vm_template"]` -> `module.vms["vm-template"].proxmox_vm_qemu.this`

Passos:

1. Inicializar o novo stack com backend configurado.
2. Fazer backup do state antes de qualquer `state mv`.
3. Migrar um recurso de cada vez.
4. Executar `plan` apos cada lote pequeno.
5. Corrigir o inventario antes de continuar se existir drift.
6. So fazer `state push` depois de rever o state novo e o `plan` resultante.

Script de apoio:

```bash
bash scripts/cutover-lab.sh
bash scripts/cutover-lab.sh --execute
```

## 7. Ambiente Piloto

Ordem recomendada:

1. `lab`
2. `staging`
3. `prod`

Nunca migrar mais de um ambiente ao mesmo tempo.

## 8. Remocao de Legado

So depois de `plan` limpo no novo stack:

- remover `modules.tf`
- remover `templates/`
- remover `10-restic_deploy.tf`
- remover `15-docker_setup.tf`
- remover `20-docker_deploy.tf`
- remover `30-portainer_endpoints.tf`
- remover `50-rundeck_deploy.tf`
- remover `10-validade_backup.tf`

## 9. Rollback

Se o novo stack apresentar diferencas inesperadas:

1. parar a migracao
2. nao executar `apply`
3. restaurar o state backup se necessario
4. regressar ao root legacy
5. documentar a causa antes de nova tentativa

## 10. Blockers Conhecidos Neste Workspace

Neste workspace atual, o binario `terraform` ja foi instalado localmente em `./.tools/bin/terraform`, mas o sandbox ainda bloqueia `init`, `validate` e `plan` com `bwrap: Unknown option --argv0`. Por isso:

- a validacao real de `init`, `validate` e `plan` nao foi concluida aqui
- a migracao de state nao foi realizada aqui
- os artefactos novos foram preparados para a fase seguinte, mas precisam de shell local normal ou CI antes de cutover
