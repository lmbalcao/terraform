# 1. Resumo Executivo

O repo atual mistura três responsabilidades no mesmo root module: provisão Proxmox, configuração imperativa dentro dos guests e orquestração operacional de apps/serviços externos. A direção certa é separar isso em `stacks` independentes, com um núcleo `proxmox-base` orientado por inventário, manter `Ansible` e `PBS` como componentes suportados da arquitetura e remover `Vault`, `Rundeck`, `Portainer` e `Restic` deste repositório. `notas.lmb` é uma boa semente de schema, mas ainda está demasiado ambíguo e inconsistente para ser a forma final.

# 2. Leitura do Estado Atual do Repositório

- O repo é um root Terraform plano, com inventário em `locals`, deploy de CT/VM, pós-configuração, Docker, Portainer, Restic e Rundeck no mesmo nível: `00-inventory.tf`, `01-proxmox_ct_deploy.tf`, `02-proxmox_vm_deploy.tf`, `15-docker_setup.tf`, `20-docker_deploy.tf`, `30-portainer_endpoints.tf`, `50-rundeck_deploy.tf`.
- Providers declarados: Proxmox, Portainer e Rundeck em `providers.tf`. No lockfile existem também `hashicorp/null` e `hashicorp/local`, mas não são declarados explicitamente.
- O repo referencia módulos inexistentes em `modules.tf`. Não existe diretório `modules/`.
- O working tree está sujo: `00-inventory.tf` modificado, `notas.lmb`, `06-ansible_deploy.tf` e `11-pbs_deploy.tf` não versionados.
- A pipeline só valida baseline de repositório, não Terraform: `.forgejo/workflows/validate.yml`. Não consegui correr `terraform validate` porque o binário `terraform` não está instalado neste workspace.

# 3. Problemas Encontrados

- Acoplamento excessivo: todos os CTs `enabled` recebem Docker, TLS, endpoint Portainer e potencialmente apps, porque a lógica opera sobre `local.enabled_cts` sem distinguir papéis: `15-docker_setup.tf`, `30-portainer_endpoints.tf`, `20-docker_deploy.tf`.
- Defaults perigosos: Restic e Rundeck assumem `true` quando `controlo_manual` não existe, o que torna side effects acidentais muito fáceis: `10-restic_deploy.tf`, `50-rundeck_deploy.tf`.
- Naming e schema fracos: `hostname` vs `name`, `mountpoints` vs `pct_mounts`, `controlo_manual` misturado com inglês, `ultimo_octeto` a contaminar rede e VMID: `00-inventory.tf`, `05-post_proxmox_deploy.tf`, `notas.lmb`.
- Código morto ou obsoleto: módulos inexistentes em `modules.tf`, template VM errado em `templates/vm.tf`, `fetch_docker_ca_certs` sem consumidor em `15-docker_setup.tf`, `portainer_join_token` não usado em `vars-portainer.tf`.
- Deriva semântica: o provider Rundeck é declarado em `providers.tf`, mas o deploy usa `curl` direto para API v44 em `50-rundeck_deploy.tf`.
- Modelo VM incompleto: o inventário guarda `clone` e `ostemplate`, mas o recurso VM não os usa; não há cloud-init, IP nem outputs equivalentes aos CTs: `00-inventory.tf`, `02-proxmox_vm_deploy.tf`, `99-output.tf`.

# 4. Interpretação Crítica do `notas.lmb`

`notas.lmb` melhora a legibilidade ao separar `network`, `resources`, `boot`, `storage` e `traefik`, e essa direção deve ser mantida. O que precisa de correção é a forma: `sn` deve virar `true/false`, `uri/porta` não chega porque o próprio exemplo mostra múltiplos serviços, labels Traefik em blob de texto não devem ser a fonte de verdade, e CT/VM precisam de campos comuns normalizados mais blocos específicos por tipo. Também falta explicitar `vmid`, `ip/gateway` quando não houver DHCP e remover campos LXC do template VM.

# 5. Proposta de Novo Modelo de Inventário

Modelo final: `version`, `defaults`, `nodes`, `networks`, `cts`, `vms`.

- Campos comuns para CT e VM: `enabled`, `vmid`, `name`, `node`, `tags`, `network`, `resources`, `boot`, `services`, `operations`.
- `network` deve usar `segment`, `mode`, `address`, `gateway`, `dns_servers`, `dns_domain`; não usar `ultimo_octeto` como fonte de verdade.
- `resources` e `storage` devem usar números (`memory_mb`, `swap_mb`, `size_gb`) e o Terraform converte para o formato do provider.
- CTs ficam com bloco `lxc`: `template`, `unprivileged`, `features`, `mounts`.
- VMs ficam com bloco `qemu`: `source.clone` ou `source.template`, `sockets`, `agent`, `cloud_init`, `disks`.
- `services` substitui `access.uri/porta` e o blob Traefik; cada serviço exposto deve ter `name`, `port`, `scheme` e opcional `proxy`.

