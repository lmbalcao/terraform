# Terraform GUI Architecture

- `terraform`:
  - source of truth única
  - guarda inventário YAML
  - valida inventário
  - corre `terraform plan` e `terraform apply`
  - consulta estado real do Proxmox
  - expõe API HTTP JSON mínima para a GUI
- `terraform-gui`:
  - frontend puro
  - não tem lógica de negócio Terraform
  - não toca diretamente nos ficheiros do repo `terraform`
  - consome apenas a API HTTP do repo `terraform`

## Onde Corre Cada Coisa

- Backend mínimo: no CT do `terraform`
- Frontend: no CT independente do `terraform-gui`
- Terraform CLI e acesso ao Proxmox: apenas do lado `terraform`

## Contrato Entre Repos

- `terraform-gui` chama endpoints JSON para:
  - obter estado declarado
  - obter estado real Proxmox
  - validar drafts
  - gravar drafts
  - correr `plan`
  - correr `apply`
  - listar e selecionar branch existente
- `terraform-gui` nunca:
  - grava YAML diretamente
  - corre `terraform`
  - lê segredos
  - consulta Proxmox diretamente

## Modelo De Crescimento

- Mínimo hoje:
  - HTTP JSON
  - ficheiros YAML
  - drafts em `.cache/terraform-gui-api/`
- Preparado para crescer:
  - backend isolado por módulos Python
  - frontend modular por ficheiros ES
  - contrato explícito em `api-contract.md`

