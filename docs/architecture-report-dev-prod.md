# Architecture Report: Dev And Prod

## 1. Visao Geral Muito Simples

Este repo gere workloads Proxmox a partir de inventario YAML por ambiente.

Fluxo principal hoje:

```text
env/<environment> + inventory/<environment> -> stack -> module -> provider/script -> sistema destino
```

Tipos de coisas geridas hoje:

- CTs Proxmox
- VMs Proxmox
- registos DNS OpenWrt derivados de `services[]`
- handoff minimo para Ansible e PBS por outputs

Diferenca pratica entre ambientes:

- `dev` tem inventario real, `plan` Proxmox comprovado e criacao fisica de CT provada
- `prod` esta estruturalmente preparado, mas nao ficou provado com credenciais reais

## 2. Desenho Simples Da Arquitetura

```text
[env/dev]
  -> [inventory/dev/defaults.yaml]
  -> [inventory/dev/nodes.yaml]
  -> [inventory/dev/networks.yaml]
  -> [inventory/dev/cts/homarr.yaml]
  -> [inventory/dev/vms/vm-template.yaml]
  -> [stacks/proxmox-base]
     -> [module proxmox-ct]
     -> [module proxmox-vm]
     -> [provider Telmate/proxmox]
     -> [script apply-proxmox-ct-features.py]
     -> [CT/VM configurados no Proxmox]

[env/dev]
  -> [inventory/dev/ingress.yaml]
  -> [inventory/dev services[] com traefik_tag]
  -> [stacks/openwrt-dns]
     -> [provider joneshf/openwrt]
     -> [script ensure-openwrt-firewall.py]
     -> [DNS/firewall no OpenWrt]

[outputs de proxmox-base]
  -> [stacks/ansible]
     -> [filtra ansible_enabled=true]
     -> [output handoff]

[outputs de proxmox-base]
  -> [stacks/pbs]
     -> [filtra backup_policy!=null]
     -> [output handoff]

[env/prod + inventory/prod]
  -> [mesmo layout]
  -> [sem nodes/workloads reais provados]
```

## 3. Mapa Dos Ambientes

### `dev`

Ficheiros:

- `env/dev/common.tfvars`
- `env/dev/proxmox-base.tfvars`
- `env/dev/openwrt-dns.tfvars`
- `inventory/dev/defaults.yaml`
- `inventory/dev/nodes.yaml`
- `inventory/dev/networks.yaml`
- `inventory/dev/ingress.yaml`
- `inventory/dev/cts/homarr.yaml`
- `inventory/dev/vms/vm-template.yaml`

Finalidade pratica:

- ambiente ativo de desenvolvimento
- alvo do `plan` Proxmox real comprovado

Estado:

- utilizavel para `proxmox-base`
- `openwrt-dns` definido e validado estruturalmente, mas nao provado como planeamento bem-sucedido com o provider oficial

Stacks alimentadas:

- `proxmox-base`
- `openwrt-dns`
- `ansible`
- `pbs`

### `prod`

Ficheiros:

- `env/prod/common.tfvars`
- `env/prod/proxmox-base.tfvars`
- `env/prod/openwrt-dns.tfvars`
- `inventory/prod/defaults.yaml`
- `inventory/prod/nodes.yaml`
- `inventory/prod/networks.yaml`
- `inventory/prod/ingress.yaml`

Finalidade pratica:

- ambiente final suportado no layout

Estado:

- estruturalmente preparado
- sem nodes, redes ou workloads declarados
- nao ficou provado com credenciais reais

Stacks alimentadas:

- pode alimentar as mesmas stacks que `dev`, mas hoje nao alimenta workloads reais

### Historico

- `env/legacy/lab/`
- `inventory/legacy/lab/`
- `legacy/root-module/`

Isto existe para referencia e migracao, nao como ambiente ativo.

## 4. O Que Acontece Quando O Repo Gera Um CT

Fluxo provado hoje para `homarr`:

1. `stacks/proxmox-base/locals.tf` le:
   - `inventory/dev/defaults.yaml`
   - `inventory/dev/nodes.yaml`
   - `inventory/dev/networks.yaml`
   - `inventory/dev/cts/homarr.yaml`
2. O stack faz merge de:
   - defaults comuns
   - defaults CT
   - segmento de rede
   - workload do CT
3. O CT ativo atual e:
   - `name = homarr`
   - `vmid = 6011`
   - `node = dev-proxmox`
   - `network.segment = vlan-99`
   - `network.mode = dhcp`
   - sem `vlan` declarada no inventario ativo de teste
   - `lxc.template = local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`
   - `memory_mb = 1024`
   - `swap_mb = 1024`
   - `rootfs_size_gb = 8`
4. `stacks/proxmox-base/main.tf` instancia `module.cts["homarr"]`
5. `modules/proxmox-ct/main.tf` cria o recurso `proxmox_lxc.this`
6. Depois disso, `terraform_data.ct_manual_features` chama `scripts/apply-proxmox-ct-features.py`
7. Esse script reconcilia:
   - `nesting`
   - `keyctl`
   - `fuse`
   - `description`
   - `nameserver`
   - `searchdomain`

