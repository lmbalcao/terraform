from __future__ import annotations

import argparse
import json
import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from . import runtime
from .inventory import (
    apply_drafts_to_document,
    build_state_payload,
    build_workload_template,
    compare_states,
    discover_environments,
    git_current_branch,
    git_local_branches,
    git_switch_branch,
    load_environment_document,
    load_inventory_node_names,
    validate_document,
    workload_file_path,
    write_workload_file,
)
from .proxmox import (
    TFVARS_FIELDS,
    get_real_workload_detail,
    list_bridges,
    list_nodes,
    list_node_storages,
    list_node_templates,
    list_real_workloads,
    load_proxmox_credentials,
    load_proxmox_tfvars,
    set_workload_status,
    write_proxmox_tfvars,
)
from .terraform_ops import run_apply, run_plan


REPO_ROOT = Path(__file__).resolve().parents[2]

# ── Docker apps helpers ───────────────────────────────────────────────────────

_DOCKER_REPO_SKIP = {"legacy", "scripts", "docs", "terraform", "terraform-gui"}


def _find_docker_repo(repo_root: Path) -> Path | None:
    candidates = [
        Path("/tmp/docker-repo"),           # colocado pelo dev-install.sh após fresh install
        Path("/opt/docker-repo"),           # alternativa persistente (clone manual)
        repo_root.parent / "docker",          # workspace de dev local (irmão do repo terraform)
        repo_root.parent / "docker-repo",
    ]
    for path in candidates:
        if path.is_dir():
            return path
    return None


def _list_apps(repo_root: Path) -> list[str]:
    docker_repo = _find_docker_repo(repo_root)
    if docker_repo is None:
        return []
    apps = []
    for item in sorted(docker_repo.iterdir()):
        if not item.is_dir() or item.name.startswith(".") or item.name in _DOCKER_REPO_SKIP:
            continue
        if (item / "docker-compose.yml").exists() or (item / "docker-compose.yaml").exists():
            apps.append(item.name)
    return apps


def _parse_compose_text(text: str) -> list[dict[str, Any]]:
    """Extract services with exposed ports and PUID/PGID from docker-compose text."""
    services: list[dict[str, Any]] = []
    current_svc: dict[str, Any] | None = None
    section: str | None = None
    svc_indent: int | None = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(stripped)

        # Detect start of top-level services block
        if re.match(r"^services\s*:", stripped) and indent == 0:
            svc_indent = None
            continue

        # First service entry determines the service-level indent
        if svc_indent is None:
            m = re.match(r"^([a-zA-Z][a-zA-Z0-9_-]*)\s*:\s*$", stripped)
            if m and indent > 0:
                svc_indent = indent
                current_svc = {"name": m.group(1), "ports": [], "uid": None, "gid": None}
                services.append(current_svc)
                section = None
            continue

        if indent == svc_indent:
            # New sibling service
            m = re.match(r"^([a-zA-Z][a-zA-Z0-9_-]*)\s*:\s*$", stripped)
            if m:
                current_svc = {"name": m.group(1), "ports": [], "uid": None, "gid": None}
                services.append(current_svc)
                section = None
            elif indent < svc_indent:
                current_svc = None
                section = None
            continue

        if current_svc is None or indent <= svc_indent:
            continue

        # Section headers one level below service
        if indent == svc_indent + 2 or indent == svc_indent + 4:
            if re.match(r"^ports\s*:", stripped):
                section = "ports"
                continue
            if re.match(r"^environment\s*:", stripped):
                section = "environment"
                continue
            if re.match(r"^[a-zA-Z][a-zA-Z0-9_]*\s*:", stripped):
                section = None
                continue

        if section == "ports" and stripped.startswith("-"):
            port_str = stripped[1:].strip().strip("\"'")
            m = re.match(r"^(?:[^:]+:)?(\d+):(\d+)", port_str)
            if m:
                current_svc["ports"].append({"host": int(m.group(1)), "container": int(m.group(2))})

        elif section == "environment":
            # dict format: KEY: VALUE
            m = re.match(r"^(PUID|PGID)\s*:\s*(\d+)", stripped)
            if m:
                key, val = m.group(1), int(m.group(2))
                current_svc["uid" if key == "PUID" else "gid"] = val
            # list format: - KEY=VALUE
            m = re.match(r"^-\s+(PUID|PGID)=(\d+)", stripped)
            if m:
                key, val = m.group(1), int(m.group(2))
                current_svc["uid" if key == "PUID" else "gid"] = val

    return [s for s in services if s["ports"]]


