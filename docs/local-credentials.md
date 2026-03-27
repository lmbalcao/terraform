# Local Credentials

Credenciais reais ficam fora do git.

## CT Terraform

No host `dev-terraform-101`, usar:

- `/mnt/data/ssh/id_ed25519_lab_hosts`
- `/mnt/data/ssh/id_ed25519_lab_hosts.pub`
- `/mnt/data/terraform-lab/credentials/lab-credentials.json`
- `/mnt/data/terraform-lab/tfvars/lab-proxmox-base.tfvars.json`
- `/mnt/data/terraform-lab/tfvars/lab-openwrt-dns.tfvars.json`
- `/mnt/data/terraform-lab/tfvars/lab-external-hosts.json`

Notas operacionais:

- o repo ativo usa apenas `dev` e `prod`
- no CT atual, os segredos reais ainda vivem no path historico `/mnt/data/terraform-lab/`
- isso nao torna `lab` um ambiente ativo do repo; e apenas naming legado do host atual

## Fluxo

1. Guardar ou atualizar o manifesto consolidado em `/mnt/data/terraform-lab/credentials/lab-credentials.json`.
2. Gerar os `tfvars` com:

```bash
python3 scripts/render-local-tfvars.py \
  --manifest /mnt/data/terraform-lab/credentials/lab-credentials.json \
  --output-dir /mnt/data/terraform-lab/tfvars
```

3. Se o manifesto usar `"environment": "dev"`, os ficheiros gerados passam a `dev-*.tfvars.json`. Os ficheiros `lab-*` atualmente presentes no CT sao legado operacional.

4. Usar os ficheiros resultantes com `-var-file`, por exemplo:

```bash
STACK_VARS_FILE=/mnt/data/terraform-lab/tfvars/dev-proxmox-base.tfvars.json \
bash scripts/plan-stack.sh proxmox-base dev
```

```bash
terraform -chdir=stacks/openwrt-dns plan \
  -var-file=env/dev/common.tfvars \
  -var-file=/mnt/data/terraform-lab/tfvars/dev-openwrt-dns.tfvars.json \
  -var environment=dev \
  -var inventory_root=../../inventory
```

## Nota

`env/dev/*.tfvars` e `env/prod/*.tfvars` no checkout devem manter placeholders ou ser omitidos. O source of truth operativo para segredos reais fica em `/mnt/data`.
