# Migration Runbook

Este runbook serve para migrar state do root module legacy para a arquitetura por stacks.

## Estado Atual

- o root module antigo continua arquivado em `legacy/root-module/`
- o ambiente ativo novo e `dev`
- `prod` esta apenas preparado estruturalmente
- nao existe bloco `backend` implementado nos stacks ativos

## Preconditions

- inventario `dev` validado
- `stacks/proxmox-base` validado
- snapshot do state legacy guardado fora do repo
- credenciais reais disponiveis fora do git
- plano novo revisto antes de qualquer `state mv`

## Ordem Recomendada

1. validar repo e inventario
2. correr `plan` real do stack novo
3. fazer backup do state legacy
4. fazer `state mv` recurso a recurso
5. repetir `plan`
6. so depois considerar `apply`

## Comandos Minimos

```bash
bash scripts/validate-repo.sh
bash scripts/validate-inventory.sh
STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json \
bash scripts/plan-stack.sh proxmox-base dev
```

Helper de apoio para state move:

```bash
bash scripts/cutover-lab.sh
bash scripts/cutover-lab.sh --execute
```

O nome do script e legado, mas o fluxo alvo do helper e `dev`.

## Mapeamentos Relevantes

- `proxmox_lxc.cts["homarr"]` -> `module.cts["homarr"].proxmox_lxc.this`
- `proxmox_vm_qemu.vms["vm_template"]` -> `module.vms["vm-template"].proxmox_vm_qemu.this`

## Verificacao Real Ja Feita

Em `2026-03-27`, o stack novo `stacks/proxmox-base` foi provado em `dev-terraform-101` com credenciais reais:

- `plan` com exit code `0`
- sem warnings
- `target_node = "dev-proxmox"`
- `ostemplate = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"`

Isto prova que o stack novo consegue planear o CT `homarr` contra o provider real.

## Cuidados

- nao usar docs antigas de `lab` como verdade operacional atual
- nao assumir que `vm-template` esta ativo; o inventario atual tem `enabled: false`
- nao assumir Traefik/OpenWrt ativos para `homarr`; o inventario atual nao prova isso
- nao assumir backend remoto ja configurado; essa parte continua fora do codigo ativo
