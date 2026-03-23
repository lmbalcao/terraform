#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ParsedLine:
    indent: int
    content: str
    lineno: int


class YamlLiteError(ValueError):
    pass


def strip_inline_comment(line: str) -> str:
    in_single = False
    in_double = False
    result: list[str] = []
    single_quote = chr(39)

    for char in line:
        if char == single_quote and not in_double:
            in_single = not in_single
        elif char == chr(34) and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            break
        result.append(char)

    return "".join(result).rstrip()


def tokenize(text: str) -> list[ParsedLine]:
    lines: list[ParsedLine] = []
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        cleaned = strip_inline_comment(raw_line)
        if not cleaned.strip():
            continue

        indent = len(cleaned) - len(cleaned.lstrip(" "))
        if indent % 2 != 0:
            raise YamlLiteError(f"Invalid indentation at line {lineno}: use multiples of two spaces.")

        lines.append(ParsedLine(indent=indent, content=cleaned.strip(), lineno=lineno))
    return lines


def parse_scalar(text: str) -> Any:
    single_quote = chr(39)
    double_quote = chr(34)

    if text in {"null", "~"}:
        return None
    if text == "true":
        return True
    if text == "false":
        return False
    if text == "[]":
        return []
    if text == "{}":
        return {}
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    if (text.startswith(double_quote) and text.endswith(double_quote)) or (
        text.startswith(single_quote) and text.endswith(single_quote)
    ):
        return text[1:-1]
    return text


def parse_key_value(content: str, lineno: int) -> tuple[str, str]:
    key, separator, value = content.partition(":")
    if not separator or not key.strip():
        raise YamlLiteError(f"Invalid mapping entry at line {lineno}: {content}")
    return key.strip(), value.strip()


def is_inline_mapping(text: str) -> bool:
    return re.match(r"^[A-Za-z0-9_.-]+\s*:(?:\s.*)?$", text) is not None


def parse_block(lines: list[ParsedLine], index: int, indent: int) -> tuple[Any, int]:
    if index >= len(lines):
        return {}, index

    current = lines[index]
    if current.indent < indent:
        return {}, index
    if current.indent != indent:
        raise YamlLiteError(
            f"Unexpected indentation at line {current.lineno}: expected {indent} spaces, got {current.indent}."
        )

    if current.content.startswith("- "):
        return parse_list(lines, index, indent)
    return parse_mapping(lines, index, indent)


def parse_mapping(lines: list[ParsedLine], index: int, indent: int) -> tuple[dict[str, Any], int]:
    mapping: dict[str, Any] = {}

    while index < len(lines):
        current = lines[index]
        if current.indent < indent:
            break
        if current.indent != indent:
            raise YamlLiteError(
                f"Unexpected indentation at line {current.lineno}: expected {indent} spaces, got {current.indent}."
            )
        if current.content.startswith("- "):
            raise YamlLiteError(f"Unexpected list item at line {current.lineno} inside mapping block.")

        key, value_text = parse_key_value(current.content, current.lineno)
        index += 1

        if value_text == "":
            if index < len(lines) and lines[index].indent > indent:
                value, index = parse_block(lines, index, lines[index].indent)
            else:
                value = {}
        else:
            value = parse_scalar(value_text)

        mapping[key] = value

    return mapping, index


def parse_list(lines: list[ParsedLine], index: int, indent: int) -> tuple[list[Any], int]:
    items: list[Any] = []

    while index < len(lines):
        current = lines[index]
        if current.indent < indent:
            break
        if current.indent != indent:
            raise YamlLiteError(
                f"Unexpected indentation at line {current.lineno}: expected {indent} spaces, got {current.indent}."
            )
        if not current.content.startswith("- "):
            break

        remainder = current.content[2:].strip()
        index += 1

        if remainder == "":
            if index < len(lines) and lines[index].indent > indent:
                item, index = parse_block(lines, index, lines[index].indent)
            else:
                item = None
            items.append(item)
            continue

        if is_inline_mapping(remainder):
            key, value_text = parse_key_value(remainder, current.lineno)
            item_map: dict[str, Any] = {}
            if value_text == "":
                if index < len(lines) and lines[index].indent > indent:
                    child, index = parse_block(lines, index, lines[index].indent)
                else:
                    child = {}
                item_map[key] = child
            else:
                item_map[key] = parse_scalar(value_text)

            if index < len(lines) and lines[index].indent > indent:
                child, index = parse_block(lines, index, lines[index].indent)
                if not isinstance(child, dict):
                    raise YamlLiteError(
                        f"Expected mapping continuation for list item declared at line {current.lineno}."
                    )
                overlap = set(item_map).intersection(child)
                if overlap:
                    overlap_text = ", ".join(sorted(overlap))
                    raise YamlLiteError(
                        f"Duplicate keys in list item declared at line {current.lineno}: {overlap_text}."
                    )
                item_map.update(child)
            items.append(item_map)
            continue

        if index < len(lines) and lines[index].indent > indent:
            raise YamlLiteError(
                f"Scalar list item at line {current.lineno} cannot have a nested block."
            )
        items.append(parse_scalar(remainder))

    return items, index


