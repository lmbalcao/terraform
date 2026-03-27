# Historical Lab External Credentials Design

This file is a historical design artifact for the earlier `lab` naming. It explains why `/mnt/data/terraform-lab/` exists on the current CT, but it does not define the active environment model of the repo.

## Goal

Gerir credenciais dos hosts externos ao inventario Terraform sem versionar segredos no git, materializando `tfvars` locais no CT `dev-terraform-101` em `/mnt/data`.

## Scope

- `192.168.99.10` `dev-pbs-9910`
- `192.168.99.100` `dev-proxmox`
- `192.168.99.150` `dev-traefik-99150`
- `192.168.99.200` `DEV-openwrt`
- `192.168.99.201` `dev-docker-2`
- `192.168.99.202` `dev-nas`
- `192.168.99.203` `dev-terraform-101`

## Decisions

- Segredos reais ficam fora do git.
- O CT Terraform guarda os artefactos em `/mnt/data/terraform-lab/`.
- O acesso SSH entre hosts usa a pubkey existente, copiada para `/mnt/data/ssh/` no CT Terraform.
- `Proxmox` usa token de API dedicado.
- `PBS` usa token de API dedicado.
- `OpenWrt` usa `username/password`, porque o provider atual consome esse modelo.
- Hosts Linux genéricos mantêm acesso via `root` + pubkey; o manifesto local regista esse mapeamento para consumo futuro.
- O repo mantém apenas exemplos, documentação e um helper para renderizar `tfvars` locais a partir de um manifesto consolidado.

## Outputs

- Manifesto consolidado com todas as credenciais em `/mnt/data/terraform-lab/credentials/lab-credentials.json`
- `tfvars` locais válidos por stack em `/mnt/data/terraform-lab/tfvars/`
- Inventário local de acesso aos hosts externos em `/mnt/data/terraform-lab/tfvars/lab-external-hosts.json`

## Safety

- Nenhum segredo novo é escrito em ficheiros versionados.
- O ficheiro local `env/lab/openwrt-dns.tfvars` no workspace fica sanitizado para evitar credenciais em claro no checkout.
