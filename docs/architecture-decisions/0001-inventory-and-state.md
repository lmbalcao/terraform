# ADR 0001: Inventory, Stacks and State Boundaries

- Status: accepted
- Date: 2026-03-21

## Context

O repositorio legacy mistura provisao Proxmox, configuracao imperativa nos guests e automacao operacional de apps externas no mesmo root module. Isso aumenta o risco de side effects, degrada a capacidade de validar `plan` e torna a migracao de state perigosa.

## Decision

1. O inventario passa para YAML em `inventory/<environment>/`.
2. `vmid` passa a ser explicito e obrigatorio.
3. O runtime e separado por stacks:
   - `proxmox-base`
   - `ansible`
   - `pbs`
4. O core deixa de conter integracoes com `Vault`, `Rundeck`, `Portainer` e `Restic`.
5. O backend de state deve ser remoto e separado por stack e ambiente.
6. Segredos deixam de viver em ficheiros `*.tfvars` versionados; a direcao escolhida e `SOPS + age` para configuracao partilhada e variaveis de ambiente ou CI para credenciais efemeras.

## Consequences

- a identidade dos recursos deixa de depender de `vlan + ultimo_octeto`
- o core fica mais pequeno e previsivel
- a migracao exige planeamento de `state mv` e `import`
- o repositorio ganha uma fronteira clara entre infraestrutura base e automacao consumidora
