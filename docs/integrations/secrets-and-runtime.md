# Secrets And Runtime

## O Que Fica Dentro Do Repo

- schema de inventário
- stacks Terraform
- scripts de render e validação
- documentação operacional

## O Que Fica Fora Do Git

- segredos reais OpenWrt
- segredos reais Proxmox
- segredos do runtime Traefik

## Render Local De Ficheiros Operacionais

Com um manifesto consolidado:

```bash
python3 scripts/render-local-tfvars.py \
  --manifest /mnt/data/terraform-lab/credentials/lab-credentials.json \
  --output-dir /mnt/data/terraform-lab/tfvars
```

O script gera:

- `<environment>-proxmox-base.tfvars.json`
- `<environment>-openwrt-dns.tfvars.json`
- `<environment>-external-hosts.json`
- `<environment>-traefik-proxmox-provider.env`

## Runtime Externo Necessário

### Terraform

- `terraform` CLI
- acesso Proxmox para `proxmox-base`
- acesso OpenWrt para `openwrt-dns`
- fork local do provider OpenWrt apenas quando o endpoint real exigir o fallback `admin/ubus`

### Traefik

- runtime Traefik externo a este repo
- plugin `traefik-proxmox-provider`
- token Proxmox com permissões de leitura

## O Que Cada Componente Faz

Terraform:

- cria CTs e VMs em Proxmox
- escreve notes Traefik em CTs e VMs
- cria DNS OpenWrt e firewall derivado

Traefik:

- lê notes/description do Proxmox
- descobre workloads em `running`
- cria configuração dinâmica HTTP a partir das labels

## Validação Operacional

- primeiro validar `proxmox-base`
- depois validar `openwrt-dns`
- por fim validar o runtime Traefik com o `.env` gerado e a config estática do plugin
