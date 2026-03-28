# Traefik Proxmox Provider

## Limite Arquitetural

O `traefik-proxmox-provider` não é um provider Terraform.

Terraform neste repo apenas prepara o ecossistema para o Traefik o consumir:

- escreve labels `traefik.*` em notes/description Proxmox
- mantém coerência entre `services[]` e `inventory/<environment>/ingress.yaml`
- gera segredos/runtime auxiliares para o Traefik

## O Que O Plugin Espera

Evidência no README e código do plugin:

- plugin instalado no bloco `experimental.plugins` ou `experimental.localPlugins`
- configuração do provider em config estática do Traefik
- campos suportados:
  - `pollInterval`
  - `apiEndpoint`
  - `apiTokenId`
  - `apiToken`
  - `apiLogging`
  - `apiValidateSSL`
  - `labelPrefix`
- labels são lidas das notes Proxmox

## Como Este Repo Alimenta O Plugin

Fonte de verdade:

- `inventory/<environment>/ingress.yaml`
- `inventory/<environment>/cts/*.yaml`
- `inventory/<environment>/vms/*.yaml`

Convenção atual:

- cada serviço Traefik declara:
  - `traefik_tag`
  - `traefik_label`
  - `uri`
  - `port`
- o stack `proxmox-base` escreve notes em CTs e VMs no formato:

```text
<traefik_tag>.enable=true
<traefik_tag>.http.routers.<traefik_label>.rule=Host(`<uri>`)
<traefik_tag>.http.services.<traefik_label>.loadbalancer.server.port=<port>
```

O plugin normaliza esse prefixo para `traefik.*` internamente.

## Regra Operacional Importante

`labelPrefix` é único por instância do provider plugin.

Logo:

- um `traefik_tag` do inventário corresponde a uma instância do provider plugin no Traefik
- se existirem vários `traefik_tag`, o runtime Traefik precisa de várias instâncias do plugin, uma por tag

## Exemplo De Configuração Estática

Exemplo mínimo por tag:

```yaml
experimental:
  plugins:
    traefik-proxmox-provider:
      moduleName: github.com/lmbalcao/traefik-proxmox-provider
      version: v0.1.0

providers:
  plugin:
    traefik-proxmox-dev:
      pollInterval: "30s"
      apiEndpoint: "${PROXMOX_API_ENDPOINT}"
      apiTokenId: "${PROXMOX_TOKEN_ID}"
      apiToken: "${PROXMOX_TOKEN_SECRET}"
      apiLogging: "${PROXMOX_API_LOGGING}"
      apiValidateSSL: "${PROXMOX_API_VALIDATE_SSL}"
      labelPrefix: "traefik-dev."
```

Se o runtime usar plugin local em vez do catálogo:

```yaml
experimental:
  localPlugins:
    traefik-proxmox-provider:
      moduleName: github.com/lmbalcao/traefik-proxmox-provider
```

## Credenciais Proxmox

O plugin precisa de token Proxmox com privilégios de leitura.

Segundo o README do plugin:

- PVE 8.x ou anterior:
  - `VM.Audit,VM.Monitor,Sys.Audit,Datastore.Audit`
- PVE 9.x ou posterior:
  - `VM.Audit,VM.GuestAgent.Audit,Sys.Audit,Datastore.Audit`

## Output De Runtime Gerado Pelo Repo

`scripts/render-local-tfvars.py` passa a gerar:

```text
<environment>-traefik-proxmox-provider.env
```

Esse ficheiro contém:

- `PROXMOX_API_ENDPOINT`
- `PROXMOX_TOKEN_ID`
- `PROXMOX_TOKEN_SECRET`
- `PROXMOX_POLL_INTERVAL`
- `PROXMOX_API_LOGGING`
- `PROXMOX_API_VALIDATE_SSL`

## Validação

No lado Terraform:

- `terraform -chdir=stacks/proxmox-base validate`
- verificar que CTs/VMs com `services[]` recebem `description`

No lado Traefik:

- usar o `.env` gerado
- configurar uma instância do plugin por `traefik_tag`
- confirmar que os workloads estão `running`
- confirmar que as notes no Proxmox contêm as labels esperadas
