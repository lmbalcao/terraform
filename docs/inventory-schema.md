# Inventory Schema

O inventario e a fonte de verdade declarativa da nova arquitetura Terraform.
Cada ambiente vive em `inventory/<environment>/` e separa:

- `defaults.yaml`: defaults por tipo
- `nodes.yaml`: catalogo de nodes Proxmox validos
- `networks.yaml`: segmentos logicos reutilizaveis
- `ingress.yaml`: catalogo de instancias Traefik e respetivos IPs de entrada
- `cts/*.yaml`: um documento por CT
- `vms/*.yaml`: um documento por VM

## Convencoes

- YAML versionado com `version: 1`
- Um workload por ficheiro
- O nome do ficheiro deve coincidir com `name`
- Campos em `snake_case`
- `vmid` explicito e obrigatorio
- `network.segment` referencia um segmento definido em `networks.yaml`
- `network.mode` e sempre explicito: `static` ou `dhcp`
- `services` descreve intencao de exposicao, nao labels raw de reverse proxy
- `operations` e sempre opt-in; nao existem defaults implicitos que disparem efeitos laterais
- quando um servico declara `traefik_tag`, `traefik_label` e `uri`, o hostname tem de ser resolvivel no OpenWrt para o IP da instancia Traefik referenciada

## Estrutura Agregada

```yaml
version: 1
defaults: {}
nodes: {}
networks: {}
ingress: {}
cts: {}
vms: {}
```

## defaults.yaml

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

## nodes.yaml

```yaml
version: 1
nodes:
  2core:
    role: compute
  6core:
    role: compute
```

## networks.yaml

```yaml
version: 1
networks:
  servicos-externos:
    vlan: 60
    bridge: vmbr0
    cidr: 192.168.60.0/24
    gateway: 192.168.60.1
    dns_servers:
      - 192.168.60.1
    dns_domain: lbtec.org
```

## ingress.yaml

```yaml
version: 1
traefik_instances:
  traefik-int:
    address: 192.168.40.50
```

Regras:

- `traefik_instances.<tag>.address` e o IP para o qual o OpenWrt deve resolver os hostnames publicados por essa instancia
- um mesmo `uri` nao pode apontar para duas instancias Traefik diferentes
- `ingress.yaml` e o catalogo de entrada; o workload apenas referencia `traefik_tag`

## Campos Comuns

Todos os workloads usam os seguintes campos:

- `version`
- `kind`
- `enabled`
- `vmid`
- `name`
- `node`
- `notes_title`
- `tags`
- `network`
- `resources`
- `boot`
- `storage`
- `services`
- `operations`

### network

```yaml
network:
  segment: servicos-externos
  mode: static
  address: 192.168.60.11/24
  gateway: 192.168.60.1
  dns_servers:
    - 192.168.60.1
  dns_domain: lbtec.org
  bridge: vmbr0
```

Regras:

- `segment` tem de existir em `networks.yaml`
- `address` e `gateway` sao obrigatorios quando `mode: static`
- `bridge` pode vir do segmento ou do proprio workload

### resources

```yaml
resources:
  cpu_cores: 2
  memory_mb: 2048
```

Para CT:

```yaml
resources:
  cpu_cores: 2
  memory_mb: 2048
  swap_mb: 1024
```

Para VM:

```yaml
resources:
  cpu_cores: 2
  cpu_sockets: 1
  memory_mb: 2048
```

### boot

Para CT:

```yaml
boot:
  on_boot: true
  start: true
```

Para VM:

```yaml
boot:
  on_boot: true
  start_state: running
```

### storage

```yaml
storage:
  rootfs_storage: local
  rootfs_size_gb: 8
```

### services

`services` descreve metadados consumiveis por stacks externos. Um workload pode expor varios endpoints; cada entrada representa uma porta/hostname publicado.

Quando `traefik_tag`, `traefik_label` e `uri` existem, o fluxo faz duas coisas:

- `stacks/proxmox-base` gera automaticamente notas Proxmox no formato esperado pela instancia Traefik referenciada
- `stacks/openwrt-dns` garante no OpenWrt que o `uri` resolve para o IP definido em `ingress.yaml` para esse `traefik_tag`

```yaml
services:
  - name: homarr
    port: 7575
    scheme: http
    traefik_tag: traefik-int
    traefik_label: homarr
    uri: homarr.lbtec.org
    proxy:
      enabled: true
      host: homarr.lbtec.org
      entrypoint: websecure
      tls: true
  - name: homarr-api
    port: 8080
    scheme: http
    traefik_tag: traefik-int
    traefik_label: homarr-api
    uri: homarr-api.lbtec.org
```

Regras:

