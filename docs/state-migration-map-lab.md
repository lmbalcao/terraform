# Historical Lab State Migration Map

Este ficheiro e historico.

O nome foi mantido porque o helper `scripts/cutover-lab.sh` e o state legacy ainda usam naming `lab`, mas este documento nao descreve a realidade operacional atual do inventario ativo.

## O Que Continua Util

Mapeamentos de enderecos de state:

- `proxmox_lxc.cts["homarr"]` -> `module.cts["homarr"].proxmox_lxc.this`
- `proxmox_vm_qemu.vms["vm_template"]` -> `module.vms["vm-template"].proxmox_vm_qemu.this`

## O Que Nao Deve Ser Tratado Como Verdade Atual

Valores antigos de:

- node legacy
- enderecos IP antigos
- segmentacao antiga
- naming `lab` como ambiente ativo

Esses valores foram ultrapassados pelo inventario ativo em `inventory/dev/`.

## Valores Ativos Verificados Hoje

### CT `homarr`

- `vmid`: `6011`
- `node`: `dev-proxmox`
- `network.segment`: `vlan-99`
- `network.mode`: `dhcp`
- `lxc.template`: `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`

### VM `vm-template`

- `vmid`: `1780`
- `node`: `dev-proxmox`
- `enabled`: `false`
- `network.address`: `192.168.17.80/24`

## Uso Correto Deste Documento

Usar apenas para:

- perceber como o legacy state se mapeia para os novos enderecos Terraform
- apoiar `state mv` durante migracao manual

Nao usar este ficheiro como fonte para reconstruir inventario novo.