def load_yaml_like(path: Path) -> dict[str, Any]:
    lines = tokenize(path.read_text(encoding="utf-8"))
    if not lines:
        return {}

    document, index = parse_block(lines, 0, lines[0].indent)
    if index != len(lines):
        current = lines[index]
        raise SystemExit(f"Unexpected trailing content in {path} at line {current.lineno}.")
    if not isinstance(document, dict):
        raise SystemExit(f"Expected a mapping document in {path}.")
    return document


def discover_environments(inventory_root: Path) -> list[str]:
    environments: list[str] = []
    for child in sorted(inventory_root.iterdir()):
        if child.is_dir() and (child / "defaults.yaml").exists():
            environments.append(child.name)
    return environments


def load_workload_directory(directory: Path, expected_kind: str) -> dict[str, dict[str, Any]]:
    documents: dict[str, dict[str, Any]] = {}
    if not directory.exists():
        return documents

    for path in sorted(directory.glob("*.yaml")):
        document = load_yaml_like(path)
        name = document.get("name")
        if not name:
            raise SystemExit(f"Missing `name` in {path}.")
        if path.stem != name:
            raise SystemExit(f"Filename mismatch in {path}: expected {name}.yaml.")
        kind_value = document.get("kind")
        if kind_value != expected_kind:
            raise SystemExit(
                f"Invalid `kind` in {path}: expected {expected_kind!r}, got {kind_value!r}."
            )
        if name in documents:
            raise SystemExit(f"Duplicate workload name {name!r} in {directory}.")
        documents[name] = document
    return documents


def load_environment(inventory_root: Path, environment: str) -> dict[str, Any]:
    env_dir = inventory_root / environment
    if not env_dir.exists():
        raise SystemExit(f"Environment not found: {env_dir}")

    defaults_document = load_yaml_like(env_dir / "defaults.yaml")
    nodes_document = load_yaml_like(env_dir / "nodes.yaml")
    networks_document = load_yaml_like(env_dir / "networks.yaml")
    ingress_document = load_yaml_like(env_dir / "ingress.yaml")

    return {
        "version": 1,
        "defaults": defaults_document.get("defaults", {}),
        "nodes": nodes_document.get("nodes", {}),
        "networks": networks_document.get("networks", {}),
        "ingress": ingress_document.get("traefik_instances", {}),
        "cts": load_workload_directory(env_dir / "cts", "ct"),
        "vms": load_workload_directory(env_dir / "vms", "vm"),
        "_documents": {
            "defaults": defaults_document,
            "nodes": nodes_document,
            "networks": networks_document,
            "ingress": ingress_document,
        },
    }


def append_error(errors: list[str], context: str, message: str) -> None:
    errors.append(f"{context}: {message}")


def require_mapping(value: Any, context: str, errors: list[str]) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    append_error(errors, context, f"expected mapping, got {type(value).__name__}")
    return {}


def require_list(value: Any, context: str, errors: list[str]) -> list[Any]:
    if isinstance(value, list):
        return value
    append_error(errors, context, f"expected list, got {type(value).__name__}")
    return []


def expect_type(value: Any, expected: type | tuple[type, ...], context: str, errors: list[str]) -> None:
    if not isinstance(value, expected):
        if isinstance(expected, tuple):
            expected_name = ", ".join(t.__name__ for t in expected)
        else:
            expected_name = expected.__name__
        append_error(errors, context, f"expected {expected_name}, got {type(value).__name__}")