def _get_app_compose(repo_root: Path, app_name: str) -> dict[str, Any] | None:
    docker_repo = _find_docker_repo(repo_root)
    if docker_repo is None:
        return None
    app_dir = docker_repo / app_name
    if not app_dir.is_dir():
        return None
    compose_path = app_dir / "docker-compose.yml"
    if not compose_path.exists():
        compose_path = app_dir / "docker-compose.yaml"
    if not compose_path.exists():
        return None
    text = compose_path.read_text(encoding="utf-8", errors="replace")
    services = _parse_compose_text(text)
    uid = next((s["uid"] for s in services if s.get("uid") is not None), None)
    gid = next((s["gid"] for s in services if s.get("gid") is not None), None)
    return {"app": app_name, "services": services, "uid": uid, "gid": gid}


def _json(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return {}
    raw = handler.rfile.read(length).decode("utf-8")
    return json.loads(raw) if raw.strip() else {}


def _query(handler: BaseHTTPRequestHandler) -> dict[str, list[str]]:
    return parse_qs(urlparse(handler.path).query)


def _get_environment(handler: BaseHTTPRequestHandler, body: dict[str, Any] | None = None) -> str:
    body = body or {}
    query = _query(handler)
    environment = str(body.get("environment") or query.get("environment", [""])[0]).strip()
    if environment:
        return environment
    environments = discover_environments(REPO_ROOT)
    if not environments:
        raise RuntimeError("No inventory environments discovered.")
    return environments[0]


def _draft_key(draft: dict[str, Any]) -> tuple[str, str]:
    return str(draft["kind"]), str(draft["name"])


def _upsert_draft(drafts: list[dict[str, Any]], draft: dict[str, Any]) -> list[dict[str, Any]]:
    filtered = [item for item in drafts if _draft_key(item) != _draft_key(draft)]
    filtered.append(draft)
    return sorted(filtered, key=lambda item: (str(item["kind"]), str(item["name"])))


def _load_real_state(environment: str) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], str | None]:
    credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
    if credentials is None:
        return [], {}, error

    try:
        real_items = list_real_workloads(credentials)
        detail_map: dict[str, dict[str, Any]] = {}
        for item in real_items:
            detail_map[f"{item['kind']}:{item['name']}"] = get_real_workload_detail(
                credentials,
                node=str(item["node"]),
                vmid=int(item["vmid"]),
                kind=str(item["kind"]),
            )
        return real_items, detail_map, None
    except Exception as exc:
        return [], {}, str(exc)


