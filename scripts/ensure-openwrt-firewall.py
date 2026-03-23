#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import ipaddress
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


VALIDATOR_PATH = Path(__file__).with_name("validate-inventory.py")
VALIDATOR_SPEC = importlib.util.spec_from_file_location("validate_inventory", VALIDATOR_PATH)
if VALIDATOR_SPEC is None or VALIDATOR_SPEC.loader is None:
    raise SystemExit(f"Unable to load inventory helper from {VALIDATOR_PATH}.")
VALIDATOR_MODULE = importlib.util.module_from_spec(VALIDATOR_SPEC)
sys.modules[VALIDATOR_SPEC.name] = VALIDATOR_MODULE
VALIDATOR_SPEC.loader.exec_module(VALIDATOR_MODULE)

load_yaml_like = VALIDATOR_MODULE.load_yaml_like
load_workload_directory = VALIDATOR_MODULE.load_workload_directory

TOKEN_SPLIT_RE = re.compile(r"[\s,]+")
FALSE_VALUES = {"0", "false", "no", "off"}


@dataclass(frozen=True)
class ServiceCheck:
    workload_kind: str
    workload_name: str
    service_name: str
    uri: str
    traefik_tag: str
    traefik_label: str
    source_ip: str
    target_ip: str
    target_port: int


@dataclass
class UciSection:
    qualified_id: str
    section_id: str
    section_type: str | None = None
    options: dict[str, list[str]] = field(default_factory=dict)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ensure OpenWrt firewall rules exist for Traefik-to-workload traffic."
    )
    parser.add_argument("--environment", required=True, help="Inventory environment name.")
    parser.add_argument(
        "--inventory-root",
        default="inventory",
        help="Path to the inventory root relative to the repository root.",
    )
    parser.add_argument(
        "--openwrt-host",
        default=os.environ.get("OPENWRT_HOST"),
        help="OpenWrt SSH host. Defaults to OPENWRT_HOST.",
    )
    parser.add_argument(
        "--openwrt-user",
        default=os.environ.get("OPENWRT_USER", "root"),
        help="OpenWrt SSH user. Defaults to OPENWRT_USER or root.",
    )
    parser.add_argument(
        "--openwrt-port",
        type=int,
        default=int(os.environ.get("OPENWRT_PORT", "22")),
        help="OpenWrt SSH port. Defaults to OPENWRT_PORT or 22.",
    )
    parser.add_argument("--workload", help="Filter by workload name.")
    parser.add_argument("--service", help="Filter by service name.")
    parser.add_argument("--uri", help="Filter by service URI.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply the missing port to the first compatible rule when possible.",
    )
    parser.add_argument(
        "--plan-only",
        action="store_true",
        help="Only print the derived traffic checks, without contacting OpenWrt.",
    )
    return parser.parse_args()


def load_inventory_environment(repo_root: Path, inventory_root: str, environment: str) -> dict[str, Any]:
    inventory_base = Path(inventory_root)
    if not inventory_base.is_absolute():
        inventory_base = (repo_root / inventory_base).resolve()
    env_dir = inventory_base / environment
    if not env_dir.exists():
        raise SystemExit(f"Environment not found: {env_dir}")

    defaults_document = load_yaml_like(env_dir / "defaults.yaml")
    networks_document = load_yaml_like(env_dir / "networks.yaml")
    ingress_document = load_yaml_like(env_dir / "ingress.yaml")

    return {
        "defaults": defaults_document.get("defaults", {}),
        "networks": networks_document.get("networks", {}),
        "ingress": ingress_document.get("traefik_instances", {}),
        "cts": load_workload_directory(env_dir / "cts", "ct"),
        "vms": load_workload_directory(env_dir / "vms", "vm"),
    }


def merge_workloads(
    workloads: dict[str, dict[str, Any]],
    defaults: dict[str, Any],
    networks: dict[str, Any],
    kind_key: str,
) -> list[dict[str, Any]]:
    common_defaults = defaults.get("common", {})
    kind_defaults = defaults.get(kind_key, {})
    merged_workloads: list[dict[str, Any]] = []

    for workload in workloads.values():
        enabled = workload.get("enabled", kind_defaults.get("enabled", True))
        if not enabled:
            continue

        workload_network = workload.get("network", {})
        segment = workload_network.get("segment")
        merged_network: dict[str, Any] = {}
        if isinstance(segment, str):
            merged_network.update(networks.get(segment, {}))
        merged_network.update(kind_defaults.get("network", {}))
        merged_network.update(workload_network)

        merged = dict(common_defaults)
        merged.update(kind_defaults)
        merged.update(workload)
        merged["network"] = merged_network
        merged["services"] = workload.get("services", common_defaults.get("services", []))
        merged_workloads.append(merged)

    return merged_workloads


