# Stack Boundaries

## `stacks/proxmox-base`

Responsabilidades reais:

- ler `defaults.yaml`, `nodes.yaml`, `networks.yaml`, `cts/*.yaml` e `vms/*.yaml`
- validar `version`, `vmid`, `node`, `segment` e redes staticas
- criar CTs com `module.cts -> proxmox_lxc`
- criar VMs com `module.vms -> proxmox_vm_qemu`
- expor outputs consumiveis por stacks externos
- gerar notes/description Proxmox para CTs e VMs quando um workload tem `services[]` com `traefik_tag`, `traefik_label`, `uri` e `port`
- reconciliar pos-criacao de CT para:
  - `nesting`
  - `keyctl`
  - `fuse`
  - `description`
  - `nameserver`
  - `searchdomain`

Limites reais:

- `mounts` nao estao suportados no contrato ativo
- `features_manual.mount` e rejeitado pelo validador
- nao faz bootstrap aplicacional
- nao faz DNS OpenWrt
- nao faz configuracao Ansible
- nao faz politicas PBS

## `stacks/openwrt-dns`

Responsabilidades reais:

- ler workloads e `ingress.yaml`
- derivar `uri -> traefik_tag -> address`
- criar `openwrt_dhcp_domain.records` quando existirem serviços validos
- reconciliar regras agregadas de firewall com `terraform_data.firewall_rules` e `scripts/ensure-openwrt-firewall.py`

Limites reais:

- nao cria CTs nem VMs
- nao inventa `traefik_instances`
- depende de `ingress.yaml` e `services[]`
- o provider oficial entra no `plan`, mas no host OpenWrt real deste workspace falha em LuCI RPC porque espera `/cgi-bin/luci/rpc/auth` e esse endpoint devolve `404`

## `stacks/ansible`

Estado real:

- stack minimo
- filtra `targets` com `ansible_enabled=true`
- nao aplica configuracao externa

## `stacks/pbs`

Estado real:

- stack minimo
- filtra `targets` com `backup_policy` preenchida
- nao aplica politicas PBS externas

## Contratos Entre Stacks

`proxmox-base` exporta:

- `inventory_summary`
- `created_cts`
- `created_vms`
- `ansible_targets`
- `pbs_targets`

`ansible` e `pbs` consomem apenas esse contrato.

`openwrt-dns` nao depende dos outputs internos do stack base; depende do inventario e de `ingress.yaml`.
