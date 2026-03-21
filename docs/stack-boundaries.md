# Stack Boundaries

## `stacks/proxmox-base`

Responsabilidades:

- ler inventario YAML
- validar schema, referencias de node e rede, e unicidade de `vmid`
- criar CTs e VMs no Proxmox
- publicar outputs estaveis consumiveis por stacks externos

Nao faz:

- `remote-exec`
- `local-exec`
- bootstrap Docker
- deploy de apps
- triggers Rundeck
- restores Restic
- configuracao pos-provisionamento detalhada

## `stacks/ansible`

Responsabilidades:

- consumir targets e metadados produzidos pelo core
- transformar isso em inventario ou entradas para configuracao
- representar apenas a integracao, nao o estado completo dos workloads

Nao faz:

- criar CTs ou VMs
- substituir o inventario principal
- esconder side effects operacionais dentro do stack base

## `stacks/pbs`

Responsabilidades:

- consumir workloads e politicas de backup declaradas
- modelar inclusao de CTs e VMs em politicas de backup
- manter o tema backup no dominio da infraestrutura

Nao faz:

- restore imperativo durante `apply`
- scripts ad hoc por workload
- dependencia em naming legacy ou tags opacas sem schema

## Contratos Entre Stacks

`proxmox-base` deve expor pelo menos:

- `created_cts`
- `created_vms`
- `ansible_targets`
- `pbs_targets`
- `inventory_summary`

`ansible` e `pbs` devem consumir esses contratos sem depender do layout interno do stack base.
