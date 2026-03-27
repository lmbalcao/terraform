# Dev And Prod Reality Alignment Design

**Date:** 2026-03-27

## Goal

Alinhar o repositório Terraform com uma arquitetura final simples e comprovável baseada apenas em `dev` e `prod`, corrigindo inventário, ambientes, stacks, scripts e documentação para refletirem a realidade operacional e removendo estados intermédios, claims não provadas e drift conhecido.

## Scope

Incluído:

- migrar o conceito operacional de `lab` para `dev`
- remover `staging` do fluxo ativo
- manter apenas `dev` e `prod` como ambientes suportados
- manter `proxmox-base` e `openwrt-dns` como stacks operacionais
- manter `ansible` e `pbs` como stacks mínimos de handoff
- corrigir inventário, docs e scripts para refletirem a realidade atual
- exigir comprovação com dados reais antes de declarar features ou integrações como funcionais
- produzir relatório final de arquitetura real após as correções

Excluído:

- introduzir novas features fora do que o repo já tenta fazer
- transformar `ansible` e `pbs` em automação completa
- manter caminhos paralelos `lab`/`dev` após o refactor
- manter documentação descritiva de features legacy como se fossem parte do fluxo ativo

## Current Problems Confirmed

### 1. Ambientes incoerentes

- O layout ativo declara `lab`, `staging` e `prod`, mas só `lab` tem inventário funcional.
- `staging` e `prod` existem como placeholders e criam a impressão falsa de ambientes utilizáveis.
- O objetivo operacional pedido é apenas `dev` e `prod`.

### 2. Drift entre inventário, state e documentação

- O stack `openwrt-dns` tem state local com registos e reconciliação firewall que não correspondem ao inventário `lab` atual.
- A documentação de migração `lab` contradiz o inventário novo em node, addressing e segmentação.
- O stack `proxmox-base` tem configuração válida, mas o state local novo não prova aplicação real de CTs/VMs.

### 3. Fronteiras do repo pouco nítidas

- `ansible` e `pbs` aparecem como stacks ativos, mas hoje só expõem filtros/outputs.
- A existência de providers, scripts auxiliares e state local pode sugerir capacidades maiores do que as comprovadas.
- O legado continua a contaminar a leitura da arquitetura real.

### 4. Contrato operacional incompleto

- `mounts` LXC existem no schema/inventário, mas o stack novo não os suporta como capacidade funcional completa.
- A reconciliação pós-criação de CT depende de script externo e precisa de ser descrita como parte explícita do runtime real.
- A comprovação atual está misturada entre `validate`, states locais antigos e documentação parcialmente desatualizada.

## Desired End State

### Ambientes

- `env/dev` e `inventory/dev` substituem `lab` como ambiente real de desenvolvimento.
- `env/prod` e `inventory/prod` existem como ambiente suportado.
- `env/staging` e `inventory/staging` deixam de fazer parte da arquitetura ativa.
- Nenhuma doc principal deve continuar a tratar `lab` ou `staging` como ambiente operacional.

### Stacks

- `stacks/proxmox-base` continua como stack central de criação/configuração base de CTs e VMs.
- `stacks/openwrt-dns` continua como stack de DNS/OpenWrt e firewall derivado.
- `stacks/ansible` e `stacks/pbs` ficam explicitamente marcados como stacks mínimos de handoff.
- O legado fica identificado apenas como referência histórica, sem ambiguidade operacional.

### Evidência e comprovação

- Só se pode afirmar que uma capacidade está ativa quando houver evidência por código e por execução real.
- `validate` sozinho não conta como prova operacional.
- `plan` com credenciais reais conta como prova de integração até ao nível do provider.
- `apply` ou state real consistente conta como prova de materialização.
- Onde não houver credenciais reais ou acesso real, o estado deve ficar marcado como não comprovado.

## Recommended Approach

### Approach A: Full reality-first alignment in one pass

Executar a migração estrutural para `dev` e `prod`, corrigir inventário/docs/scripts/states locais, testar com dados reais e reescrever a documentação final à volta da evidência obtida.

Vantagens:

- evita que o repo continue a carregar ambientes e claims falsamente ativos
- reduz retrabalho de documentação
- produz uma arquitetura final coerente e mais fácil de explicar

Riscos:

