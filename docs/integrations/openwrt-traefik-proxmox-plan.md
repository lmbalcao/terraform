# OpenWrt + Traefik Proxmox Plan

Data: 2026-03-28

## Estado Atual Observado

- `stacks/openwrt-dns` já usa `joneshf/openwrt` e `openwrt_dhcp_domain`
- `scripts/sync-local-openwrt-provider.sh` e `scripts/test-openwrt-dev.sh` já previam um fork local do provider OpenWrt
- `scripts/plan-stack.sh` ainda não oferecia o mesmo caminho de `dev_overrides`
- `stacks/proxmox-base` já gerava notes Traefik para CTs
- `modules/proxmox-vm` não escrevia notes/description para VMs
- `scripts/render-local-tfvars.py` só gerava `proxmox-base`, `openwrt-dns` e `external-hosts`
- o runtime Traefik existente no workspace usa o plugin Proxmox, mas está fixado a `labelPrefix=traefik-int.`

## Lacunas Reais

- VMs não eram elegíveis para descoberta Traefik a partir do que o repo Terraform preparava
- o caminho suportado para provider OpenWrt local estava espalhado num helper experimental, não no fluxo normal
- faltava material operacional para o runtime Traefik consumir credenciais Proxmox de forma consistente
- a documentação principal não distinguia com precisão suficiente o limite entre Terraform e plugin Traefik

## Plano Exato De Alteração Por Ficheiro

- `modules/proxmox-vm/main.tf`
  - passar a escrever `description`
- `modules/proxmox-vm/variables.tf`
  - introduzir variável `description`
- `stacks/proxmox-base/main.tf`
  - passar `local.vm_descriptions` ao módulo VM
- `stacks/proxmox-base/locals.tf`
  - gerar labels/notes Traefik para VMs com a mesma convenção já usada em CTs
- `stacks/openwrt-dns/variables.tf`
  - adicionar validações mínimas para hostname, username, password e scheme
- `scripts/sync-local-openwrt-provider.sh`
  - deixar de falhar por artefactos do próprio build local
- `scripts/plan-stack.sh`
  - suportar `dev_overrides` do provider OpenWrt via env vars no fluxo normal
- `scripts/render-local-tfvars.py`
  - gerar também `*-traefik-proxmox-provider.env`
- `tests/test_render_local_tfvars.py`
  - cobrir o novo output `.env`
- `README.md`
  - alinhar visão geral, OpenWrt local override e docs de integração
- `docs/README.md`
  - indexar a nova documentação de integrações
- `docs/local-credentials.md`
  - explicar o novo output `.env`
- `docs/stack-boundaries.md`
  - explicitar que CTs e VMs podem receber notes Traefik
- `docs/inventory-schema.md`
  - reforçar semântica de `traefik_tag`, `traefik_label`, `uri`, `port`
- `docs/integrations/*`
  - documentar operação e limites arquiteturais

## Riscos

- o plugin Traefik usa `labelPrefix`; quando existirem vários `traefik_tag`, o runtime Traefik precisa de uma instância do provider por tag
- validação completa com `plan` real depende de credenciais e reachability externos
- o provider Telmate aceita tanto `desc` como `description` em `proxmox_vm_qemu`; o repo precisa de validação local para confirmar o uso do atributo escolhido

## Validações A Executar

- `terraform fmt -recursive`
- `terraform -chdir=stacks/proxmox-base init -backend=false`
- `terraform -chdir=stacks/proxmox-base validate`
- `terraform -chdir=stacks/openwrt-dns init -backend=false`
- `terraform -chdir=stacks/openwrt-dns validate`
- `python3 -m unittest -q tests/test_render_local_tfvars.py`
- `bash scripts/validate-repo.sh`
- `bash scripts/validate-inventory.sh`
- `bash scripts/sync-local-openwrt-provider.sh`
- `OPENWRT_PROVIDER_DEV_OVERRIDE=1 bash scripts/plan-stack.sh openwrt-dns dev ...` quando existirem credenciais reais
