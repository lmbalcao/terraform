# Terraform GUI API Contract

Base URL local recomendada: `http://127.0.0.1:8765/api`

## Princípios

- O repo `terraform` continua a ser a única source of truth.
- A GUI nunca escreve ficheiros diretamente.
- A GUI só consome JSON e só aciona operações via esta API.
- `apply` é bloqueado quando existem drafts pendentes.

## Endpoints

### `GET /health`

Resposta:

```json
{ "ok": true }
```

### `GET /environments`

Resposta:

```json
{ "environments": ["dev", "prod"] }
```

### `GET /branches`

Lista apenas branches locais existentes.

Resposta:

```json
{ "branches": ["main", "feature-x"] }
```

### `GET /branch/current`

Resposta:

```json
{ "branch": "main" }
```

### `POST /branch/select`

Payload:

```json
{ "branch": "main" }
```

Resposta `200`:

```json
{ "branch": "main", "drafts_cleared": true }
```

Resposta `409`:

```json
{ "error": "git switch failed ..." }
```

### `GET /state?environment=dev`

Devolve numa só chamada:

- branch atual
- contador de drafts
- disponibilidade de estado real Proxmox
- lista declarada raw
- lista declarada efetiva
- detalhe real quando disponível
- comparação simples

Resposta simplificada:

```json
{
  "branch": "main",
  "environment": "dev",
  "draft_count": 0,
  "real_state": {
    "available": false,
    "error": "Missing env/dev/proxmox-base.tfvars(.json) with non-placeholder Proxmox credentials.",
    "count": 0
  },
  "declared_counts": { "cts": 1, "vms": 1 },
  "rows": [
    {
      "id": "ct:wikijs",
      "kind": "ct",
      "name": "wikijs",
      "path": "inventory/dev/cts/wikijs.yaml",
      "raw": {},
      "effective": {},
      "draft": null,
      "real": null,
      "comparison": {
        "status": "missing_real",
        "fields": []
      }
    }
  ]
}
```

### `GET /workloads/detail?environment=dev&kind=ct&name=wikijs`

Resposta:

```json
{
  "id": "ct:wikijs",
  "kind": "ct",
  "name": "wikijs",
  "path": "inventory/dev/cts/wikijs.yaml",
  "raw": {},
  "effective": {},
  "draft": null,
  "real": {
    "kind": "ct",
    "vmid": 6011,
    "node": "dev-proxmox",
    "config": {},
    "status": {}
  },
  "comparison": {
    "status": "drift",
    "fields": [
      { "field": "resources.memory_mb", "declared": 1024, "real": 2048 }
    ]
  }
}
```

### `GET /workloads/template?environment=dev&kind=ct`

Devolve um template mínimo baseado no ambiente real e nos defaults reais do repo.

Resposta:

```json
{
  "environment": "dev",
  "kind": "ct",
  "workload": {
    "version": 1,
    "kind": "ct",
    "enabled": true,
    "vmid": null,
    "name": "",
    "hostname": "",
    "node": "dev-proxmox",
    "network": { "segment": "servicos-externos", "mode": "dhcp" }
  }
}
```

### `GET /drafts?environment=dev`

Resposta:

```json
{
  "environment": "dev",
  "drafts": []
}
```

### `POST /workloads/validate`

Valida um draft no contexto do inventário real do ambiente e dos outros drafts pendentes.

Payload:

```json
{
  "environment": "dev",
  "draft": {
    "environment": "dev",
    "kind": "ct",
    "name": "wikijs",
    "original_name": "wikijs",
    "operation": "upsert",
    "workload": {}
  }
}
```

Resposta:

```json
{
  "valid": false,
  "errors": [
    "dev.cts.wikijs.resources: missing required field `cpu_cores`"
  ]
}
```

### `POST /workloads/draft`

Guarda ou substitui um draft pendente. Não grava no inventário final.

Payload:

```json
{
  "environment": "dev",
  "draft": {
    "environment": "dev",
    "kind": "ct",
    "name": "wikijs",
    "original_name": "wikijs",
    "operation": "upsert",
    "workload": {}
  }
}
```

### `POST /workloads/draft/delete`

Marca um workload para remoção, sem apagar logo o ficheiro.

Payload:

```json
{
  "environment": "dev",
  "kind": "vm",
  "name": "rdtclient",
  "original_name": "rdtclient"
}
```

### `POST /workloads/draft/enabled`

Marca ativo/inativo num draft derivado do estado atual.

Payload:

```json
{
  "environment": "dev",
  "kind": "vm",
  "name": "rdtclient",
  "enabled": true
}
```

### `POST /workloads/save`

Grava todos os drafts pendentes no inventário real do ambiente.

Payload:

```json
{ "environment": "dev" }
```

Resposta `200`:

```json
{ "saved": true, "environment": "dev" }
```

Resposta `400`:

```json
{
  "error": "Validation failed.",
  "errors": ["dev.vms.example: ..."]
}
```

### `POST /terraform/plan`

Payload:

```json
{ "environment": "dev" }
```

Resposta:

```json
{
  "command": ["bash", "scripts/plan-stack.sh", "proxmox-base", "dev", "-no-color"],
  "exit_code": 0,
  "raw_output": "Terraform used the selected providers ...",
  "summary": {
    "status": "changes",
    "add": 1,
    "change": 0,
    "destroy": 0
  }
}
```

### `POST /terraform/apply`

Payload:

```json
{ "environment": "dev" }
```

Se houver drafts pendentes:

```json
{
  "error": "Apply blocked: there are pending unsaved drafts.",
  "draft_count": 2
}
```

Se não houver drafts:

```json
{
  "command": ["bash", "scripts/apply-stack.sh", "proxmox-base", "dev", "-no-color"],
  "exit_code": 0,
  "raw_output": "Apply complete! Resources: 1 added, 0 changed, 0 destroyed.",
  "summary": {
    "status": "applied",
    "add": 1,
    "change": 0,
    "destroy": 0
  }
}
```