- depende de acesso real a Proxmox/OpenWrt e segredos corretos
- pode revelar contradições adicionais durante os testes

### Approach B: Minimal doc fix first

Corrigir só documentação e nomenclatura de ambientes, deixando estados e inventário para depois.

Vantagens:

- mais rápido

Desvantagens:

- não cumpre o requisito de comprovação real
- perpetua drift técnico escondido por texto

### Recommendation

Seguir a Approach A.

## Design Decisions

### 1. Ambiente final: `dev` + `prod`

- `dev` será o sucessor direto do ambiente hoje materialmente presente em `lab`, mas não por simples rename cego.
- A migração para `dev` deve incluir correção dos dados contraditórios de inventário, documentação e state local.
- `prod` deve ficar completo no repo, mas só será descrito como comprovado se houver execução real com dados reais.

### 2. Modelo de estados de evidência

Cada feature/capacidade/documentação final deve usar quatro níveis distintos:

- `definido no repo`
- `validado localmente`
- `planeado com dados reais`
- `aplicado/comprovado`

Isto evita voltar a misturar “existe no código” com “funciona em produção”.

### 3. `ansible` e `pbs` mantêm-se mínimos

- Não serão removidos.
- Não serão descritos como stacks de automação completa.
- Serão tratados como contratos mínimos de export/handoff derivados do `proxmox-base`.

### 4. `mounts` LXC têm de deixar de estar num estado ambíguo

Uma destas condições tem de ficar verdadeira no fim:

- ou o stack novo suporta `mounts` de forma explícita e testada
- ou `mounts` deixam de fazer parte do contrato do inventário ativo e a documentação passa a dizê-lo sem ambiguidade

A decisão final depende do que for possível comprovar com dados reais durante a execução.

### 5. OpenWrt DNS e firewall têm de refletir o inventário atual

- O inventário ativo, o `plan` e o state local não podem continuar a apontar para realidades diferentes.
- O DNS derivado e as regras de firewall geridas têm de ser recalculados a partir do inventário final `dev`/`prod`.
- Se o state atual provar recursos antigos que já não pertencem ao inventário final, isso deve ser tratado como drift a corrigir e não como funcionalidade ativa válida.

## Expected File Areas

Ficheiros/pastas candidatos a alteração:

- `README.md`
- `docs/*.md`
- `docs/architecture-decisions/*.md` se necessário para refletir a arquitetura final
- `docs/superpowers/specs/*`
- `env/dev/*`
- `env/prod/*`
- `inventory/dev/*`
- `inventory/prod/*`
- remoção ou migração de `env/lab`, `inventory/lab`, `env/staging`, `inventory/staging`
- `stacks/proxmox-base/*`
- `stacks/openwrt-dns/*`
- `stacks/ansible/*`
- `stacks/pbs/*`
- `scripts/plan-stack.sh`
- `scripts/validate-inventory.py`
- `scripts/validate-inventory.sh`
- scripts auxiliares de prova/operação

## Verification Requirements

Antes de qualquer claim final, executar e registar evidência fresca para:

- baseline repo
- validação do inventário
- `terraform init` + `validate` dos stacks ativos
- `plan` real de `proxmox-base` com credenciais reais
- `plan` real de `openwrt-dns` com credenciais reais
- verificações adicionais necessárias para provar ou refutar `mounts`, notes Traefik, CT manual features, DNS OpenWrt e firewall OpenWrt

Se `prod` não tiver dados reais ou credenciais reais disponíveis, isso deve ficar explicitamente registado no relatório final como “estruturalmente preparado, não comprovado operacionalmente”.

## Deliverables

No fim do trabalho deve existir:

1. Repositório alinhado com arquitetura final `dev + prod`
2. Inventário coerente com a realidade validada
3. Documentação reescrita para refletir apenas o fluxo real
4. Classificação revista das features/providers/addons baseada em evidência real
5. Relatório final de arquitetura real, simples e prático, apoiado em ficheiros e resultados de execução

## Open Constraints

- A comprovação operacional depende de credenciais reais e acesso real aos endpoints necessários.
- Estados/versionamentos locais existentes não serão tratados como verdade absoluta sem cruzamento com inventário e execução real.
- O worktree já contém alterações locais pré-existentes; a execução deve evitar sobrescrevê-las sem revisão.
