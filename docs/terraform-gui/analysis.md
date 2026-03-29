# Terraform GUI Analysis

## O Que Existe Realmente No Repo `terraform`

- Source of truth declarativa: `inventory/<environment>/`.
- Ambientes ativos descobertos no código: `dev` e `prod`.
- Estrutura real do inventário ativo:
  - `defaults.yaml`
  - `nodes.yaml`
  - `networks.yaml`
  - `ingress.yaml`
  - `cts/*.yaml`
  - `vms/*.yaml`
- Um workload por ficheiro. O `name` do documento tem de coincidir com o nome do ficheiro.
- O carregamento real do inventário não usa PyYAML; usa o parser próprio em [`scripts/validate-inventory.py`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.py).
- O contrato estrutural base está em [`schemas/inventory-environment.schema.json`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/schemas/inventory-environment.schema.json), mas a validação real inclui regras adicionais em código Python.
- Os stacks Terraform ativos leem YAML diretamente com `yamldecode(file(...))` em [`stacks/proxmox-base/locals.tf`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/stacks/proxmox-base/locals.tf).

## Onde Vivem CTs E VMs

- CTs: `inventory/<environment>/cts/*.yaml`
- VMs: `inventory/<environment>/vms/*.yaml`
- No estado real atual do código:
  - `dev` tem `ct:wikijs`
  - `dev` tem `vm:rdtclient`
- Há drift entre documentação e código:
  - [`README.md`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/README.md) ainda fala em `homarr`
  - o inventário real ativo hoje tem `wikijs`

## Como Os Campos São Definidos Hoje

- Campos comuns obrigatórios no código:
  - `version`
  - `kind`
  - `enabled`
  - `vmid`
  - `name`
  - `node`
  - `network`
  - `resources`
  - `boot`
  - `storage`
  - `services`
  - `operations`
- CTs exigem adicionalmente `lxc`.
- VMs exigem adicionalmente `qemu`.
- Os defaults reais são fundidos com o workload no stack `proxmox-base`, não no ficheiro YAML gravado.
- A GUI precisa de mostrar dois níveis:
  - `raw`: o que está no ficheiro
  - `effective`: o que o Terraform realmente usa depois do merge com `defaults` e catálogo de `networks`

## Como São Validados

- Validação estrutural e semântica real: [`scripts/validate-inventory.py`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/validate-inventory.py)
- Regras relevantes confirmadas no código:
  - `version` tem de ser `1`
  - `kind` tem de ser `ct` ou `vm`
  - `node` tem de existir em `nodes.yaml`
  - `network.segment` tem de existir em `networks.yaml`
  - `network.mode` tem de ser `static` ou `dhcp`
  - em `static`, `address` e `gateway` são obrigatórios
  - `vmid` tem de ser único entre CTs e VMs
  - `services[]` valida `name`, `port`, `scheme`, `traefik_tag`, `traefik_label`, `uri`
  - `traefik_tag` tem de existir em `ingress.yaml`
  - CTs validam `boot.on_boot`, `boot.start`, `lxc.*`
  - VMs validam `boot.on_boot`, `boot.start_state`, `qemu.*`

## Como `plan` E `apply` São Corridos Hoje

- `plan` real existente: [`scripts/plan-stack.sh`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/plan-stack.sh)
- O script:
  - resolve runner local ou `docker compose`
  - faz `terraform init -backend=false`
  - injeta `environment` e `inventory_root`
  - usa `env/<environment>/common.tfvars` e `env/<environment>/proxmox-base.tfvars` quando existem
  - bloqueia `proxmox-base` se as credenciais forem placeholders
- `apply` não existia como script reutilizável no repo; foi criado nesta tarefa:
  - [`scripts/apply-stack.sh`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/apply-stack.sh)

## Que Dados Já Existem Para Expor Ao Frontend

- Estado declarado raw por workload: vindo diretamente dos YAMLs.
- Estado declarado efetivo: reproduzido a partir da lógica real de merge do stack `proxmox-base`.
- Branch atual e branches locais disponíveis: via `git branch`.
- Resultado raw de `plan` e `apply`: stdout/stderr combinado dos comandos shell.
- Resumo simples de `plan` e `apply`: parseado de linhas padrão do Terraform.
- Estado real do Proxmox:
  - não existia bridge HTTP pronta
  - existia código reutilizável para falar com a API Proxmox em [`scripts/apply-proxmox-ct-features.py`](/home/lmbalcao/Documentos/vscode-workspace/repos/terraform/scripts/apply-proxmox-ct-features.py)
  - nesta tarefa foi criada uma bridge mínima HTTP que usa as mesmas credenciais de `env/<environment>/proxmox-base.tfvars(.json)`

## Schema E Reutilização Confirmados

- Reutilizável hoje:
  - parser/loader/validator do inventário em `scripts/validate-inventory.py`
  - schema JSON em `schemas/inventory-environment.schema.json`
  - lógica real de merge observada em `stacks/proxmox-base/locals.tf`
- Não existia:
  - API HTTP
  - modelo de drafts/edição diferida
  - endpoint para estado real Proxmox
  - endpoint para branches
  - endpoint para validar/gravar workloads
  - endpoint para plan/apply

## O Que Falta Para Suportar A GUI

- Interface HTTP JSON mínima no repo `terraform`
- Modelo simples de drafts sem base de dados
- Escrita segura dos ficheiros `cts/*.yaml` e `vms/*.yaml`
- Bloqueio de `apply` quando existem alterações pendentes não gravadas
- Contrato explícito para o frontend consumir apenas a interface, sem aceder aos ficheiros internos

## Interface Mínima Recomendada No Repo `terraform`

- Processo HTTP local e independente, corrido no CT do `terraform`
- Sem base de dados
- Sem autenticação nesta fase
- Persistência temporária apenas de drafts em `.cache/terraform-gui-api/`
- Endpoints mínimos:
  - ambientes
  - branch atual
  - branches locais
  - seleção de branch existente
  - estado agregado real vs declarado
  - detalhe de workload
  - template mínimo de workload
  - validar draft
  - guardar draft
  - marcar ativo/inativo em draft
  - marcar remoção em draft
  - gravar drafts no inventário
  - correr `plan`
  - correr `apply`

## Incertezas Reais Registadas

- O estado real do Proxmox depende de credenciais não versionadas em `env/<environment>/proxmox-base.tfvars(.json)`. Sem elas, a API devolve o declarado mas não o real.
- A comparação real vs declarado só pode ser exata em campos comparáveis confirmados pela API Proxmox. A bridge devolve também `config` e `status` raw do Proxmox para não esconder informação.
- O repo `terraform` está com alterações locais noutras áreas do stack `proxmox-base`; esta implementação evitou tocar nesses ficheiros.