def validate_service(
    service: Any,
    context: str,
    traefik_instances: set[str],
    errors: list[str],
) -> tuple[str | None, str | None]:
    service_map = require_mapping(service, context, errors)
    for key in ("name", "port", "scheme"):
        if key not in service_map:
            append_error(errors, context, f"missing required field `{key}`")
    if "name" in service_map:
        expect_type(service_map["name"], str, f"{context}.name", errors)
    if "port" in service_map:
        expect_type(service_map["port"], int, f"{context}.port", errors)
    if "scheme" in service_map:
        expect_type(service_map["scheme"], str, f"{context}.scheme", errors)
    if "traefik_tag" in service_map and service_map["traefik_tag"] is not None:
        expect_type(service_map["traefik_tag"], str, f"{context}.traefik_tag", errors)
    if "traefik_label" in service_map and service_map["traefik_label"] is not None:
        expect_type(service_map["traefik_label"], str, f"{context}.traefik_label", errors)
    if "uri" in service_map and service_map["uri"] is not None:
        expect_type(service_map["uri"], str, f"{context}.uri", errors)

    if "proxy" in service_map:
        proxy_map = require_mapping(service_map["proxy"], f"{context}.proxy", errors)
        if "host" in proxy_map and proxy_map["host"] is not None:
            expect_type(proxy_map["host"], str, f"{context}.proxy.host", errors)

    has_traefik_tag = service_map.get("traefik_tag") is not None
    has_traefik_label = service_map.get("traefik_label") is not None
    has_uri = service_map.get("uri") is not None

    if len({has_traefik_tag, has_traefik_label, has_uri}) != 1:
        append_error(errors, context, "`traefik_tag`, `traefik_label` and `uri` must be defined together")

    traefik_tag = service_map.get("traefik_tag")
    if has_traefik_tag and isinstance(traefik_tag, str) and traefik_tag not in traefik_instances:
        append_error(errors, context, f"references unknown traefik_tag `{traefik_tag}`")

    return service_map.get("uri"), traefik_tag


def validate_common_workload(
    workload: dict[str, Any],
    context: str,
    nodes: set[str],
    networks: set[str],
    traefik_instances: set[str],
    uri_owners: dict[str, str],
    uri_tags: dict[str, str],
    errors: list[str],
) -> None:
    for key in (
        "version",
        "kind",
        "enabled",
        "vmid",
        "name",
        "node",
        "network",
        "resources",
        "boot",
        "storage",
        "services",
        "operations",
    ):
        if key not in workload:
            append_error(errors, context, f"missing required field `{key}`")

    if workload.get("version") != 1:
        append_error(errors, context, "`version` must be 1")

    if "enabled" in workload:
        expect_type(workload["enabled"], bool, f"{context}.enabled", errors)
    if "vmid" in workload:
        expect_type(workload["vmid"], int, f"{context}.vmid", errors)
    if "name" in workload:
        expect_type(workload["name"], str, f"{context}.name", errors)
    if "notes_title" in workload and workload["notes_title"] is not None:
        expect_type(workload["notes_title"], str, f"{context}.notes_title", errors)
    if "node" in workload:
        expect_type(workload["node"], str, f"{context}.node", errors)
        node_name = workload["node"]
        if isinstance(node_name, str) and node_name not in nodes:
            append_error(errors, context, f"references unknown node `{node_name}`")

    tags = workload.get("tags", [])
    if tags is not None:
        for index, tag in enumerate(require_list(tags, f"{context}.tags", errors)):
            expect_type(tag, str, f"{context}.tags[{index}]", errors)

    network = require_mapping(workload.get("network", {}), f"{context}.network", errors)
    for key in ("segment", "mode"):
        if key not in network:
            append_error(errors, f"{context}.network", f"missing required field `{key}`")
    segment = network.get("segment")
    if isinstance(segment, str) and segment not in networks:
        append_error(errors, context, f"references unknown network segment `{segment}`")
    mode = network.get("mode")
    if mode not in {"static", "dhcp"}:
        append_error(errors, f"{context}.network.mode", "must be `static` or `dhcp`")
    if mode == "static":
        for key in ("address", "gateway"):
            if not network.get(key):
                append_error(errors, f"{context}.network", f"requires `{key}` when mode=static")

    resources = require_mapping(workload.get("resources", {}), f"{context}.resources", errors)
    for key in ("cpu_cores", "memory_mb"):
        if key not in resources:
            append_error(errors, f"{context}.resources", f"missing required field `{key}`")
    for key in ("cpu_cores", "cpu_sockets", "memory_mb", "swap_mb"):
        if key in resources and resources[key] is not None:
            expect_type(resources[key], int, f"{context}.resources.{key}", errors)

    boot = require_mapping(workload.get("boot", {}), f"{context}.boot", errors)
    storage = require_mapping(workload.get("storage", {}), f"{context}.storage", errors)
    for key in ("rootfs_storage", "rootfs_size_gb"):
        if key not in storage:
            append_error(errors, f"{context}.storage", f"missing required field `{key}`")
    if "rootfs_storage" in storage:
        expect_type(storage["rootfs_storage"], str, f"{context}.storage.rootfs_storage", errors)
    if "rootfs_size_gb" in storage:
        expect_type(storage["rootfs_size_gb"], int, f"{context}.storage.rootfs_size_gb", errors)

    services = require_list(workload.get("services", []), f"{context}.services", errors)
    for index, service in enumerate(services):
        uri, traefik_tag = validate_service(service, f"{context}.services[{index}]", traefik_instances, errors)
        if uri is None or traefik_tag is None:
            continue
        owner = uri_owners.get(uri)
        owner_tag = uri_tags.get(uri)
        if owner is None:
            uri_owners[uri] = f"{context}.services[{index}]"
            uri_tags[uri] = traefik_tag
        elif owner_tag != traefik_tag:
            append_error(
                errors,
                f"{context}.services[{index}]",
                f"reuses uri `{uri}` already mapped to traefik_tag `{owner_tag}` by {owner}",
            )

    require_mapping(workload.get("operations", {}), f"{context}.operations", errors)


