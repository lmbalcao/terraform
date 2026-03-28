# OpenWrt + Traefik Proxmox Analysis

Data: 2026-03-28

## Fontes Reais Consultadas

- `terraform-provider-openwrt`
  - upstream remoto: `https://github.com/joneshf/terraform-provider-openwrt.git`
  - fork remoto usado no workspace: `https://github.com/lmbalcao/terraform-provider-openwrt.git`
  - docs locais lidas: `../terraform-provider-openwrt/docs/index.md`, `../terraform-provider-openwrt/docs/resources/dhcp_domain.md`
  - código local lido: `../terraform-provider-openwrt/lucirpc/client.go`
- `traefik-proxmox-provider`
  - remoto usado no workspace: `https://forgejo.lbtec.org/lmbalcao/traefik-provider-proxmox.git`
  - README local lido: `../traefik-provider-proxmox/README.md`
  - código local lido: `../traefik-provider-proxmox/provider/provider.go`, `../traefik-provider-proxmox/internal/client.go`, `../traefik-provider-proxmox/internal/models.go`
- repo Terraform local
  - `stacks/openwrt-dns/*`
  - `stacks/proxmox-base/*`
  - `modules/proxmox-ct/*`
  - `modules/proxmox-vm/*`
  - `scripts/sync-local-openwrt-provider.sh`
  - `scripts/test-openwrt-dev.sh`
  - `scripts/plan-stack.sh`
  - `scripts/render-local-tfvars.py`
  - `inventory/*`
  - `docs/*`
- runtime Traefik já existente no workspace
  - `../docker/traefik/docker-compose.yml`

## Resumo Técnico Do Modo De Integração Correto

### `terraform-provider-openwrt`

Evidência no código oficial:

- o provider Terraform declara `hostname`, `port`, `scheme`, `username`, `password`
- o resource já usado pelo repo, `openwrt_dhcp_domain`, existe e suporta `id`, `name`, `ip`
- a source address continua a ser `joneshf/openwrt`

Evidência no repo atual:

- `stacks/openwrt-dns/versions.tf` já declara `joneshf/openwrt = 0.0.20`
- `stacks/openwrt-dns/providers.tf` já usa os cinco argumentos suportados pelo provider
- `stacks/openwrt-dns/main.tf` já cria `openwrt_dhcp_domain.records`
- existem scripts já previstos para fork/local override:
  - `scripts/sync-local-openwrt-provider.sh`
  - `scripts/test-openwrt-dev.sh`

Evidência no fork local:

- `../terraform-provider-openwrt/lucirpc/client.go` implementa fallback para `/cgi-bin/luci/admin/ubus`
- o branch ativo do fork local é `wip/openwrt-ubus-fallback`

Inferência razoável:

- a integração correta no repo Terraform não exige mudar `required_providers.source`; exige manter `joneshf/openwrt` e usar `dev_overrides` quando for preciso consumir o fork local compatível com o OpenWrt real

### `traefik-proxmox-provider`

Evidência no README e código do plugin:

- não é provider Terraform
- é provider plugin do Traefik
- configuração suportada no plugin:
  - `pollInterval`
  - `apiEndpoint`
  - `apiTokenId`
  - `apiToken`
  - `apiLogging`
  - `apiValidateSSL`
  - `labelPrefix`
- o cliente do plugin faz append automático de `/api2/json` ao `apiEndpoint`
- labels são lidas do campo Proxmox `description` / notes
- apenas workloads em `running` são descobertos

Evidência no repo atual:

- o inventário já tem `services[].traefik_tag`, `services[].traefik_label`, `services[].uri`, `services[].port`
- `stacks/proxmox-base/locals.tf` já gerava notes Traefik para CTs
- `modules/proxmox-ct/main.tf` já escrevia `description` em Proxmox
- `modules/proxmox-vm/main.tf` não escrevia `description`
- `../docker/traefik/docker-compose.yml` já usa o plugin, mas com configuração fixa `labelPrefix=traefik-int.` que não está alinhada com o inventário atual `dev`

Lacuna por implementar:

- VMs com `services[]` não eram preparadas para o plugin
- o fluxo normal `scripts/plan-stack.sh` não suportava `dev_overrides` do provider OpenWrt
- o render de segredos locais não emitia um `.env` reutilizável pelo runtime Traefik
- a documentação principal não descrevia de forma suficiente a separação entre Terraform e plugin Traefik

## Diferenças Entre Provider Terraform E Provider De Traefik

### Provider Terraform OpenWrt

- é carregado pelo Terraform
- participa em `terraform init`, `plan`, `apply`
- gere diretamente recursos OpenWrt suportados pelo provider, como `openwrt_dhcp_domain`

### Plugin Provider Traefik Proxmox

- é carregado pelo Traefik
- não participa em `terraform init`, `plan`, `apply`
- consome notes/description escritas em Proxmox e credenciais Proxmox próprias
- o papel do Terraform é preparar esse ecossistema:
  - gerar notes/description compatíveis
  - manter coerência de `traefik_tag` com `inventory/*/ingress.yaml`
  - documentar e gerar segredos/runtime externos necessários

## Impactos No Repo Atual

- `openwrt-dns` já estava estruturalmente perto do correto; o principal ajuste é operacionalizar o fork local via `dev_overrides` sem quebrar o source oficial
- `proxmox-base` precisava passar a escrever notes também em VMs
- o render de segredos locais precisava passar a produzir ficheiro consumível pelo runtime Traefik
- a documentação precisava separar claramente:
  - o que Terraform usa diretamente
  - o que apenas prepara para o Traefik

## Lista Exata De Ficheiros Que Precisavam De Alteração

- `modules/proxmox-vm/main.tf`
- `modules/proxmox-vm/variables.tf`
- `stacks/proxmox-base/main.tf`
- `stacks/proxmox-base/locals.tf`
- `stacks/openwrt-dns/variables.tf`
- `scripts/sync-local-openwrt-provider.sh`
- `scripts/plan-stack.sh`
- `scripts/render-local-tfvars.py`
- `tests/test_render_local_tfvars.py`
- `README.md`
- `docs/README.md`
- `docs/local-credentials.md`
- `docs/stack-boundaries.md`
- `docs/inventory-schema.md`
- `docs/integrations/openwrt-traefik-proxmox-plan.md`
- `docs/integrations/openwrt-provider.md`
- `docs/integrations/traefik-proxmox-provider.md`
- `docs/integrations/secrets-and-runtime.md`
