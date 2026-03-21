# Lab State Migration Map

Este ficheiro fixa o mapeamento esperado entre o runtime legacy no root e o novo stack `stacks/proxmox-base` para o ambiente `lab`.

## Recursos Identificados

### CTs

- legacy: `proxmox_lxc.cts["homarr"]`
- novo: `module.cts["homarr"].proxmox_lxc.this`
- `vmid`: `6011`
- `node`: `2core`
- `address`: `192.168.60.11/24`

### VMs

- legacy: `proxmox_vm_qemu.vms["vm_template"]`
- novo: `module.vms["vm-template"].proxmox_vm_qemu.this`
- `vmid`: `1780`
- `node`: `6core`
- `address`: `192.168.17.80/24`

## Fluxo Recomendado

1. Fazer `state pull` do root legacy.
2. Fazer backup do state antes de qualquer alteracao.
3. Inicializar `stacks/proxmox-base` com o backend final.
4. Migrar os recursos do ficheiro de state legacy para o state do stack novo.
5. Executar `plan` no novo stack e bloquear se existir `destroy` ou `replace` nao planeado.

## Exemplo com ficheiros de state locais

```bash
terraform -chdir=. state pull > /tmp/legacy.tfstate
terraform -chdir=stacks/proxmox-base state pull > /tmp/proxmox-base.tfstate

terraform state mv   -state=/tmp/legacy.tfstate   -state-out=/tmp/proxmox-base.tfstate   "proxmox_lxc.cts[\"homarr\"]"   "module.cts[\"homarr\"].proxmox_lxc.this"

terraform state mv   -state=/tmp/legacy.tfstate   -state-out=/tmp/proxmox-base.tfstate   "proxmox_vm_qemu.vms[\"vm_template\"]"   "module.vms[\"vm-template\"].proxmox_vm_qemu.this"
```

Depois destes movimentos, validar ambos os ficheiros de state e fazer `state push` apenas se o `plan` do stack novo estiver limpo ou com diferencas aprovadas.

## Cuidado Especifico

O identificador legacy da VM e `vm_template`, mas o identificador novo e `vm-template`. A migracao de state tem de respeitar essa mudanca de chave para evitar importacoes redundantes ou recursos duplicados.

## Shortcut

```bash
bash scripts/cutover-lab.sh
bash scripts/cutover-lab.sh --execute
```