def validate_ct_workload(
    workload: dict[str, Any],
    context: str,
    nodes: set[str],
    networks: set[str],
    traefik_instances: set[str],
    uri_owners: dict[str, str],
    uri_tags: dict[str, str],
    errors: list[str],
) -> None:
    validate_common_workload(
        workload,
        context,
        nodes,
        networks,
        traefik_instances,
        uri_owners,
        uri_tags,
        errors,
    )
    if workload.get("kind") != "ct":
        append_error(errors, context, "`kind` must be `ct`")

    boot = require_mapping(workload.get("boot", {}), f"{context}.boot", errors)
    for key in ("on_boot", "start"):
        if key not in boot:
            append_error(errors, f"{context}.boot", f"missing required field `{key}`")
        elif boot[key] is not None:
            expect_type(boot[key], bool, f"{context}.boot.{key}", errors)

    lxc = require_mapping(workload.get("lxc", {}), f"{context}.lxc", errors)
    if "unprivileged" in lxc and lxc["unprivileged"] is not None:
        expect_type(lxc["unprivileged"], bool, f"{context}.lxc.unprivileged", errors)
    if "template" in lxc and lxc["template"] is not None:
        expect_type(lxc["template"], str, f"{context}.lxc.template", errors)
    if "features" in lxc:
        features = require_mapping(lxc["features"], f"{context}.lxc.features", errors)
        if "nesting" in features and features["nesting"] is not None:
            expect_type(features["nesting"], bool, f"{context}.lxc.features.nesting", errors)
    if "features_manual" in lxc:
        features_manual = require_mapping(lxc["features_manual"], f"{context}.lxc.features_manual", errors)
        for key in ("keyctl", "fuse", "create"):
            if key in features_manual and features_manual[key] is not None:
                expect_type(features_manual[key], bool, f"{context}.lxc.features_manual.{key}", errors)
        if "mount" in features_manual and features_manual["mount"] is not None:
            expect_type(features_manual["mount"], str, f"{context}.lxc.features_manual.mount", errors)
    if "mounts" in lxc:
        require_list(lxc["mounts"], f"{context}.lxc.mounts", errors)


def validate_vm_workload(
    workload: dict[str, Any],
    context: str,
    nodes: set[str],
    networks: set[str],
    traefik_instances: set[str],
    uri_owners: dict[str, str],
    uri_tags: dict[str, str],
    errors: list[str],
) -> None:
    validate_common_workload(
        workload,
        context,
        nodes,
        networks,
        traefik_instances,
        uri_owners,
        uri_tags,
        errors,
    )
    if workload.get("kind") != "vm":
        append_error(errors, context, "`kind` must be `vm`")

    boot = require_mapping(workload.get("boot", {}), f"{context}.boot", errors)
    for key in ("on_boot", "start_state"):
        if key not in boot:
            append_error(errors, f"{context}.boot", f"missing required field `{key}`")
    if "on_boot" in boot and boot["on_boot"] is not None:
        expect_type(boot["on_boot"], bool, f"{context}.boot.on_boot", errors)
    if "start_state" in boot and boot["start_state"] is not None:
        expect_type(boot["start_state"], str, f"{context}.boot.start_state", errors)

    qemu = require_mapping(workload.get("qemu", {}), f"{context}.qemu", errors)
    if "sockets" in qemu and qemu["sockets"] is not None:
        expect_type(qemu["sockets"], int, f"{context}.qemu.sockets", errors)
    if "agent_enabled" in qemu and qemu["agent_enabled"] is not None:
        expect_type(qemu["agent_enabled"], bool, f"{context}.qemu.agent_enabled", errors)
    if "source" in qemu:
        require_mapping(qemu["source"], f"{context}.qemu.source", errors)
    if "disks" in qemu:
        require_list(qemu["disks"], f"{context}.qemu.disks", errors)