Notas importantes:

- `description` pode ser gerada a partir de `services[]` com `traefik_tag`
- no `dev` atual, `homarr` tem `services: []`
- por isso nao ha notas Traefik ativas no inventario atual
- `mounts` nao vazios nao entram neste fluxo; o validador rejeita-os

O que ficou efetivamente criado/configurado no Proxmox no teste real:

- CT LXC base
- rootfs
- rede
- tags
- parametros de boot
- o CT `6011` apareceu fisicamente no Proxmox e ficou `running`

O que nao ficou provado como convergido:

- fim do `apply` completo com state limpo
- o resultado final da reconciliacao pos-criacao pelo `terraform_data.ct_manual_features` depois do bootstrap de `python3` no runtime Alpine do CT Terraform

## 5. Onde Cada Configuracao E Aplicada

| Tipo | Origem | Ficheiro | Consumidor | Destino |
|---|---|---|---|---|
| ambiente | tfvars | `env/dev/common.tfvars`, `env/prod/common.tfvars` | stacks ativos | selecao de `inventory/<environment>` |
| credenciais Proxmox | tfvars / JSON externo | `env/*/proxmox-base.tfvars`, `/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json` | `stacks/proxmox-base/providers.tf` | API Proxmox |
| definicao de CT | YAML | `inventory/dev/cts/homarr.yaml` | `stacks/proxmox-base` | `module proxmox-ct` |
| definicao de VM | YAML | `inventory/dev/vms/vm-template.yaml` | `stacks/proxmox-base` | `module proxmox-vm` |
| defaults | YAML | `inventory/*/defaults.yaml` | `locals.tf` dos stacks | merge base por tipo |
| nodes | YAML | `inventory/*/nodes.yaml` | checks de `proxmox-base` | validacao de `node` |
| redes | YAML | `inventory/*/networks.yaml` | merge em `proxmox-base` | bridge, vlan, gateway, DNS |
| ingress Traefik | YAML | `inventory/*/ingress.yaml` | `stacks/openwrt-dns/locals.tf` | resolucao `uri -> IP` |
| notas Traefik | `services[]` | `inventory/*/cts/*.yaml`, `inventory/*/vms/*.yaml` | `stacks/proxmox-base/locals.tf` | `description` do CT no Proxmox |
| DNS OpenWrt | `services[]` + ingress | `stacks/openwrt-dns/main.tf` | `openwrt_dhcp_domain.records` | OpenWrt |
| firewall OpenWrt | vars + inventario | `scripts/ensure-openwrt-firewall.py` | `terraform_data.firewall_rules` | OpenWrt por SSH/UCI |
| handoff Ansible | outputs | `stacks/ansible/main.tf` | filtro `ansible_enabled` | output apenas |
| handoff PBS | outputs | `stacks/pbs/main.tf` | filtro `backup_policy` | output apenas |

## 6. Estado Real Das Features

| Feature | O que faz | Evidencia | Estado | Impacto real |
|---|---|---|---|---|
| CT Proxmox | cria CTs via `proxmox_lxc` | `modules/proxmox-ct/main.tf`, `plan` real em `dev`, CT `6011` observado no Proxmox | definido + apply-parcial-provado | `homarr` e criado fisicamente, mas o `apply` nao converge no passo final |
| VM Proxmox | cria VMs via `proxmox_vm_qemu` | `modules/proxmox-vm/main.tf`, teste com workspace temporario e `enabled: true` | definido, nao provado | o modulo nao ficou provado a entrar no grafo real de forma operacionalmente util |
| notas Traefik | gera `description` para Proxmox | `stacks/proxmox-base/locals.tf` | definido, nao provado no inventario atual | sem efeito no `dev` atual |
| reconciliacao manual CT | aplica `nesting`, `keyctl`, `fuse`, DNS e descricao | `stacks/proxmox-base/main.tf`, `scripts/apply-proxmox-ct-features.py` | definido + entra no `plan` | o CT ganha um passo pos-criacao fora do provider |
| mounts LXC | mounts manuais | `scripts/validate-inventory.py` | explicitamente nao suportado | entradas nao vazias falham cedo |
| OpenWrt DNS | cria `openwrt_dhcp_domain` | `stacks/openwrt-dns/main.tf` | definido, provider chamado, `plan` falha | nao ficou provado `apply` |
| OpenWrt firewall | deriva regras e aplica via script | `scripts/ensure-openwrt-firewall.py` | definido, nao provado com sucesso no fluxo atual | depende de SSH/UCI e do inventario Traefik |
| Ansible handoff | filtra targets | `stacks/ansible/main.tf` | ativo minimo | output apenas |
| PBS handoff | filtra targets | `stacks/pbs/main.tf` | ativo minimo | output apenas |

## 7. Addons / Plugins / Providers

