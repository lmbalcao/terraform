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
    "<proxmox-root-password>",
    # Legacy token placeholders kept so old tfvars files with placeholders are
    # still caught rather than silently accepted as real values.
    "<proxmox-user@realm!token-name>",
    "<proxmox-api-token-id>",
    "<proxmox-api-token-secret>",
}


@dataclass(frozen=True)
class ProxmoxCredentials:
    api_url: str
    password: str
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
        elif value_text.startswith("[") and value_text.endswith("]"):
            try:
                # HCL inline list is valid JSON when items are double-quoted strings
                values[key] = json.loads(value_text)
            except json.JSONDecodeError:
                values[key] = value_text
        else:
            values[key] = value_text
    return values


# Fields exposed for editing through the GUI (in display order).
TFVARS_FIELDS = [
    "proxmox_api_url",
    "proxmox_password",
    "proxmox_tls_insecure",
    "root_password",
    "network_bridge",
    "default_search_domain",
    "proxmox_ssh_private_key_path",
    "ssh_public_keys",
]


def load_proxmox_tfvars(repo_root: Path, environment: str) -> dict[str, Any]:
    """Return the full contents of proxmox-base.tfvars for display/editing."""
    env_dir = repo_root / "env" / environment
    for path in (env_dir / "proxmox-base.tfvars", env_dir / "proxmox-base.tfvars.json"):
        if path.exists():
            return _parse_tfvars(path)
    return {}


def write_proxmox_tfvars(repo_root: Path, environment: str, values: dict[str, Any]) -> None:
    """Serialise *values* back to env/{environment}/proxmox-base.tfvars (HCL format)."""
    path = repo_root / "env" / environment / "proxmox-base.tfvars"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    for key in TFVARS_FIELDS:
        if key not in values:
            continue
        value = values[key]
        if value is None or value == "":
            continue
        if isinstance(value, bool):
            lines.append(f"{key} = {'true' if value else 'false'}")
        elif isinstance(value, int):
            lines.append(f"{key} = {value}")
        elif isinstance(value, list):
            items = ", ".join(f'"{v}"' for v in value if v)
            lines.append(f"{key} = [{items}]")
        else:
            lines.append(f'{key} = "{value}"')
    # Preserve any keys not in TFVARS_FIELDS that were already in the file
    existing = _parse_tfvars(path) if path.exists() else {}
    for key, value in existing.items():
        if key in TFVARS_FIELDS or key in values:
            continue
        if isinstance(value, bool):
            lines.append(f"{key} = {'true' if value else 'false'}")
        elif isinstance(value, int):
            lines.append(f"{key} = {value}")
        elif isinstance(value, list):
            items = ", ".join(f'"{v}"' for v in value if v)
            lines.append(f"{key} = [{items}]")
        else:
            lines.append(f'{key} = "{value}"')
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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
        password = str(payload.get("proxmox_password") or "").strip()
        tls_insecure = bool(payload.get("proxmox_tls_insecure", True))
        if api_url in PLACEHOLDERS or password in PLACEHOLDERS:
            continue
        if api_url and password:
            return (
                ProxmoxCredentials(
                    api_url=api_url,
                    password=password,
                    tls_insecure=tls_insecure,
                ),
                None,
            )

    return None, f"Missing env/{environment}/proxmox-base.tfvars(.json) with non-placeholder Proxmox credentials (proxmox_api_url + proxmox_password)."


def _make_context(tls_insecure: bool) -> ssl.SSLContext | None:
    if not tls_insecure:
        return None
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def _api_base(api_url: str) -> str:
    """Return the Proxmox REST API base URL, ensuring the /api2/json prefix is present."""
    base = api_url.rstrip("/")
    if not base.endswith("/api2/json"):
        base = f"{base}/api2/json"
    return base