def normalize_ip_literal(value: str) -> str:
    text = value.strip()
    if "/" in text:
        return str(ipaddress.ip_interface(text).ip)
    return str(ipaddress.ip_address(text))


def build_service_checks(document: dict[str, Any], args: argparse.Namespace) -> list[ServiceCheck]:
    checks: list[ServiceCheck] = []
    ingress = document["ingress"]

    for workload_kind, kind_key, workloads in (
        ("ct", "ct", document["cts"]),
        ("vm", "vm", document["vms"]),
    ):
        merged_workloads = merge_workloads(workloads, document["defaults"], document["networks"], kind_key)
        for workload in merged_workloads:
            workload_name = str(workload.get("name"))
            if args.workload and workload_name != args.workload:
                continue

            network = workload.get("network", {})
            address = network.get("address")
            mode = network.get("mode")
            services = workload.get("services", [])

            for service in services:
                traefik_tag = service.get("traefik_tag")
                uri = service.get("uri")
                port = service.get("port")
                service_name = str(service.get("name") or uri or port or workload_name)
                traefik_label = str(service.get("traefik_label") or service_name)

                if traefik_tag is None or uri is None or port is None:
                    continue
                if args.service and service_name != args.service:
                    continue
                if args.uri and uri != args.uri:
                    continue
                if mode != "static" or not address:
                    raise SystemExit(
                        f"Workload {workload_name} service {service_name} needs a static address for firewall checks."
                    )
                if traefik_tag not in ingress:
                    raise SystemExit(
                        f"Service {service_name} references unknown Traefik instance {traefik_tag}."
                    )

                traefik_address = ingress[traefik_tag].get("address")
                if not traefik_address:
                    raise SystemExit(f"Traefik instance {traefik_tag} is missing address in ingress.yaml.")

                checks.append(
                    ServiceCheck(
                        workload_kind=workload_kind,
                        workload_name=workload_name,
                        service_name=service_name,
                        uri=str(uri),
                        traefik_tag=str(traefik_tag),
                        traefik_label=traefik_label,
                        source_ip=normalize_ip_literal(str(traefik_address)),
                        target_ip=normalize_ip_literal(str(address)),
                        target_port=int(port),
                    )
                )

    return sorted(checks, key=lambda item: (item.workload_name, item.service_name, item.uri, item.target_port))


def run_ssh(host: str, user: str, port: int, remote_command: str) -> str:
    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-p",
        str(port),
        f"{user}@{host}",
        remote_command,
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"SSH command failed: {remote_command}"
        raise SystemExit(detail)
    return result.stdout.strip()


def strip_uci_value(value: str) -> str:
    text = value.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {"'", '"'}:
        return text[1:-1]
    return text


def parse_uci_show(text: str, package_name: str) -> list[UciSection]:
    sections: list[UciSection] = []
    by_id: dict[str, UciSection] = {}

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue

        left, right = line.split("=", 1)
        parts = left.split(".")
        if len(parts) < 2 or parts[0] != package_name:
            continue

        section_id = parts[1]
        section = by_id.get(section_id)
        if section is None:
            section = UciSection(
                qualified_id=f"{package_name}.{section_id}",
                section_id=section_id,
            )
            by_id[section_id] = section
            sections.append(section)

        if len(parts) == 2:
            section.section_type = strip_uci_value(right)
            continue

        option = ".".join(parts[2:])
        section.options.setdefault(option, []).append(strip_uci_value(right))

    return sections


def option_values(section: UciSection, key: str) -> list[str]:
    return list(section.options.get(key, []))


def option_first(section: UciSection, key: str) -> str | None:
    values = option_values(section, key)
    return values[0] if values else None


def split_option_words(values: list[str]) -> list[str]:
    words: list[str] = []
    for value in values:
        for token in TOKEN_SPLIT_RE.split(value.strip()):
            if token:
                words.append(token)
    return words


def option_enabled(section: UciSection) -> bool:
    value = option_first(section, "enabled")
    return value is None or value.strip().lower() not in FALSE_VALUES


def build_device_interface_map(network_sections: list[UciSection]) -> dict[str, list[str]]:
    mapping: dict[str, list[str]] = {}
    for section in network_sections:
        if section.section_type != "interface":
            continue
        devices = split_option_words(option_values(section, "device"))
        devices.extend(split_option_words(option_values(section, "ifname")))
        for device in devices:
            mapping.setdefault(device, []).append(section.section_id)
    return mapping


