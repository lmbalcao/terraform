Terraform + Proxmox + Rundeck

fluxo:
terraform apply -> T/F add/remove no proxmox -> instala base -> prepara docker -> liga ao portainer instala -> T/F stack do forgejo -> T/F corre job rundeck

1. tenho o inventory.tf onde defino requisitos individuais para cada ct
          enabled      = true / false
          true -> aplica
          false -> destroi

2. tenho ct.tf que le inventory.tf e credentials.auto.tfvars

= edito apenas inventory.tf para ajustar todos os ct que quero

= variaveis fixas para todo o sistema estão no credentials.auto.tfvars

problemas:
1. nao consegue criar ct privilegiado
2. problemas com as opcoes de ct

# TODO
1. frontend para inventory.cf
    edicao do ficheiro e apply
    botoes de terraform init, plan, deploy <- e/ou forma automatica de deploy aquando alteracoes

NOTA:
    terraform apply -auto-approve -> remove a necessidade de escrever yes

2. Integração com rundeck -> já funciona com integracao basica FEITO
2.1 decidir o que quero colocar no script do rundeck a aplicar em cada host
    -> definicoes gerais para todos os hosts
        - ntp
        - logs
        - Agente de métricas (node_exporter, telegraf, etc.)
        - Agente de logs (vector, promtail, fluent-bit, etc.)
        - Healthchecks locais (serviços críticos)
        - permissoes ssh
        - Definição consistente de timezone e locale
        - Política comum de gestão de utilizadores e grupos
        - Política de sudo padronizada
        - Limpeza automática de pacotes órfãos e caches
        - Fail2ban ou equivalente
        - Política comum de rotação de logs
        - Auditoria básica (auditd)
        - Versão de Docker padronizada
        - Configuração comum do daemon (log driver, cgroups, storage)
        - Diretórios padrão para volumes
        - Política de limpeza de imagens/containers antigos
        - Banner de login (identificação + aviso legal) -> MOTD e shel comum

3. Quando Terraform gerar contentor, verificar local de backups pelo VMID e copiar para o host os dados guardados FEITO

4. acrescentar mais variaveis ao ct_proxmox (tags, ha, ...) ADICIONEI TAGS APENAS

5. ct's com docker, como fazer? FEITO

6. implementar hashivault

7. colocar tudo numa nuvem com execucao pela cloud???



export RESTIC_REPOSITORY="/mnt/pve/nas1/backups/docker-data/restic-repo"
export RESTIC_PASSWORD="*RtqZQR4TpWib3"
restic snapshots