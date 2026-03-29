# Backend Responsibilities

## Repo `terraform`

- continuar a ser a source of truth única
- carregar e validar inventário real
- aplicar defaults e merges reais para mostrar o estado efetivo
- consultar Proxmox com as credenciais reais do ambiente
- gerir drafts pendentes sem base de dados
- gravar alterações no inventário YAML
- correr `terraform plan`
- correr `terraform apply`
- bloquear `apply` com alterações pendentes não gravadas
- expor output raw e resumo simples
- listar branch atual e branches locais existentes
- permitir apenas seleção de branch existente

## Repo `terraform-gui`

- apresentar informação e formulários
- manter apenas estado de interface
- enviar drafts e ações para o backend
- nunca ser source of truth

## Limitação Explícita

- O backend da GUI não substitui Terraform nem Proxmox.
- É apenas uma bridge fina para expor o que o repo `terraform` já controla.