### Providers ativos no core

| Provider | Onde | Obrigatorio | Uso real |
|---|---|---|---|
| `Telmate/proxmox` | `stacks/proxmox-base/versions.tf` | sim para `proxmox-base` | plan real comprovado; criacao fisica do CT comprovada |
| `joneshf/openwrt` | `stacks/openwrt-dns/versions.tf` | sim para `openwrt-dns` | provider entra no plan, mas falha no endpoint LuCI atual |
| `terraform` builtin | `terraform_data` nos stacks | sim | usado para reconciliacao/manual exec |

### Scripts auxiliares com impacto real

| Script | Papel | Estado |
|---|---|---|
| `scripts/apply-proxmox-ct-features.py` | reconciliacao pos-criacao de CT | ativo no fluxo |
| `scripts/ensure-openwrt-firewall.py` | reconciliacao firewall OpenWrt | definido, nao provado com sucesso no fluxo atual |
| `scripts/test-openwrt-dev.sh` | helper de provider alternativo | experimental; requer Go local |

### Providers legacy

So no legado:

- `rundeck`
- `portainer`
- `local`
- `null`

Nao fazem parte do core ativo atual.

## 8. Fluxo Pratico De Execucao

Comandos uteis hoje:

```bash
bash scripts/validate-repo.sh
bash scripts/validate-inventory.sh
```

`plan` real Proxmox em `dev`:

```bash
STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json \
bash scripts/plan-stack.sh proxmox-base dev
```

`plan` OpenWrt com dados reais:

```bash
terraform -chdir=stacks/openwrt-dns plan \
  -var-file=env/dev/common.tfvars \
  -var-file=/mnt/data/terraform-lab/tfvars/lab-openwrt-dns.tfvars.json \
  -var environment=dev \
  -var inventory_root=../../inventory
```

O que falha cedo:

- placeholders de credenciais em `proxmox-base`
- `mounts` nao vazios
- `features_manual.mount` preenchido
- `node` ou `network.segment` inexistentes

O que so falha em runtime/provider access:

- autenticacao/API Proxmox
- incompatibilidade do provider OpenWrt com o endpoint real
- SSH/UCI do firewall OpenWrt

Dependencias externas reais:

- API Proxmox
- host OpenWrt
- Docker + Compose no `dev-terraform-101` para correr Terraform no contentor
- Python 3

Backends:

- nao foram encontrados blocos `backend` nos `.tf` ativos
- o repo fala em backend remoto como orientacao, nao como configuracao ativa no codigo atual

## 9. Riscos, Zonas Confusas E Divida Tecnica

- `openwrt-dns` tem drift claro entre inventario ativo e `terraform.tfstate` local
- o provider oficial OpenWrt nao encaixa no endpoint LuCI atual do host provado
- nao foram encontrados artefactos reais de `prod` em `/mnt/data`
- `prod` esta completo no layout, mas nao provado operacionalmente
- o helper `test-openwrt-dev.sh` depende de um provider alternativo e de Go local
- existe documentacao e artefactos historicos `lab` que continuam relevantes para paths reais de credenciais, mas nao para o modelo de ambientes
- nao ha backend Terraform ativo configurado no codigo
- os states locais `*.backup` ainda mostram a realidade antiga com `homarr-ui.lbtec.org` e `traefik-int`

## 10. Resposta Final Em Formato Muito Pratico

### A. Se eu quiser perceber este repo em 2 minutos

Hoje o repo tem dois ambientes ativos no layout: `dev` e `prod`. O que realmente faz trabalho util hoje e `stacks/proxmox-base`; ele ja provou `plan` real e criacao fisica de CT. `stacks/openwrt-dns` existe, mas o provider oficial falha no endpoint real do OpenWrt atual. `ansible` e `pbs` sao stacks minimos de export/handoff.

### B. Se eu quiser criar um CT

Editar `inventory/dev/cts/<nome>.yaml`, validar o inventario, fornecer credenciais reais Proxmox e correr:

```bash
STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json \
bash scripts/plan-stack.sh proxmox-base dev
```

### C. Se eu quiser perceber os ambientes

- `dev`: ambiente real, com `homarr` ativo, `plan` Proxmox provado e CT fisicamente criado
- `prod`: ambiente estrutural, sem prova real

### D. Se eu quiser validar se os plugins/addons funcionam

- `Telmate/proxmox`: comprovado ao nivel de `plan`
- `joneshf/openwrt`: chamado no `plan`, mas falha no endpoint LuCI atual
- scripts auxiliares: `apply-proxmox-ct-features.py` esta no fluxo; `ensure-openwrt-firewall.py` existe mas nao ficou provado com sucesso

### E. O que este repo faz realmente hoje

Faz validacao de inventario, modela CTs/VMs Proxmox, faz `plan` real Proxmox para `dev`, e tem um stack OpenWrt definido mas operacionalmente bloqueado pela compatibilidade do provider oficial com o endpoint real atual.