class Handler(BaseHTTPRequestHandler):
    server_version = "terraform-gui-api/0.1"

    def log_message(self, format: str, *args: Any) -> None:
        return

    def do_OPTIONS(self) -> None:
        _json(self, HTTPStatus.NO_CONTENT, {})

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        try:
            if parsed.path == "/api/health":
                _json(self, HTTPStatus.OK, {"ok": True})
                return
            if parsed.path == "/api/environments":
                _json(self, HTTPStatus.OK, {"environments": discover_environments(REPO_ROOT)})
                return
            if parsed.path == "/api/branches":
                _json(self, HTTPStatus.OK, {"branches": git_local_branches(REPO_ROOT)})
                return
            if parsed.path == "/api/branch/current":
                _json(self, HTTPStatus.OK, {"branch": git_current_branch(REPO_ROOT)})
                return
            if parsed.path == "/api/drafts":
                environment = _get_environment(self)
                _json(self, HTTPStatus.OK, {"environment": environment, "drafts": runtime.load_drafts(REPO_ROOT, environment)})
                return
            if parsed.path == "/api/workloads/template":
                environment = _get_environment(self)
                kind = parse_qs(parsed.query).get("kind", ["ct"])[0]
                document = load_environment_document(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"environment": environment, "kind": kind, "workload": build_workload_template(document, kind)})
                return
            if parsed.path == "/api/workloads/detail":
                environment = _get_environment(self)
                kind = parse_qs(parsed.query).get("kind", [""])[0]
                name = parse_qs(parsed.query).get("name", [""])[0]
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                real_items, real_map, real_error = _load_real_state(environment)
                payload = build_state_payload(REPO_ROOT, environment, drafts, real_items, real_map, real_error)
                row = next((item for item in payload["rows"] if item["kind"] == kind and item["name"] == name), None)
                if row is None:
                    _json(self, HTTPStatus.NOT_FOUND, {"error": f"Workload not found: {kind}/{name}"})
                    return
                _json(self, HTTPStatus.OK, row)
                return
            if parsed.path == "/api/proxmox/nodes":
                environment = _get_environment(self)

                # Always load inventory nodes (available without Proxmox credentials)
                inv_names = load_inventory_node_names(REPO_ROOT, environment)
                inv_nodes = [{"node": n, "status": "inventory"} for n in inv_names]

                credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
                if credentials is None:
                    # Return inventory nodes so the form dropdown is still populated
                    _json(self, HTTPStatus.OK, {"nodes": inv_nodes, "warning": error})
                    return

                # Merge live Proxmox nodes with inventory-only nodes
                try:
                    live_nodes = list_nodes(credentials)
                    live_names = {n["node"] for n in live_nodes}
                    extra = [n for n in inv_nodes if n["node"] not in live_names]
                    merged = sorted(live_nodes + extra, key=lambda x: x["node"])
                    _json(self, HTTPStatus.OK, {"nodes": merged})
                except Exception as exc:
                    # Live API failed — fall back to inventory-only nodes
                    _json(self, HTTPStatus.OK, {"nodes": inv_nodes, "warning": str(exc)})
                return
            if parsed.path == "/api/proxmox/bridges":
                environment = _get_environment(self)
                credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
                if credentials is None:
                    _json(self, HTTPStatus.OK, {"bridges": [], "warning": error})
                    return
                try:
                    _json(self, HTTPStatus.OK, {"bridges": list_bridges(credentials)})
                except Exception as exc:
                    _json(self, HTTPStatus.OK, {"bridges": [], "warning": str(exc)})
                return
            if parsed.path == "/api/proxmox/storages":
                environment = _get_environment(self)
                node = parse_qs(parsed.query).get("node", [""])[0].strip()
                if not node:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `node` query param.", "storages": []})
                    return
                credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
                if credentials is None:
                    _json(self, HTTPStatus.SERVICE_UNAVAILABLE, {"error": error, "storages": []})
                    return
                _json(self, HTTPStatus.OK, {"node": node, "storages": list_node_storages(credentials, node)})
                return
            if parsed.path == "/api/proxmox/templates":
                environment = _get_environment(self)
                node = parse_qs(parsed.query).get("node", [""])[0].strip()
                storage = parse_qs(parsed.query).get("storage", [""])[0].strip()
                if not node or not storage:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `node` or `storage` query params.", "templates": []})
                    return
                credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
                if credentials is None:
                    _json(self, HTTPStatus.SERVICE_UNAVAILABLE, {"error": error, "templates": []})
                    return
                _json(self, HTTPStatus.OK, {"node": node, "storage": storage, "templates": list_node_templates(credentials, node, storage)})
                return
            if parsed.path == "/api/networks":
                environment = _get_environment(self)
                document = load_environment_document(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"environment": environment, "networks": document.get("networks", {})})
                return
            if parsed.path == "/api/traefik-instances":
                environment = _get_environment(self)
                document = load_environment_document(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"environment": environment, "instances": document.get("ingress", {})})
                return
            if parsed.path == "/api/terraform-pubkey":
                import os, subprocess
                container = os.environ.get("TERRAFORM_CONTAINER", "").strip()
                key_path = "/terraform/config/id_ed25519"
                cmd = (["docker", "exec", container, "ssh-keygen", "-y", "-f", key_path]
                       if container else ["ssh-keygen", "-y", "-f", key_path])
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=10)
                    pubkey = result.stdout.strip()
                    _json(self, HTTPStatus.OK, {"pubkey": pubkey})
                except Exception as exc:
                    _json(self, HTTPStatus.OK, {"pubkey": None, "error": str(exc)})
                return
            if parsed.path == "/api/apps/list":
                _json(self, HTTPStatus.OK, {"apps": _list_apps(REPO_ROOT)})
                return
            if parsed.path == "/api/apps/compose":
                app_name = parse_qs(parsed.query).get("app", [""])[0].strip()
                if not app_name:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `app` query param."})
                    return
                result = _get_app_compose(REPO_ROOT, app_name)
                if result is None:
                    _json(self, HTTPStatus.NOT_FOUND, {"error": f"App not found or no docker-compose.yml: {app_name}"})
                    return
                _json(self, HTTPStatus.OK, result)
                return
            if parsed.path == "/api/state":
                environment = _get_environment(self)
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                real_items, real_map, real_error = _load_real_state(environment)
                payload = build_state_payload(REPO_ROOT, environment, drafts, real_items, real_map, real_error)
                payload["branch"] = git_current_branch(REPO_ROOT)
                _json(self, HTTPStatus.OK, payload)
                return
            if parsed.path == "/api/settings/tfvars":
                environment = _get_environment(self)
                values = load_proxmox_tfvars(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"environment": environment, "fields": TFVARS_FIELDS, "values": values})
                return

            _json(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown path: {parsed.path}"})
        except (Exception, SystemExit) as exc:
            _json(self, HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        try:
            body = _read_json(self)
            if parsed.path == "/api/branch/select":
                branch = str(body.get("branch") or "").strip()
                if not branch:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `branch`."})
                    return
                if branch not in git_local_branches(REPO_ROOT):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": f"Branch does not exist locally: {branch}"})
                    return
                ok, output = git_switch_branch(REPO_ROOT, branch)
                if not ok:
                    _json(self, HTTPStatus.CONFLICT, {"error": output or f"Unable to switch branch to {branch}"})
                    return
                runtime.clear_all_drafts(REPO_ROOT)
                _json(self, HTTPStatus.OK, {"branch": git_current_branch(REPO_ROOT), "drafts_cleared": True})
                return

            environment = _get_environment(self, body)

            if parsed.path == "/api/workloads/validate":
                draft = body.get("draft")
                if not isinstance(draft, dict):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `draft` object."})
                    return
                document = load_environment_document(REPO_ROOT, environment)
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                candidate = apply_drafts_to_document(document, _upsert_draft(drafts, draft))
                errors = validate_document(REPO_ROOT, candidate, environment)
                _json(self, HTTPStatus.OK, {"valid": not errors, "errors": errors})
                return

            if parsed.path == "/api/workloads/draft":
                draft = body.get("draft")
                if not isinstance(draft, dict):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `draft` object."})
                    return
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                drafts = _upsert_draft(drafts, draft)
                runtime.save_drafts(REPO_ROOT, environment, drafts)
                _json(self, HTTPStatus.OK, {"environment": environment, "drafts": drafts})
                return

            if parsed.path == "/api/workloads/draft/delete":
                kind = str(body.get("kind") or "").strip()
                name = str(body.get("name") or "").strip()
                original_name = str(body.get("original_name") or name).strip()
                if not kind or not name:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `kind` or `name`."})
                    return
                draft = {
                    "environment": environment,
                    "kind": kind,
                    "name": name,
                    "original_name": original_name,
                    "operation": "delete",
                }
                drafts = _upsert_draft(runtime.load_drafts(REPO_ROOT, environment), draft)
                runtime.save_drafts(REPO_ROOT, environment, drafts)
                _json(self, HTTPStatus.OK, {"environment": environment, "drafts": drafts})
                return

            if parsed.path == "/api/workloads/draft/enabled":
                kind = str(body.get("kind") or "").strip()
                name = str(body.get("name") or "").strip()
                enabled = body.get("enabled")
                if not kind or not name or not isinstance(enabled, bool):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `kind`, `name` or boolean `enabled`."})
                    return
                document = load_environment_document(REPO_ROOT, environment)
                draft_document = apply_drafts_to_document(document, runtime.load_drafts(REPO_ROOT, environment))
                collection = draft_document["cts" if kind == "ct" else "vms"]
                if name not in collection:
                    _json(self, HTTPStatus.NOT_FOUND, {"error": f"Workload not found: {kind}/{name}"})
                    return
                workload = collection[name]
                workload["enabled"] = enabled
                draft = {
                    "environment": environment,
                    "kind": kind,
                    "name": name,
                    "original_name": name,
                    "operation": "upsert",
                    "workload": workload,
                }
                drafts = _upsert_draft(runtime.load_drafts(REPO_ROOT, environment), draft)
                runtime.save_drafts(REPO_ROOT, environment, drafts)
                _json(self, HTTPStatus.OK, {"environment": environment, "drafts": drafts})
                return

            if parsed.path == "/api/drafts/clear":
                runtime.save_drafts(REPO_ROOT, environment, [])
                _json(self, HTTPStatus.OK, {"environment": environment, "drafts": []})
                return

            if parsed.path == "/api/workloads/save":
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                document = load_environment_document(REPO_ROOT, environment)
                candidate = apply_drafts_to_document(document, drafts)
                errors = validate_document(REPO_ROOT, candidate, environment)
                if errors:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Validation failed.", "errors": errors})
                    return

                for draft in drafts:
                    kind = draft["kind"]
                    original_name = draft.get("original_name") or draft["name"]
                    original_path = workload_file_path(REPO_ROOT, environment, kind, original_name)
                    if draft.get("operation") == "delete":
                        if original_path.exists():
                            original_path.unlink()
                        continue

                    workload = draft["workload"]
                    target_name = workload["name"]
                    target_path = workload_file_path(REPO_ROOT, environment, kind, target_name)
                    write_workload_file(target_path, workload)
                    if original_name != target_name and original_path.exists():
                        original_path.unlink()

                runtime.clear_drafts(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"saved": True, "environment": environment})
                return

            if parsed.path == "/api/proxmox/action":
                kind = str(body.get("kind") or "").strip()
                name = str(body.get("name") or "").strip()
                action = str(body.get("action") or "").strip()
                if not kind or not name or action not in ("start", "stop"):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing/invalid `kind`, `name`, or `action` (start|stop)."})
                    return
                credentials, error = load_proxmox_credentials(REPO_ROOT, environment)
                if credentials is None:
                    _json(self, HTTPStatus.SERVICE_UNAVAILABLE, {"error": error})
                    return
                document = load_environment_document(REPO_ROOT, environment)
                draft_document = apply_drafts_to_document(document, runtime.load_drafts(REPO_ROOT, environment))
                collection = draft_document["cts" if kind == "ct" else "vms"]
                if name not in collection:
                    _json(self, HTTPStatus.NOT_FOUND, {"error": f"Workload not found: {kind}/{name}"})
                    return
                workload = collection[name]
                vmid = workload.get("vmid")
                node = workload.get("node")
                if not vmid or not node:
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": f"Workload '{name}' has no vmid or node configured."})
                    return
                result = set_workload_status(credentials, node=str(node), vmid=int(vmid), kind=kind, action=action)
                _json(self, HTTPStatus.OK, {"ok": True, "action": action, "name": name, "vmid": vmid, "node": node})
                return
            if parsed.path == "/api/terraform/plan":
                result = run_plan(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, result)
                return

            if parsed.path == "/api/terraform/apply":
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                if drafts:
                    _json(
                        self,
                        HTTPStatus.CONFLICT,
                        {"error": "Apply blocked: there are pending unsaved drafts.", "draft_count": len(drafts)},
                    )
                    return
                result = run_apply(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, result)
                return

            if parsed.path == "/api/settings/tfvars":
                values = body.get("values")
                if not isinstance(values, dict):
                    _json(self, HTTPStatus.BAD_REQUEST, {"error": "Missing `values` object."})
                    return
                write_proxmox_tfvars(REPO_ROOT, environment, values)
                saved = load_proxmox_tfvars(REPO_ROOT, environment)
                _json(self, HTTPStatus.OK, {"saved": True, "environment": environment, "values": saved})
                return

            _json(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown path: {parsed.path}"})
        except (Exception, SystemExit) as exc:
            _json(self, HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Minimal HTTP bridge for terraform-gui.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(json.dumps({"host": args.host, "port": args.port, "repo_root": str(REPO_ROOT)}))
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
