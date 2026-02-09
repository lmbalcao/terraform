# Terraform + Proxmox + Docker + Portainer + Rundeck  
## Arquitetura, Fluxo e Estado do Projeto

---

## Visão geral

Este projeto usa **Terraform como orquestrador de infraestrutura** sobre **Proxmox**, e **Rundeck** como motor de **configuração contínua e execução operacional**.

O objetivo é que **editar um único ficheiro (`inventory.tf`)** seja suficiente para:
- criar / destruir contentores (CT) e VMs
- preparar o sistema base
- instalar Docker
- integrar Portainer
- aplicar stacks (ex.: Forgejo)
- executar jobs Rundeck conforme necessário

---

## Fluxo global

### Princípio fundamental
- **Terraform** decide *o quê* existe (estado desejado)
- **Rundeck** decide *como* os sistemas são configurados e mantidos

---

## Fonte da verdade

### 1) inventory.tf

Ficheiro **central e único** que defines no dia-a-dia.

Define, por CT:

- `enabled = true | false`
  - `true` → criar/manter
    - `false` → destruir
    - recursos (CPU, RAM, disco)
    - rede (VLAN, IP)
    - flags funcionais:
      - docker
        - backup
          - portainer
            - rundeck
            - tags (já implementadas)
            - extensões futuras:
              - HA
                - afinidades
                  - políticas

                  👉 **Editar este ficheiro e aplicar é o workflow normal.**

                  ---

                  ### 2) credentials.auto.tfvars

                  Contém **variáveis globais do sistema**:

                  - credenciais Proxmox
                  - utilizador SSH e chave default
                  - paths de backup
                  - tokens Portainer / Rundeck / Forgejo
                  - repositórios (ex.: Restic)

                  Características:
                  - não contém lógica
                  - não contém inventário
                  - pode ser substituído por `TF_VAR_*` em CI
                  - não deve ser versionado

                  ---

                  ### 3) Ficheiros Terraform (`*.tf`)

                  - Leem `inventory.tf` + `credentials.auto.tfvars`
                  - Criam/destruem recursos conforme `enabled`
                  - Aplicam opções comuns e específicas
                  - Executam scripts via `null_resource` quando necessário

                  ---

                  ## Estrutura Terraform (00 → 99)

                  