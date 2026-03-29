from __future__ import annotations

import copy
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def load_validate_inventory_module(repo_root: Path) -> Any:
    module_path = repo_root / "scripts" / "validate-inventory.py"
    spec = importlib.util.spec_from_file_location("validate_inventory_bridge", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load inventory helpers from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def discover_environments(repo_root: Path) -> list[str]:
    module = load_validate_inventory_module(repo_root)
    return module.discover_environments(repo_root / "inventory")


def load_environment_document(repo_root: Path, environment: str) -> dict[str, Any]:
    module = load_validate_inventory_module(repo_root)
    return module.load_environment(repo_root / "inventory", environment)


def validate_document(repo_root: Path, document: dict[str, Any], environment: str) -> list[str]:
    module = load_validate_inventory_module(repo_root)
    return module.validate_environment_document(document, environment)


def git_current_branch(repo_root: Path) -> str:
    completed = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def git_local_branches(repo_root: Path) -> list[str]:
    completed = subprocess.run(
        ["git", "branch", "--format=%(refname:short)"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def git_switch_branch(repo_root: Path, branch: str) -> tuple[bool, str]:
    completed = subprocess.run(
        ["git", "switch", "--quiet", branch],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    output = ((completed.stdout or "") + (completed.stderr or "")).strip()
    return completed.returncode == 0, output


def workload_file_path(repo_root: Path, environment: str, kind: str, name: str) -> Path:
    directory = "cts" if kind == "ct" else "vms"
    return repo_root / "inventory" / environment / directory / f"{name}.yaml"


def build_workload_template(document: dict[str, Any], kind: str) -> dict[str, Any]:
    defaults = document.get("defaults", {})
    nodes = sorted(document.get("nodes", {}).keys())
    networks = sorted(document.get("networks", {}).keys())
    common_defaults = copy.deepcopy(defaults.get("common", {}))
    kind_defaults = copy.deepcopy(defaults.get(kind, {}))

    base: dict[str, Any] = {
        "version": 1,
        "kind": kind,
        "enabled": kind_defaults.get("enabled", True),
        "vmid": None,
        "name": "",
        "node": nodes[0] if nodes else "",
        "tags": common_defaults.get("tags", []),
        "network": {
            "segment": networks[0] if networks else "",
            "mode": "dhcp",
        },
        "resources": {
            "cpu_cores": None,
            "memory_mb": None,
        },
        "boot": copy.deepcopy(kind_defaults.get("boot", {})),
        "storage": {
            "rootfs_storage": "",
            "rootfs_size_gb": None,
        },
        "services": common_defaults.get("services", []),
        "operations": common_defaults.get(
            "operations",
            {"ansible_enabled": False, "backup_policy": None, "bootstrap_profile": None},
        ),
    }

    if kind == "ct":
        base["hostname"] = ""
        base["resources"]["swap_mb"] = kind_defaults.get("resources", {}).get("swap_mb")
        base["lxc"] = copy.deepcopy(
            kind_defaults.get(
                "lxc",
                {"unprivileged": True, "features": {"nesting": True}, "features_manual": {}, "mounts": []},
            )
        )
    else:
        base["resources"]["cpu_sockets"] = None
        base["qemu"] = copy.deepcopy(
            kind_defaults.get(
                "qemu",
                {"sockets": 1, "agent_enabled": False, "source": {}, "disks": []},
            )
        )

    return base


def apply_drafts_to_document(document: dict[str, Any], drafts: list[dict[str, Any]]) -> dict[str, Any]:
    result = copy.deepcopy(document)
    cts = result.setdefault("cts", {})
    vms = result.setdefault("vms", {})

    for draft in drafts:
        kind = draft["kind"]
        operation = draft.get("operation", "upsert")
        original_name = draft.get("original_name") or draft["name"]
        target = cts if kind == "ct" else vms

        if operation == "delete":
            target.pop(original_name, None)
            continue

        workload = copy.deepcopy(draft["workload"])
        if original_name != workload.get("name"):
            target.pop(original_name, None)
        target[workload["name"]] = workload

    return result


def merge_dicts(*values: dict[str, Any]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for value in values:
        if isinstance(value, dict):
            merged.update(copy.deepcopy(value))
    return merged


def build_effective_workloads(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    defaults = document.get("defaults", {})
    networks = document.get("networks", {})
    common_defaults = defaults.get("common", {})
    effective: dict[str, dict[str, Any]] = {}

    for kind in ("ct", "vm"):
        raw_map = document.get("cts" if kind == "ct" else "vms", {})
        kind_defaults = defaults.get(kind, {})
        kind_key = "lxc" if kind == "ct" else "qemu"
        for name, workload in raw_map.items():
            segment = str(workload.get("network", {}).get("segment") or "")
            network_catalog = copy.deepcopy(networks.get(segment, {}))
            effective_workload = merge_dicts(common_defaults, kind_defaults, workload)
            effective_workload["tags"] = copy.deepcopy(workload.get("tags", common_defaults.get("tags", [])))
            effective_workload["apps"] = copy.deepcopy(workload.get("apps", common_defaults.get("apps", [])))
            effective_workload["services"] = copy.deepcopy(workload.get("services", common_defaults.get("services", [])))
            effective_workload["operations"] = merge_dicts(common_defaults.get("operations", {}), workload.get("operations", {}))
            effective_workload["boot"] = merge_dicts(kind_defaults.get("boot", {}), workload.get("boot", {}))
            effective_workload["resources"] = merge_dicts(kind_defaults.get("resources", {}), workload.get("resources", {}))
            effective_workload["storage"] = merge_dicts(kind_defaults.get("storage", {}), workload.get("storage", {}))
            effective_workload[kind_key] = merge_dicts(kind_defaults.get(kind_key, {}), workload.get(kind_key, {}))
            effective_workload["network"] = merge_dicts(network_catalog, kind_defaults.get("network", {}), workload.get("network", {}))
            effective_workload["network"]["bridge"] = workload.get("network", {}).get("bridge", network_catalog.get("bridge"))
            effective_workload["network"]["dns_domain"] = workload.get("network", {}).get("dns_domain", network_catalog.get("dns_domain"))
            effective_workload["network"]["dns_servers"] = copy.deepcopy(
                workload.get("network", {}).get("dns_servers", network_catalog.get("dns_servers", []))
            )
            effective[name] = effective_workload
    return effective


def _parse_size_gb(value: Any) -> int | None:
    if value is None:
        return None
    text = str(value)
    match = re.search(r"size=(\d+)G", text)
    if match:
        return int(match.group(1))
    if re.fullmatch(r"\d+", text):
        return int(text)
    return None


def _parse_proxmox_kv(value: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for token in value.split(","):
        token = token.strip()
        if "=" not in token:
            continue
        key, token_value = token.split("=", 1)
        result[key] = token_value
    return result


def extract_real_comparable(detail: dict[str, Any]) -> dict[str, Any]:
    config = detail.get("config", {})
    status = detail.get("status", {})
    network_raw = str(config.get("net0") or "")
    network_map = _parse_proxmox_kv(network_raw)
    ipconfig_map = _parse_proxmox_kv(str(config.get("ipconfig0") or ""))
    rootfs = str(config.get("rootfs") or "")
    rootfs_storage = rootfs.split(":", 1)[0] if ":" in rootfs else None

    return {
        "name": config.get("hostname") or config.get("name"),
        "node": detail.get("node"),
        "vmid": detail.get("vmid"),
        "status": status.get("status"),
        "tags": sorted([tag for tag in str(config.get("tags") or "").split(";") if tag]),
        "resources": {
            "cpu_cores": config.get("cores"),
            "cpu_sockets": config.get("sockets"),
            "memory_mb": config.get("memory"),
            "swap_mb": config.get("swap"),
        },
        "boot": {
            "on_boot": bool(int(config.get("onboot", 0))) if str(config.get("onboot", "")).isdigit() else config.get("onboot"),
            "start_state": "running" if status.get("status") == "running" else status.get("status"),
        },
        "storage": {
            "rootfs_storage": rootfs_storage,
            "rootfs_size_gb": _parse_size_gb(rootfs),
        },
        "network": {
            "bridge": network_map.get("bridge"),
            "vlan": int(network_map["tag"]) if network_map.get("tag", "").isdigit() else None,
            "address": ipconfig_map.get("ip"),
            "gateway": ipconfig_map.get("gw"),
        },
    }


def extract_declared_comparable(workload: dict[str, Any]) -> dict[str, Any]:
    name = workload.get("hostname") or workload.get("name")
    return {
        "name": name,
        "node": workload.get("node"),
        "vmid": workload.get("vmid"),
        "enabled": workload.get("enabled"),
        "tags": sorted(workload.get("tags", [])),
        "resources": {
            "cpu_cores": workload.get("resources", {}).get("cpu_cores"),
            "cpu_sockets": workload.get("resources", {}).get("cpu_sockets", workload.get("qemu", {}).get("sockets")),
            "memory_mb": workload.get("resources", {}).get("memory_mb"),
            "swap_mb": workload.get("resources", {}).get("swap_mb"),
        },
        "boot": {
            "on_boot": workload.get("boot", {}).get("on_boot"),
            "start_state": workload.get("boot", {}).get("start_state"),
        },
        "storage": {
            "rootfs_storage": workload.get("storage", {}).get("rootfs_storage"),
            "rootfs_size_gb": workload.get("storage", {}).get("rootfs_size_gb"),
        },
        "network": {
            "bridge": workload.get("network", {}).get("bridge"),
            "vlan": workload.get("network", {}).get("vlan"),
            "address": workload.get("network", {}).get("address"),
            "gateway": workload.get("network", {}).get("gateway"),
        },
    }


def compare_states(declared: dict[str, Any] | None, real: dict[str, Any] | None) -> dict[str, Any]:
    if declared is None and real is None:
        return {"status": "unknown", "fields": []}
    if declared is None:
        return {"status": "undeclared_real", "fields": []}
    if real is None:
        return {"status": "missing_real", "fields": []}

    declared_map = extract_declared_comparable(declared)
    real_map = extract_real_comparable(real)
    fields: list[dict[str, Any]] = []
    for section, section_value in declared_map.items():
        real_value = real_map.get(section)
        if isinstance(section_value, dict) and isinstance(real_value, dict):
            for key, value in section_value.items():
                if real_value.get(key) != value:
                    fields.append({"field": f"{section}.{key}", "declared": value, "real": real_value.get(key)})
        elif real_value != section_value:
            fields.append({"field": section, "declared": section_value, "real": real_value})

    return {"status": "drift" if fields else "match", "fields": fields}


def build_state_payload(
    repo_root: Path,
    environment: str,
    drafts: list[dict[str, Any]],
    real_items: list[dict[str, Any]],
    real_detail_map: dict[str, dict[str, Any]],
    real_error: str | None,
) -> dict[str, Any]:
    document = load_environment_document(repo_root, environment)
    declared_with_drafts = apply_drafts_to_document(document, drafts)
    effective = build_effective_workloads(declared_with_drafts)

    declared_items: list[dict[str, Any]] = []
    for kind, collection_name in (("ct", "cts"), ("vm", "vms")):
        collection = declared_with_drafts.get(collection_name, {})
        for name, workload in sorted(collection.items()):
            identifier = f"{kind}:{name}"
            declared_items.append(
                {
                    "id": identifier,
                    "kind": kind,
                    "name": name,
                    "path": str(workload_file_path(repo_root, environment, kind, name).relative_to(repo_root)),
                    "raw": workload,
                    "effective": effective.get(name, workload),
                    "draft": next((draft for draft in drafts if draft["kind"] == kind and draft["name"] == name), None),
                    "real": real_detail_map.get(identifier),
                }
            )

    real_only_items: list[dict[str, Any]] = []
    declared_index = {item["id"]: item for item in declared_items}
    for real_item in real_items:
        identifier = f"{real_item['kind']}:{real_item['name']}"
        if identifier in declared_index:
            continue
        real_only_items.append(
            {
                "id": identifier,
                "kind": real_item["kind"],
                "name": real_item["name"],
                "path": None,
                "raw": None,
                "effective": None,
                "draft": None,
                "real": real_detail_map.get(identifier),
            }
        )

    rows = declared_items + real_only_items
    for row in rows:
        row["comparison"] = compare_states(row.get("effective"), row.get("real"))

    return {
        "environment": environment,
        "draft_count": len(drafts),
        "real_state": {
            "available": real_error is None,
            "error": real_error,
            "count": len(real_items),
        },
        "rows": rows,
        "declared_counts": {
            "cts": len(declared_with_drafts.get("cts", {})),
            "vms": len(declared_with_drafts.get("vms", {})),
        },
    }


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if text == "":
        return '""'
    if re.fullmatch(r"[A-Za-z0-9._/@:-]+", text):
        return text
    return json.dumps(text, ensure_ascii=True)


def dump_yaml(value: Any, indent: int = 0) -> list[str]:
    prefix = " " * indent
    if isinstance(value, dict):
        if not value:
            return [prefix + "{}"]
        lines: list[str] = []
        for key, nested in value.items():
            if isinstance(nested, (dict, list)) and nested:
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml(nested, indent + 2))
            else:
                if isinstance(nested, (dict, list)):
                    rendered = "{}" if isinstance(nested, dict) else "[]"
                else:
                    rendered = yaml_scalar(nested)
                lines.append(f"{prefix}{key}: {rendered}")
        return lines
    if isinstance(value, list):
        if not value:
            return [prefix + "[]"]
        lines = []
        for item in value:
            if isinstance(item, (dict, list)) and item:
                lines.append(f"{prefix}-")
                lines.extend(dump_yaml(item, indent + 2))
            else:
                if isinstance(item, (dict, list)):
                    rendered = "{}" if isinstance(item, dict) else "[]"
                else:
                    rendered = yaml_scalar(item)
                lines.append(f"{prefix}- {rendered}")
        return lines
    return [prefix + yaml_scalar(value)]


def write_workload_file(path: Path, workload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(dump_yaml(workload)) + "\n", encoding="utf-8")
