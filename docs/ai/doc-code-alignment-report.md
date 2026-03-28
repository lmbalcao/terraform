# Doc/Code Alignment Report

- repo analisado: `terraform`
- ficheiros/documentacao inspecionados: `README.md`, `AGENTS.md`, `docs/README.md`, `docs/STATE.md`, `docs/stack-boundaries.md`, `docs/inventory-schema.md`, `inventory/`, `stacks/`, `modules/`, `scripts/plan-stack.sh`, `scripts/validate-inventory.sh`
- evidencia principal encontrada: existem `stacks/proxmox-base`, `stacks/openwrt-dns`, `stacks/ansible`, `stacks/pbs`, inventario `dev`/`prod` e material `legacy/`; o README ja distingue o que foi provado em `2026-03-27` do que apenas existe estruturalmente
- inconsistencias encontradas: nao foi confirmada uma divergencia factual clara no README principal; varios resultados documentados sao historicos e nao foram reexecutados nesta auditoria
- correcoes aplicadas: criado este relatorio; sem alteracoes na documentacao principal
- validacoes executadas: `bash -n scripts/validate-repo.sh scripts/validate-inventory.sh scripts/plan-stack.sh`; `python3 -m py_compile scripts/apply-proxmox-ct-features.py scripts/ensure-openwrt-dns.py scripts/ensure-openwrt-firewall.py scripts/render-local-tfvars.py scripts/validate-inventory.py tests/test_render_local_tfvars.py`
- limitacoes / pontos nao validados: nao foi corrido `terraform init/validate/plan` porque dependem de toolchain/credenciais/paths locais externos; as provas operacionais citadas no README continuam marcadas com data e devem ser lidas como historicas
- resultado final: parcialmente alinhadas
