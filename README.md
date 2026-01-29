Terraform + Proxmox + Rundeck

fluxo:
terraform apply -> add/remove no proxmox -> job rundeck

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

2. Integração com rundeck -> já funciona com integracao basica
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

3. Quando Terraform geral contentor, verificar local de backups pelo VMID e copiar para o host os dados guardados