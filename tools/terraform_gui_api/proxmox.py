from __future__ import annotations

import json
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


FALSE_VALUES = {"0", "false", "no", "off", ""}
PLACEHOLDERS = {
    "REPLACE_ME",
    "<proxmox-api-url>",
    "<proxmox-user@realm!token-name>",
    "<proxmox-api-token-id>",
    "<proxmox-api-token-secret>",
}


@dataclass(frozen=True)
class ProxmoxCredentials:
    api_url: str
    token_id: str
    token_secret: str
    tls_insecure: bool


def _parse_tfvars(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".json":
        payload = json.loads(text)
        return payload if isinstance(payload, dict) else {}

    values: dict[str, Any] = {}
    pattern = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*(?:#.*)?$')
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = pattern.match(raw_line)
        if not match:
            continue
        key = match.group(1)
        value_text = match.group(2).strip()
        if value_text in {"true", "false"}:
            values[key] = value_text == "true"
        elif re.fullmatch(r"-?\d+", value_text):
            values[key] = int(value_text)
        elif value_text.startswith('"') and value_text.endswith('"'):
            values[key] = json.loads(value_text)
        else:
            values[key] = value_text
    return values


def load_proxmox_credentials(repo_root: Path, environment: str) -> tuple[ProxmoxCredentials | None, str | None]:
    env_dir = repo_root / "env" / environment
    candidates = [
        env_dir / "proxmox-base.tfvars.json",
        env_dir / "proxmox-base.tfvars",
    ]

    for path in candidates:
        if not path.exists():
            continue
        payload = _parse_tfvars(path)
        api_url = str(payload.get("proxmox_api_url") or "").strip()
        token_id = str(payload.get("proxmox_api_token_id") or "").strip()
        token_secret = str(payload.get("proxmox_api_token") or "").strip()
        tls_insecure = bool(payload.get("proxmox_tls_insecure", True))
        if api_url in PLACEHOLDERS or token_id in PLACEHOLDERS or token_secret in PLACEHOLDERS:
            continue
        if api_url and token_id and token_secret:
            return (
                ProxmoxCredentials(
                    api_url=api_url,
                    token_id=token_id,
                    token_secret=token_secret,
                    tls_insecure=tls_insecure,
                ),
                None,
            )

    return None, f"Missing env/{environment}/proxmox-base.tfvars(.json) with non-placeholder Proxmox credentials."


def _make_context(tls_insecure: bool) -> ssl.SSLContext | None:
    if not tls_insecure:
        return None
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def api_request(
    credentials: ProxmoxCredentials,
    method: str,
    path: str,
    data: dict[str, str] | None = None,
) -> Any:
    url = f"{credentials.api_url.rstrip('/')}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"PVEAPIToken={credentials.token_id}={credentials.token_secret}",
    }
    payload = None
    if data is not None:
        payload = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    request = urllib.request.Request(url, method=method, headers=headers, data=payload)
    try:
        with urllib.request.urlopen(request, context=_make_context(credentials.tls_insecure), timeout=30) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Proxmox API {method} {url} failed with HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Proxmox API {method} {url} failed: {exc.reason}") from exc

    if not body:
        return {}
    return json.loads(body)


def list_real_workloads(credentials: ProxmoxCredentials) -> list[dict[str, Any]]:
    response = api_request(credentials, "GET", "/cluster/resources?type=vm")
    resources = response.get("data", [])
    items: list[dict[str, Any]] = []
    for item in resources:
        if not isinstance(item, dict):
            continue
        resource_type = item.get("type")
        if resource_type not in {"lxc", "qemu"}:
            continue
        items.append(
            {
                "kind": "ct" if resource_type == "lxc" else "vm",
                "vmid": item.get("vmid"),
                "name": item.get("name"),
                "node": item.get("node"),
                "status": item.get("status"),
                "resource": item,
            }
        )
    return sorted(items, key=lambda item: (str(item.get("kind")), int(item.get("vmid") or 0), str(item.get("name") or "")))


def get_real_workload_detail(
    credentials: ProxmoxCredentials,
    *,
    node: str,
    vmid: int,
    kind: str,
) -> dict[str, Any]:
    resource_kind = "lxc" if kind == "ct" else "qemu"
    quoted_node = urllib.parse.quote(node, safe="")
    config = api_request(credentials, "GET", f"/nodes/{quoted_node}/{resource_kind}/{vmid}/config").get("data", {})
    status = api_request(credentials, "GET", f"/nodes/{quoted_node}/{resource_kind}/{vmid}/status/current").get("data", {})
    return {
        "kind": kind,
        "vmid": vmid,
        "node": node,
        "config": config,
        "status": status,
    }