def _get_ticket(credentials: ProxmoxCredentials) -> tuple[str, str]:
    """Authenticate with root@pam password and return (ticket, csrf_token)."""
    url = f"{_api_base(credentials.api_url)}/access/ticket"
    payload = urllib.parse.urlencode({
        "username": "root@pam",
        "password": credentials.password,
    }).encode("utf-8")
    request = urllib.request.Request(url, method="POST", data=payload, headers={
        "Content-Type": "application/x-www-form-urlencoded",
    })
    try:
        with urllib.request.urlopen(request, context=_make_context(credentials.tls_insecure), timeout=30) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Proxmox ticket auth failed with HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Proxmox ticket auth failed: {exc.reason}") from exc

    data = body.get("data") or {}
    ticket = str(data.get("ticket") or "")
    csrf_token = str(data.get("CSRFPreventionToken") or "")
    if not ticket:
        raise RuntimeError("Proxmox ticket auth succeeded but returned no ticket.")
    return ticket, csrf_token


def api_request(
    credentials: ProxmoxCredentials,
    method: str,
    path: str,
    data: dict[str, str] | None = None,
) -> Any:
    ticket, csrf_token = _get_ticket(credentials)
    url = f"{_api_base(credentials.api_url)}/{path.lstrip('/')}"
    headers = {
        "Cookie": f"PVEAuthCookie={ticket}",
    }
    if method != "GET":
        headers["CSRFPreventionToken"] = csrf_token
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


def list_nodes(credentials: ProxmoxCredentials) -> list[dict[str, Any]]:
    response = api_request(credentials, "GET", "/nodes")
    return sorted(
        [
            {"node": item["node"], "status": item.get("status", "unknown")}
            for item in response.get("data", [])
            if isinstance(item, dict) and item.get("node")
        ],
        key=lambda x: x["node"],
    )


def list_node_storages(credentials: ProxmoxCredentials, node: str) -> list[dict[str, Any]]:
    quoted_node = urllib.parse.quote(node, safe="")
    response = api_request(credentials, "GET", f"/nodes/{quoted_node}/storage")
    result = []
    for item in response.get("data", []):
        if not isinstance(item, dict):
            continue
        content_types = [c.strip() for c in str(item.get("content", "")).split(",") if c.strip()]
        result.append({
            "storage": item.get("storage", ""),
            "type": item.get("type", ""),
            "content": content_types,
            "active": bool(item.get("active", 1)),
            "supports_rootfs": "rootdir" in content_types,
            "supports_templates": "vztmpl" in content_types,
        })
    return sorted(result, key=lambda s: s["storage"])


def list_node_templates(credentials: ProxmoxCredentials, node: str, storage: str) -> list[str]:
    quoted_node = urllib.parse.quote(node, safe="")
    quoted_storage = urllib.parse.quote(storage, safe="")
    response = api_request(credentials, "GET", f"/nodes/{quoted_node}/storage/{quoted_storage}/content?content=vztmpl")
    return sorted(
        item["volid"]
        for item in response.get("data", [])
        if isinstance(item, dict) and item.get("volid")
    )


def set_workload_status(
    credentials: ProxmoxCredentials,
    *,
    node: str,
    vmid: int,
    kind: str,
    action: str,
) -> dict[str, Any]:
    if action not in ("start", "stop"):
        raise ValueError(f"Invalid action: {action!r}. Must be 'start' or 'stop'.")
    resource_kind = "lxc" if kind == "ct" else "qemu"
    quoted_node = urllib.parse.quote(node, safe="")
    return api_request(credentials, "POST", f"/nodes/{quoted_node}/{resource_kind}/{vmid}/status/{action}")


def list_bridges(credentials: ProxmoxCredentials) -> list[str]:
    """Return sorted unique bridge interface names across all Proxmox nodes."""
    nodes = list_nodes(credentials)
    bridges: set[str] = set()
    for node_info in nodes:
        quoted_node = urllib.parse.quote(node_info["node"], safe="")
        try:
            response = api_request(credentials, "GET", f"/nodes/{quoted_node}/network")
            for iface in response.get("data", []):
                if isinstance(iface, dict) and iface.get("type") == "bridge" and iface.get("iface"):
                    bridges.add(iface["iface"])
        except Exception:
            pass
    return sorted(bridges)
