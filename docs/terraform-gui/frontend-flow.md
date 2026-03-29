# Terraform GUI Frontend Flow

## Fluxo Principal

1. A GUI pede `/state`.
2. A GUI mostra na mesma página:
   - declarado raw
   - declarado efetivo
   - real Proxmox
   - comparação simples
3. O utilizador abre detalhe ou criação.
4. A edição é feita campo a campo em draft local da API, não no inventário final.
5. A GUI chama `/workloads/validate` sempre que o utilizador quiser validar o draft atual.
6. Quando o utilizador escolhe gravar, a GUI chama `/workloads/save`.
7. Só depois de gravado a GUI chama `/terraform/plan`.
8. `apply` só é permitido quando `/drafts` está vazio; o backend também reforça o bloqueio.

## Como A GUI Obtém Estado Real E Declarado

- Declarado raw: `rows[].raw`
- Declarado efetivo: `rows[].effective`
- Real Proxmox: `rows[].real`
- Diferenças simples: `rows[].comparison`

## Como São Mostradas Diferenças

- A listagem principal mantém os três blocos lado a lado:
  - declarado raw
  - declarado efetivo
  - real
- O resumo de drift vem de `comparison.status` e `comparison.fields`
- Nada é escondido por defeito; a GUI renderiza objetos e listas completos

