from __future__ import annotations

import argparse
import json
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
    validate_document,
    workload_file_path,
    write_workload_file,
)
from .proxmox import get_real_workload_detail, list_real_workloads, load_proxmox_credentials
from .terraform_ops import run_apply, run_plan


REPO_ROOT = Path(__file__).resolve().parents[2]


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
            if parsed.path == "/api/state":
                environment = _get_environment(self)
                drafts = runtime.load_drafts(REPO_ROOT, environment)
                real_items, real_map, real_error = _load_real_state(environment)
                payload = build_state_payload(REPO_ROOT, environment, drafts, real_items, real_map, real_error)
                payload["branch"] = git_current_branch(REPO_ROOT)
                _json(self, HTTPStatus.OK, payload)
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

            if parsed.path == "/api/terraform/plan":
                result = run_plan(REPO_ROOT, environment)
                status = HTTPStatus.OK if result["exit_code"] == 0 else HTTPStatus.BAD_GATEWAY
                _json(self, status, result)
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
                status = HTTPStatus.OK if result["exit_code"] == 0 else HTTPStatus.BAD_GATEWAY
                _json(self, status, result)
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