- `traefik_tag`, `traefik_label` e `uri` sao obrigatorios em conjunto
- `traefik_tag` tem de existir em `ingress.yaml`
- um mesmo `uri` nao pode ser usado por tags Traefik diferentes

### operations

```yaml
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

Exemplo com notas Traefik geradas:

```yaml
version: 1
kind: ct
enabled: true
vmid: 6020
name: pbs
hostname: pbs
notes_title: Proxmox Backup Server
node: 2core
tags:
  - 60-servicos-externos
network:
  segment: servicos-externos
  mode: static
  address: 192.168.60.20/24
  gateway: 192.168.60.1
resources:
  cpu_cores: 2
  memory_mb: 4096
  swap_mb: 1024
boot:
  on_boot: true
  start: true
storage:
  rootfs_storage: local
  rootfs_size_gb: 8
lxc:
  template: local:vztmpl/debian-13-standard_amd64.tar.zst
  unprivileged: true
  features:
    nesting: true
  mounts: []
services:
  - name: pbs
    scheme: https
    port: 8007
    traefik_tag: traefik-int
    traefik_label: pbs
    uri: pbs.lbtec.org
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

Com este `ingress.yaml`:

```yaml
version: 1
traefik_instances:
  traefik-int:
    address: 192.168.40.50
```

Notas Proxmox geradas para esse CT:

```text
Proxmox Backup Server

traefik-int.enable=true

traefik-int.http.routers.pbs.rule=Host(`pbs.lbtec.org`)

traefik-int.http.routers.pbs.entrypoints=websecure

traefik-int.http.routers.pbs.middlewares=compression@file

traefik-int.http.routers.pbs.tls=true

traefik-int.http.routers.pbs.tls.certresolver=le

traefik-int.http.services.pbs.loadbalancer.server.port=8007
```

Entrada DNS que o `openwrt-dns` deve garantir:

```text
pbs.lbtec.org -> 192.168.40.50
```

`operations` nao substitui Terraform state nem serve para disparar `remote-exec` arbitrario.

## Campos Especificos de CT

```yaml
lxc:
  template: local:vztmpl/debian-13-standard_amd64.tar.zst
  unprivileged: true
  features:
    nesting: true
  features_manual:
    keyctl: false
    fuse: false
    mount: ""
    create: false
  mounts:
    - slot: mp0
      host_path: /srv/data
      guest_path: /mnt/data
      backup: false
      read_only: false
```

Regras adicionais para CTs:

- `lxc.features.nesting` continua a ser gerido diretamente pelo recurso Terraform
- `lxc.features_manual.keyctl`, `fuse`, `mount` e `create` sao reconciliadas apos a criacao do CT
- `features_manual` existe para manter compatibilidade com templates e comportamento legacy sem alterar o tratamento direto de `nesting`

## Campos Especificos de VM

```yaml
qemu:
  sockets: 1
  agent_enabled: false
  source:
    clone: debian-12-template
  disks: []
```

## Exemplo Completo de CT

```yaml
version: 1
kind: ct
enabled: true
vmid: 6011
name: homarr
hostname: homarr
node: 2core
tags:
  - 60-servicos-externos
network:
  segment: servicos-externos
  mode: static
  address: 192.168.60.11/24
  gateway: 192.168.60.1
resources:
  cpu_cores: 2
  memory_mb: 2048
  swap_mb: 1024
boot:
  on_boot: true
  start: true
storage:
  rootfs_storage: local
  rootfs_size_gb: 8
lxc:
  unprivileged: true
  features:
    nesting: true
  features_manual:
    keyctl: false
    fuse: false
    mount: ""
    create: false
  mounts: []
services: []
operations:
  ansible_enabled: false
  backup_policy: null
  bootstrap_profile: null
```

## Exemplo Completo de VM

```yaml
version: 1
kind: vm
enabled: false
vmid: 1780
name: vm-template
node: 6core
tags: []
network:
  segment: vlan-17
  mode: static
  address: 192.168.17.80/24
  gateway: 192.168.17.1
resources:
  cpu_cores: 2
  cpu_sockets: 1
  memory_mb: 2048
boot:
  on_boot: true
  start_state: running
storage:
  rootfs_storage: local
  rootfs_size_gb: 20
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

## Validacoes Minimas

- unicidade de `vmid` entre CTs e VMs
- unicidade de `name` dentro de cada tipo
- ficheiro `<name>.yaml` coerente com `name`
- `node` valido
- `network.segment` valido
- `address` e `gateway` obrigatorios em `static`
- `kind` coerente com a diretoria `cts` ou `vms`
- `traefik_tag`, `traefik_label` e `uri` coerentes entre si
- `traefik_tag` existente em `ingress.yaml`
- `uri` nao conflituoso entre instancias Traefik
- campos desconhecidos devem ser revistos antes de entrarem no schema operativo
