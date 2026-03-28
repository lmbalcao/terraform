# Full Reseed CT Validation Design

## Goal

Executar um reset completo do ambiente `dev`, garantir que o repositório local `terraform` passa a ser a única fonte de verdade do código, alinhar o Forgejo com essa revisão, recriar o CT Terraform via `dev-install` e validar em contexto real o fluxo end-to-end de CT, incluindo integrações com OpenWrt, Traefik e montagem derivada de apps quando existir `docker compose`.

## Scope

Incluído:
- consolidar o estado do repositório local `terraform`
- publicar a revisão final no Forgejo
- limpar Proxmox, incluindo CTs, VMs e artefactos de configuração residuais
- limpar vestígios anteriores em OpenWrt e Traefik
- executar `dev-install` para recriar o CT Terraform
- entrar no novo CT Terraform e validar Docker, Terraform e clone do repositório
- testar criação, edição e remoção de CTs em contexto real com 2 CTs temporários
- validar notas Traefik no CT, hostname/regra em OpenWrt e mounts derivados de app quando o inventário os expuser
- corrigir código no repositório local e repetir os testes até obter evidência de sucesso

Excluído:
- preservação do ambiente `dev` atual
- validação funcional de VMs como workload de destino
- alterações arquiteturais não exigidas por falhas reais observadas

## Source Of Truth

A fonte de verdade do código Terraform será o repositório local em `/home/lmbalcao/Documentos/vscode-workspace/repos/terraform`.

O Forgejo em `origin` deve ficar alinhado com a revisão final desse repositório antes da recriação do ambiente. O `dev-install` e qualquer bootstrap posterior devem consumir essa revisão publicada, não uma cópia ad hoc divergente.

## Execution Order

### 1. Consolidar o repositório local

- inspecionar `git status`, `git log` e `origin/main`
- rever alterações pendentes e confirmar que a revisão local contém o estado desejado
- executar validações locais mínimas relevantes
- criar os commits necessários
- fazer `push` para `origin/main`

### 2. Limpeza total do ambiente

- aceder ao Proxmox e remover CTs, VMs e configurações residuais relacionadas com o fluxo anterior
- confirmar que não ficam workloads nem snippets/configs órfãs necessárias ao fluxo antigo
- aceder ao OpenWrt e remover hostnames, DNS e regras de firewall residuais
- aceder ao Traefik e remover vestígios do ambiente anterior, se existirem fora do controlo atual do Terraform

### 3. Rebootstrap do ambiente Terraform

- a partir do `dev-proxmox`, obter o `dev-install` do repositório/scripts indicado pelo utilizador
- executar o `dev-install`
- confirmar que foi criado um novo CT Terraform
- entrar no CT novo e validar:
  - Docker disponível
  - Terraform disponível
  - repositório `terraform` clonado da revisão publicada no Forgejo
  - credenciais e mounts operacionais exigidos pelo fluxo

### 4. Validação CT end-to-end

- usar 2 CTs temporários com dados reais e identificadores reais disponíveis no ambiente
- validar create, edit e destroy
- validar opções suportadas pelo contrato atual do stack
- validar a descrição/nota Traefik gravada no CT quando `services[]` estiver definido
- validar que o `openwrt-dns` cria hostname e regra coerentes com o CT
- validar mounts derivados de app apenas quando o inventário e a app atribuída ao CT produzirem evidência concreta desse comportamento esperado

### 5. Iteração por falha real

- qualquer falha deve ser reproduzida com evidência
- a correção deve ser feita no repositório local `terraform`
- a revisão corrigida deve ser publicada no Forgejo
- o teste real deve ser repetido no ambiente recriado ou no ambiente em execução, conforme o menor caminho que preserve evidência fiável

## Evidence Rules

- distinguir sempre evidência observada de inferência
- não inventar valores de IP, credenciais, nomes, IDs ou providers
- validar contra o código local e contra o comportamento real do ambiente
- quando necessário, consultar documentação oficial online para erros do provider, Terraform, Proxmox, OpenWrt ou Traefik

## Success Criteria

- `terraform` local e Forgejo apontam para a mesma revisão final
- Proxmox limpo antes do bootstrap
- OpenWrt e Traefik sem resíduos relevantes do ambiente anterior
- `dev-install` recria o CT Terraform funcional
- o novo CT Terraform corre os testes reais do stack
- os testes CT provam com sucesso os comportamentos pretendidos ou isolam bloqueios reais com causa comprovada
- nenhuma correção final depende de ajuste manual fora do repositório Terraform
