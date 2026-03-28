# OpenWrt Provider

## O Que O Terraform Usa Diretamente

O stack `stacks/openwrt-dns` usa diretamente o provider Terraform `joneshf/openwrt`.

Declaração atual:

```hcl
terraform {
  required_providers {
    openwrt = {
      source  = "joneshf/openwrt"
      version = "= 0.0.20"
    }
  }
}
```

## Argumentos Do Provider

Evidência nas docs oficiais do provider:

- `hostname`
- `port`
- `scheme`
- `username`
- `password`

No repo estes argumentos são alimentados por:

- `openwrt_hostname`
- `openwrt_port`
- `openwrt_scheme`
- `openwrt_username`
- `openwrt_password`

## Local Override / Fork

O source Terraform continua a ser `joneshf/openwrt`.

Quando o OpenWrt real só expõe `/cgi-bin/luci/admin/ubus`, o repo suporta consumo do fork local através de `dev_overrides`:

```bash
export OPENWRT_PROVIDER_DEV_OVERRIDE=1
bash scripts/plan-stack.sh openwrt-dns dev
```

Por omissão o override procura o provider local em:

```text
../terraform-provider-openwrt
```

Se precisares de outro path:

```bash
export OPENWRT_PROVIDER_OVERRIDE_DIR=/caminho/para/provider
```

Para atualizar e reconstruir o binário local:

```bash
bash scripts/sync-local-openwrt-provider.sh
```

## Variáveis Operacionais

O stack usa:

- `openwrt_hostname`
- `openwrt_port`
- `openwrt_scheme`
- `openwrt_username`
- `openwrt_password`
- `openwrt_firewall_enabled`
- `openwrt_firewall_apply`
- `openwrt_firewall_ssh_host`
- `openwrt_firewall_ssh_port`
- `openwrt_firewall_ssh_user`
- `proxmox_api_url`
- `proxmox_api_token_id`
- `proxmox_api_token`
- `proxmox_tls_insecure`

Os exemplos vivem em:

- `env/dev/openwrt-dns.tfvars.example`
- `env/prod/openwrt-dns.tfvars.example`

## O Que O Stack Faz

- cria `openwrt_dhcp_domain.records` para `uri -> address`
- reconcilia regras de firewall derivadas com `scripts/ensure-openwrt-firewall.py`

## Validação

Estrutural:

```bash
terraform -chdir=stacks/openwrt-dns init -backend=false
terraform -chdir=stacks/openwrt-dns validate
```

Com fork local:

```bash
bash scripts/sync-local-openwrt-provider.sh
OPENWRT_PROVIDER_DEV_OVERRIDE=1 bash scripts/plan-stack.sh openwrt-dns dev
```

## Limitação Importante

Sem reachability e credenciais reais do OpenWrt não é possível provar `plan/apply` completos. Isso é limitação de ambiente, não substitui a validação estrutural local.
