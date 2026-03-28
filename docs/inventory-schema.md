# Inventory Schema

O inventario ativo vive em `inventory/<environment>/` e e a fonte declarativa do repo.

## Estrutura

Cada ambiente usa:

- `defaults.yaml`
- `nodes.yaml`
- `networks.yaml`
- `ingress.yaml`
- `cts/*.yaml`
- `vms/*.yaml`

## Regras Gerais

- todos os documentos usam `version: 1`
- um workload por ficheiro
- o nome do ficheiro deve coincidir com `name`
- `kind` tem de corresponder a `ct` ou `vm`
- `vmid` e obrigatorio
- `node` tem de existir em `nodes.yaml`
- `network.segment` tem de existir em `networks.yaml`
- `network.mode` tem de ser `dhcp` ou `static`
- em `static`, `address` e `gateway` sao obrigatorios
- `services[]` e declarativo; nao substitui labels raw em Terraform

## Exemplo De `nodes.yaml`

Estado real em `dev`:

```yaml
version: 1
nodes:
  dev-proxmox:
    role: compute
```

## Exemplo De `networks.yaml`

Estado real em `dev`:

```yaml
version: 1
networks:
  vlan-99:
    bridge: vmbr0
    cidr: 192.168.99.0/24
    gateway: 192.168.99.1
    dns_servers: []
    dns_domain: lbtec.org
  servicos-externos:
    bridge: vmbr0
    cidr: 192.168.99.0/24
    gateway: 192.168.99.1
    dns_servers:
      - 192.168.99.1
    dns_domain: lbtec.org
  vlan-17:
    bridge: vmbr0
    cidr: 192.168.99.0/24
    gateway: 192.168.99.1
    dns_servers:
      - 192.168.99.1
    dns_domain: lbtec.org
```

## Exemplo De `ingress.yaml`

Estado real em `dev`:

```yaml
version: 1
traefik_instances: {}
```

Se forem usados serviços Traefik, cada `traefik_tag` tem de existir aqui. Cada `traefik_tag` corresponde operacionalmente a uma instância do provider plugin no runtime Traefik.

## `defaults.yaml`

Exemplo coerente com o contrato atual:

```yaml
version: 1
defaults:
  common:
    tags: []
    services: []
    operations:
      ansible_enabled: false
      backup_policy: null
      bootstrap_profile: null
  ct:
    enabled: true
    boot:
      on_boot: true
      start: true
    resources:
      swap_mb: 1024
    lxc:
      unprivileged: true
      features:
        nesting: true
      features_manual: {}
      mounts: []
  vm:
    enabled: true
    boot:
      on_boot: true
      start_state: running
    qemu:
      sockets: 1
      agent_enabled: false
      source: {}
      disks: []
```

## Campos Comuns

Workloads usam normalmente:

- `version`
- `kind`
- `enabled`
- `vmid`
- `name`
- `hostname` para CT
- `node`
- `tags`
- `network`
- `resources`
- `boot`
- `storage`
- `services`
- `operations`

### `network`

Exemplo `dhcp`:

```yaml
network:
  segment: vlan-99
  mode: dhcp
```

Exemplo `static`:

```yaml
network:
  segment: vlan-17
  mode: static
  address: 192.168.99.80/24
  gateway: 192.168.99.1
```

### `operations`

```yaml
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

Hoje este bloco so alimenta handoff minimo para os stacks `ansible` e `pbs`.

## Campos Especificos De CT

```yaml
lxc:
  template: local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
  unprivileged: true
  features:
    nesting: true
  features_manual:
    keyctl: false
    fuse: false
  mounts: []
```

Regras reais:

- `lxc.template` deve existir no inventario ou vir de fallback valido
- `lxc.features.nesting` entra no contrato do CT
- `features_manual.keyctl` e `features_manual.fuse` sao reconciliados apos criacao
- `features_manual.mount` nao e suportado
- `lxc.mounts` tem de ser lista vazia no contrato atual
- no contexto de teste atual, o inventario ativo nao declara `vlan`; o stack passa `null` para `network_tag`

## Campos Especificos De VM

```yaml
qemu:
  sockets: 1
  agent_enabled: false
  source: {}
  disks: []
```

## Exemplo Real De CT Em `dev`

`inventory/dev/cts/homarr.yaml`:

```yaml
version: 1
kind: ct
enabled: true
vmid: 6011
name: homarr
hostname: homarr
node: dev-proxmox
tags:
  - 60-servicos-externos
network:
  segment: vlan-99
  mode: dhcp
resources:
  cpu_cores: 1
  memory_mb: 1024
  swap_mb: 1024
boot:
  on_boot: true
  start: true
storage:
  rootfs_storage: local-lvm
  rootfs_size_gb: 8
lxc:
  template: local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
  unprivileged: true
  features:
    nesting: true
  mounts: []
services: []
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

## Exemplo Real De VM Em `dev`

`inventory/dev/vms/vm-template.yaml`:

```yaml
version: 1
kind: vm
enabled: false
vmid: 1780
name: vm-template
node: dev-proxmox
tags: []
network:
  segment: vlan-17
  mode: static
  address: 192.168.99.80/24
  gateway: 192.168.99.1
resources:
  cpu_cores: 2
  cpu_sockets: 1
  memory_mb: 1024
boot:
  on_boot: true
  start_state: running
storage:
  rootfs_storage: local
  rootfs_size_gb: 8
qemu:
  sockets: 1
  agent_enabled: false
  source: {}
  disks: []
services: []
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

## Services E Traefik

Quando um serviço tiver simultaneamente:

- `traefik_tag`
- `traefik_label`
- `uri`
- `port`

entao:

- `proxmox-base` gera notes Proxmox para esse workload
- `openwrt-dns` tenta publicar o hostname no OpenWrt

No estado atual de `dev`, `homarr` tem `services: []` e `ingress.yaml` esta vazio. Portanto nao existe prova atual de notes Traefik ou DNS OpenWrt ativos para esse workload.

No perfil de teste atual:

- CTs e VMs no inventario usam `1 GB RAM`
- o CT ativo usa `1024 swap`
- os discos foram reduzidos para o minimo pratico de testes no contexto atual
- o stack de VM nao modela `swap`; por isso essa parte nao fica declarada nem aplicada para VMs

## Validacoes Minimas

- unicidade de `vmid` entre CTs e VMs
- unicidade de `name` por tipo
- `node` valido
- `network.segment` valido
- completude de redes staticas
- coerencia de `traefik_tag` com `ingress.yaml`
- rejeicao de `features_manual.mount` preenchido
- rejeicao de `lxc.mounts` nao vazio