def build_interface_zone_map(firewall_sections: list[UciSection]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for section in firewall_sections:
        if section.section_type != "zone":
            continue
        zone_name = option_first(section, "name") or section.section_id
        for network_name in split_option_words(option_values(section, "network")):
            mapping[network_name] = zone_name
    return mapping


def resolve_interface(device: str, device_map: dict[str, list[str]]) -> str:
    interfaces = sorted(set(device_map.get(device, [])))
    if not interfaces:
        raise SystemExit(f"No OpenWrt interface maps to device {device}.")
    if len(interfaces) > 1:
        raise SystemExit(f"Device {device} maps to multiple interfaces: {', '.join(interfaces)}")
    return interfaces[0]


def extract_route_device(route_output: str) -> str:
    match = re.search(r"(?:^|\s)dev\s+(\S+)", route_output)
    if match is None:
        raise SystemExit(f"Unable to extract device from route output: {route_output.strip()}")
    return match.group(1)


def rule_allows_tcp(rule: UciSection) -> bool:
    proto_words = split_option_words(option_values(rule, "proto"))
    if not proto_words:
        return False
    for word in proto_words:
        lower_word = word.lower()
        if lower_word in {"all", "tcp", "tcpudp"} or "tcp" in lower_word:
            return True
    return False


def port_matches_tokens(tokens: list[str], target_port: int) -> bool:
    for token in tokens:
        if token.isdigit() and int(token) == target_port:
            return True

        if "-" in token or ":" in token:
            delimiter = "-" if "-" in token else ":"
            start_text, end_text = token.split(delimiter, 1)
            if not start_text.isdigit() or not end_text.isdigit():
                continue
            start = int(start_text)
            end = int(end_text)
            if start <= target_port <= end:
                return True
    return False


def ip_family_matches(rule: UciSection, ip_text: str) -> bool:
    family = (option_first(rule, "family") or "").strip().lower()
    if not family or family == "any":
        return True
    ip_version = ipaddress.ip_address(ip_text).version
    return (family == "ipv4" and ip_version == 4) or (family == "ipv6" and ip_version == 6)


def ip_constraint_matches(rule: UciSection, key: str, address_text: str) -> bool:
    entries = split_option_words(option_values(rule, key))
    if not entries:
        return True

    address = ipaddress.ip_address(address_text)
    for entry in entries:
        if entry == address_text:
            return True
        try:
            if address in ipaddress.ip_network(entry, strict=False):
                return True
        except ValueError:
            continue
    return False


def summarize_rule(rule: UciSection) -> dict[str, Any]:
    return {
        "section_id": rule.section_id,
        "qualified_id": rule.qualified_id,
        "name": option_first(rule, "name"),
        "target": option_first(rule, "target"),
        "proto": split_option_words(option_values(rule, "proto")),
        "src": option_first(rule, "src"),
        "dest": option_first(rule, "dest"),
        "family": option_first(rule, "family"),
        "src_ip": split_option_words(option_values(rule, "src_ip")),
        "dest_ip": split_option_words(option_values(rule, "dest_ip")),
        "dest_port": split_option_words(option_values(rule, "dest_port")),
    }


def render_rule_summary(rule: UciSection) -> str:
    return json.dumps(summarize_rule(rule), sort_keys=True)


def apply_dest_port_update(host: str, user: str, port: int, rule: UciSection, target_port: int) -> str:
    existing_tokens = split_option_words(option_values(rule, "dest_port"))
    updated_tokens = existing_tokens + [str(target_port)]
    seen: set[str] = set()
    normalized_tokens: list[str] = []
    for token in updated_tokens:
        if token in seen:
            continue
        seen.add(token)
        normalized_tokens.append(token)

    dest_port_value = " ".join(normalized_tokens)
    remote_command = " && ".join(
        [
            f"uci set {rule.qualified_id}.dest_port={shlex.quote(dest_port_value)}",
            "uci commit firewall",
            "/etc/init.d/firewall reload",
            f"uci -q show {rule.qualified_id}",
        ]
    )
    return run_ssh(host, user, port, remote_command)


def evaluate_service(
    service: ServiceCheck,
    firewall_sections: list[UciSection],
    device_map: dict[str, list[str]],
    interface_zone_map: dict[str, str],
    route_cache: dict[str, str],
    args: argparse.Namespace,
) -> str:
    source_route = route_cache[service.source_ip]
    target_route = route_cache[service.target_ip]

    source_device = extract_route_device(source_route)
    target_device = extract_route_device(target_route)
    source_interface = resolve_interface(source_device, device_map)
    target_interface = resolve_interface(target_device, device_map)

    source_zone = interface_zone_map.get(source_interface)
    target_zone = interface_zone_map.get(target_interface)
    if source_zone is None:
        raise SystemExit(f"No firewall zone maps to interface {source_interface} for source IP {service.source_ip}.")
    if target_zone is None:
        raise SystemExit(f"No firewall zone maps to interface {target_interface} for target IP {service.target_ip}.")

    print(
        json.dumps(
            {
                "service": service.service_name,
                "uri": service.uri,
                "source_ip": service.source_ip,
                "source_device": source_device,
                "source_interface": source_interface,
                "source_zone": source_zone,
                "target_ip": service.target_ip,
                "target_device": target_device,
                "target_interface": target_interface,
                "target_zone": target_zone,
                "target_port": service.target_port,
            },
            sort_keys=True,
        )
    )

    exact_match: UciSection | None = None
    wildcard_match: UciSection | None = None
    update_candidate: UciSection | None = None

    for section in firewall_sections:
        if section.section_type != "rule":
            continue
        if not option_enabled(section):
            continue
        if (option_first(section, "target") or "").upper() != "ACCEPT":
            continue
        if option_first(section, "src") != source_zone:
            continue
        if option_first(section, "dest") != target_zone:
            continue
        if not rule_allows_tcp(section):
            continue
        if not ip_family_matches(section, service.target_ip):
            continue
        if not ip_constraint_matches(section, "src_ip", service.source_ip):
            continue
        if not ip_constraint_matches(section, "dest_ip", service.target_ip):
            continue

        port_tokens = split_option_words(option_values(section, "dest_port"))
        if not port_tokens:
            if wildcard_match is None:
                wildcard_match = section
            continue
        if port_matches_tokens(port_tokens, service.target_port):
            exact_match = section
            break
        if update_candidate is None:
            update_candidate = section

    if exact_match is not None:
        print(f"MATCH {service.workload_name}/{service.service_name}: {render_rule_summary(exact_match)}")
        return "match"

    if wildcard_match is not None:
        print(
            f"MATCH_ANY_PORT {service.workload_name}/{service.service_name}: "
            f"{render_rule_summary(wildcard_match)}"
        )
        return "match"

    if update_candidate is not None:
        if args.apply:
            updated_state = apply_dest_port_update(
                args.openwrt_host,
                args.openwrt_user,
                args.openwrt_port,
                update_candidate,
                service.target_port,
            )
            print(f"UPDATED {service.workload_name}/{service.service_name}: {updated_state.strip()}")
            return "updated"
        print(
            f"NEEDS_UPDATE {service.workload_name}/{service.service_name}: would add port "
            f"{service.target_port} to {render_rule_summary(update_candidate)}"
        )
        return "needs_update"

    print(
        f"MISSING {service.workload_name}/{service.service_name}: no compatible rule for "
        f"{source_zone} -> {target_zone} tcp/{service.target_port}"
    )
    return "missing"


def main() -> int:
    args = parse_args()
    if not args.plan_only and not args.openwrt_host:
        print("--openwrt-host or OPENWRT_HOST is required unless --plan-only is used.", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    document = load_inventory_environment(repo_root, args.inventory_root, args.environment)
    checks = build_service_checks(document, args)

    if not checks:
        print("No Traefik-exposed services matched the requested filters.")
        return 0

    if args.plan_only:
        for check in checks:
            print(json.dumps(check.__dict__, sort_keys=True))
        return 0

    network_text = run_ssh(args.openwrt_host, args.openwrt_user, args.openwrt_port, "uci -q show network")
    firewall_text = run_ssh(args.openwrt_host, args.openwrt_user, args.openwrt_port, "uci -q show firewall")

    network_sections = parse_uci_show(network_text, "network")
    firewall_sections = parse_uci_show(firewall_text, "firewall")
    device_map = build_device_interface_map(network_sections)
    interface_zone_map = build_interface_zone_map(firewall_sections)

    route_cache: dict[str, str] = {}
    unique_ips = sorted({check.source_ip for check in checks} | {check.target_ip for check in checks})
    for ip_text in unique_ips:
        route_cache[ip_text] = run_ssh(
            args.openwrt_host,
            args.openwrt_user,
            args.openwrt_port,
            f"ip route get {shlex.quote(ip_text)}",
        )

    statuses: list[str] = []
    for check in checks:
        statuses.append(evaluate_service(check, firewall_sections, device_map, interface_zone_map, route_cache, args))

    if any(status == "missing" for status in statuses):
        return 1
    if not args.apply and any(status == "needs_update" for status in statuses):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