def validate_environment_document(document: dict[str, Any], environment: str) -> list[str]:
    errors: list[str] = []

    defaults_document = document["_documents"]["defaults"]
    nodes_document = document["_documents"]["nodes"]
    networks_document = document["_documents"]["networks"]
    ingress_document = document["_documents"]["ingress"]

    if defaults_document.get("version") != 1:
        append_error(errors, environment, "defaults.yaml must declare version 1")
    if nodes_document.get("version") != 1:
        append_error(errors, environment, "nodes.yaml must declare version 1")
    if networks_document.get("version") != 1:
        append_error(errors, environment, "networks.yaml must declare version 1")
    if ingress_document.get("version") != 1:
        append_error(errors, environment, "ingress.yaml must declare version 1")

    nodes = require_mapping(document.get("nodes", {}), f"{environment}.nodes", errors)
    networks = require_mapping(document.get("networks", {}), f"{environment}.networks", errors)
    ingress = require_mapping(document.get("ingress", {}), f"{environment}.ingress", errors)

    for tag, instance in ingress.items():
        expect_type(tag, str, f"{environment}.ingress.{tag}", errors)
        instance_map = require_mapping(instance, f"{environment}.ingress.{tag}", errors)
        if "address" not in instance_map:
            append_error(errors, f"{environment}.ingress.{tag}", "missing required field `address`")
        elif instance_map["address"] is not None:
            expect_type(instance_map["address"], str, f"{environment}.ingress.{tag}.address", errors)

    node_names = set(nodes.keys())
    network_names = set(networks.keys())
    traefik_instance_names = set(ingress.keys())
    seen_vmids: dict[int, str] = {}
    uri_owners: dict[str, str] = {}
    uri_tags: dict[str, str] = {}

    for name, workload in document.get("cts", {}).items():
        context = f"{environment}.cts.{name}"
        validate_ct_workload(
            workload,
            context,
            node_names,
            network_names,
            traefik_instance_names,
            uri_owners,
            uri_tags,
            errors,
        )
        vmid = workload.get("vmid")
        if isinstance(vmid, int):
            owner = seen_vmids.get(vmid)
            if owner is not None:
                append_error(errors, context, f"reuses vmid {vmid} already used by {owner}")
            else:
                seen_vmids[vmid] = context

    for name, workload in document.get("vms", {}).items():
        context = f"{environment}.vms.{name}"
        validate_vm_workload(
            workload,
            context,
            node_names,
            network_names,
            traefik_instance_names,
            uri_owners,
            uri_tags,
            errors,
        )
        vmid = workload.get("vmid")
        if isinstance(vmid, int):
            owner = seen_vmids.get(vmid)
            if owner is not None:
                append_error(errors, context, f"reuses vmid {vmid} already used by {owner}")
            else:
                seen_vmids[vmid] = context

    return sorted(errors)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Terraform YAML inventory.")
    parser.add_argument(
        "--inventory-root",
        default="inventory",
        help="Path to the inventory root directory.",
    )
    parser.add_argument(
        "environments",
        nargs="*",
        help="Environment names to validate. Defaults to all discovered environments.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    inventory_root = (repo_root / args.inventory_root).resolve()

    try:
        environments = args.environments or discover_environments(inventory_root)
        if not environments:
            print("No inventory environments discovered.", file=sys.stderr)
            return 1

        all_errors: list[str] = []
        for environment in environments:
            document = load_environment(inventory_root, environment)
            errors = validate_environment_document(document, environment)
            if errors:
                all_errors.extend(errors)
                continue

            print(
                json.dumps(
                    {
                        "environment": environment,
                        "cts": sorted(document["cts"].keys()),
                        "vms": sorted(document["vms"].keys()),
                        "traefik_instances": sorted(document["ingress"].keys()),
                    }
                )
            )

        if all_errors:
            for error in all_errors:
                print(error, file=sys.stderr)
            return 1
        return 0
    except YamlLiteError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
