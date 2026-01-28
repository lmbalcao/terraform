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
        - permissoes ssh
        - 