# 6. Proposta de Nova Estrutura do Repositório

```text
inventory/
  lab/{defaults.yaml,nodes.yaml,networks.yaml,cts/*.yaml,vms/*.yaml}
  staging/...
  prod/...
modules/
  proxmox-ct/
  proxmox-vm/
stacks/
  proxmox-base/
  ansible/
  pbs/
env/
  lab/*.tfvars
  staging/*.tfvars
  prod/*.tfvars
docs/
  inventory-schema.md
```

- Manter: metadata de repo, `scripts/validate-repo.sh`, `.forgejo/`, docs gerais.
- Mover/fundir: root `providers.tf`, `vars-*.tf`, `01/02/05/...` para `stacks/` e `modules/`, preservando apenas o que serve `proxmox-base`, `ansible` e `pbs`.
- Remover: `modules.tf`, `templates/`, `10-validade_backup.tf`, `10-restic_deploy.tf`, `15-docker_setup.tf`, `20-docker_deploy.tf`, `30-portainer_endpoints.tf`, `50-rundeck_deploy.tf`, `local.enabled_cts_docker`, `teste`.
- Recriar de raiz: stack raiz Terraform, README técnico, validações, providers por stack, outputs, CI com `fmt`/`validate`.

# 7. Avaliação das Apps

- Ansible: deve manter-se no repositório como camada suportada de configuração pós-provisionamento, mas desacoplada do stack base. O papel certo é consumir o inventário e outputs do Terraform, não substituir o Terraform nem repetir modelação de infraestrutura.
- Vault: deve sair deste repositório. É uma dependência externa de gestão de segredos e não uma peça estrutural do inventário ou da provisão Proxmox.
- Rundeck: deve sair deste repositório. O uso atual é um trigger lateral com `curl`, fora do modelo de estado do Terraform e sem justificação suficiente para continuar no desenho alvo.
- PBS: deve manter-se no repositório como componente de infraestrutura. Faz sentido no ecossistema Proxmox e deve evoluir para integração explícita com políticas de backup, incluindo associação e automatização da inclusão de CTs e VMs em planos de backup.
- Portainer: deve sair deste repositório. A sua existência empurra o desenho para gestão de apps Docker dentro do stack de infraestrutura e aumenta o acoplamento operacional sem ser parte da base pretendida.
- Restic: deve sair deste repositório. O restore em `apply` é demasiado intrusivo, imperativo e frágil para continuar como parte da arquitetura alvo.

# 8. Decisões de Manter / Opcional / Remover

- Manter: `proxmox-base`, inventário, módulos CT/VM, `Ansible`, `PBS`, metadados de networking lógico e de exposição de serviços.
- Opcional: consumidor futuro de reverse proxy, desde que consuma metadados do inventário sem contaminar o core.
- Remover: `Vault`, `Rundeck`, `Portainer`, `Restic`, bootstrap Docker global por defeito, templates legacy, módulos fantasma e placeholders vazios.

# 9. Plano de Migração por Fases

1. Congelar o estado atual e fechar o schema alvo do inventário com base em `notas.lmb`.
2. Modelar `inventory/` e converter o atual `00-inventory.tf` para YAML normalizado, sem ainda mudar o runtime.
3. Criar `stacks/proxmox-base` e `modules/proxmox-ct`/`proxmox-vm`, primeiro em paridade funcional mínima.
4. Extrair a configuração para três linhas claras: `proxmox-base`, `ansible` e `pbs`, removendo `Portainer`, `Restic`, `Rundeck` e restante lógica operacional acoplada ao core.
5. Eliminar o root module plano, templates legacy, providers desnecessários e validações baseadas em `null_resource`.

# 10. Riscos e Pontos a Validar Antes de Implementar

- Confirmar se `vmid` passa a explícito; eu recomendo que sim, porque DHCP e redes não-`192.168.<vlan>.0/24` quebram o modelo atual.
- Decidir o limite exato entre `proxmox-base` e `ansible`, para que o bootstrap mínimo fique do lado certo e `remote-exec` deixe de ser o mecanismo principal.
- Validar o desenho do `pbs` como integração de infraestrutura, incluindo como CTs e VMs entram em políticas e planos de backup sem reintroduzir lógica imperativa dispersa.
- Decidir a política de segredos e backend de state, porque hoje não há backend nem `required_version`.
- Validar a semântica de `services/proxy` para Traefik antes de fixar o schema, para evitar inventário demasiado abstrato ou demasiado “raw labels”.
