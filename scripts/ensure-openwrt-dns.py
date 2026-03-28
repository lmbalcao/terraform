#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
VALIDATOR_PATH = SCRIPT_DIR / "validate-inventory.py"
FIREWALL_HELPER_PATH = SCRIPT_DIR / "ensure-openwrt-firewall.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Unable to load helper module from {path}.")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


VALIDATOR_MODULE = load_module("validate_inventory", VALIDATOR_PATH)
FIREWALL_MODULE = load_module("ensure_openwrt_firewall", FIREWALL_HELPER_PATH)

load_yaml_like = VALIDATOR_MODULE.load_yaml_like
load_workload_directory = VALIDATOR_MODULE.load_workload_directory
OpenWrtClient = FIREWALL_MODULE.OpenWrtClient
OpenWrtRPCError = FIREWALL_MODULE.OpenWrtRPCError
UciSection = FIREWALL_MODULE.UciSection
fetch_ct_runtime_ip = FIREWALL_MODULE.fetch_ct_runtime_ip
normalize_ip_literal = FIREWALL_MODULE.normalize_ip_literal
option_first = FIREWALL_MODULE.option_first
parse_uci_show = FIREWALL_MODULE.parse_uci_show


@dataclass(frozen=True)
class DesiredDomainRecord:
    section_id: str
    name: str
    ip: str
    source: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ensure OpenWrt DNS domain records exist for workload hostnames and Traefik-exposed service URIs."
    )
    parser.add_argument("--environment", required=True, help="Inventory environment name.")
    parser.add_argument("--inventory-root", required=True, help="Path to the inventory root.")
    parser.add_argument("--apply", action="store_true", help="Apply DNS changes instead of only reporting drift.")
    parser.add_argument("--host", default=os.environ.get("OPENWRT_HOSTNAME"), help="OpenWrt SSH host.")
    parser.add_argument("--port", type=int, default=int(os.environ.get("OPENWRT_PORT", "22")), help="OpenWrt SSH port.")
    parser.add_argument("--scheme", default=os.environ.get("OPENWRT_SCHEME", "http"), help="Compatibility option.")
    parser.add_argument("--username", default=os.environ.get("OPENWRT_USERNAME", "root"), help="OpenWrt SSH user.")
    parser.add_argument("--password", default=os.environ.get("OPENWRT_PASSWORD"), help="OpenWrt password fallback.")
    parser.add_argument(
        "--private-key-path",
        default=os.environ.get("OPENWRT_SSH_PRIVATE_KEY_PATH"),
        help="Optional SSH private key path used instead of password auth.",
    )
    parser.add_argument("--proxmox-api-url", default=os.environ.get("PROXMOX_API_URL"), help="Optional Proxmox API URL.")
    parser.add_argument("--proxmox-token-id", default=os.environ.get("PROXMOX_API_TOKEN_ID"), help="Optional Proxmox API token ID.")
    parser.add_argument(
        "--proxmox-token-secret",
        default=os.environ.get("PROXMOX_API_TOKEN_SECRET") or os.environ.get("PROXMOX_API_TOKEN"),
        help="Optional Proxmox API token secret.",
    )
    parser.add_argument(
        "--proxmox-tls-insecure",
        default=os.environ.get("PROXMOX_TLS_INSECURE", "true"),
        help="Disable TLS verification for Proxmox API discovery.",
    )
    args = parser.parse_args()
    if not args.host:
        raise SystemExit("Missing OpenWrt host. Set --host or OPENWRT_HOSTNAME.")
    if not args.private_key_path and not args.password:
        raise SystemExit("Provide either --private-key-path/OPENWRT_SSH_PRIVATE_KEY_PATH or --password/OPENWRT_PASSWORD.")
    args.proxmox_tls_insecure = str(args.proxmox_tls_insecure).strip().lower() not in {"0", "false", "no", "off"}
    return args


def resolve_inventory_root(value: str) -> Path:
    root = Path(value)
    if not root.is_absolute():
        root = (Path.cwd() / root).resolve()
    return root


def merge_workloads(defaults: dict[str, Any], documents: dict[str, dict[str, Any]], kind: str) -> dict[str, dict[str, Any]]:
    common_defaults = defaults.get("common", {})
    kind_defaults = defaults.get(kind, {})
    merged: dict[str, dict[str, Any]] = {}
    for name, document in documents.items():
        workload = dict(common_defaults)
        workload.update(kind_defaults)
        workload.update(document)
        workload["services"] = document.get("services", common_defaults.get("services", []))
        enabled = workload.get("enabled", kind_defaults.get("enabled", True))
        if enabled:
            merged[name] = workload
    return merged


def load_inventory(inventory_root: Path, environment: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    env_dir = inventory_root / environment
    if not env_dir.exists():
        raise SystemExit(f"Environment not found: {env_dir}")
    defaults_document = load_yaml_like(env_dir / "defaults.yaml")
    ingress_document = load_yaml_like(env_dir / "ingress.yaml")
    defaults = defaults_document.get("defaults", {})
    cts = merge_workloads(defaults, load_workload_directory(env_dir / "cts", "ct"), "ct")
    vms = merge_workloads(defaults, load_workload_directory(env_dir / "vms", "vm"), "vm")
    return defaults, ingress_document.get("traefik_instances", {}), cts, vms


def normalize_section_id(prefix: str, name: str) -> str:
    value = f"{prefix}-{name}".lower()
    for needle in (".", "-", ":"):
        value = value.replace(needle, "_")
    return value[:63]


def hostname_candidates(workload: dict[str, Any]) -> list[str]:
    hostname = workload.get("hostname") or workload.get("name")
    if not hostname:
        return []
    hostname = str(hostname).strip()
    if not hostname:
        return []
    names = [hostname]
    dns_domain = workload.get("network", {}).get("dns_domain")
    if dns_domain and "." not in hostname:
        names.append(f"{hostname}.{dns_domain}")
    return names


def workload_runtime_ip(workload: dict[str, Any], kind: str, args: argparse.Namespace) -> str | None:
    network = workload.get("network", {})
    if kind == "ct":
        runtime = fetch_ct_runtime_ip(workload, args)
        if runtime:
            return runtime
    configured = network.get("address")
    if configured:
        return normalize_ip_literal(str(configured))
    return None


def build_service_records(workloads: list[tuple[str, dict[str, Any]]], ingress: dict[str, Any]) -> list[DesiredDomainRecord]:
    records: list[DesiredDomainRecord] = []
    for workload_name, workload in workloads:
        for service in workload.get("services", []) or []:
            uri = service.get("uri")
            traefik_tag = service.get("traefik_tag")
            traefik_label = service.get("traefik_label")
            port = service.get("port")
            if not (uri and traefik_tag and traefik_label and port is not None):
                continue
            instance = ingress.get(str(traefik_tag))
            if not isinstance(instance, dict):
                continue
            address = instance.get("address")
            if not address:
                continue
            records.append(
                DesiredDomainRecord(
                    section_id=normalize_section_id(f"dns-{traefik_tag}", str(uri)),
                    name=str(uri),
                    ip=normalize_ip_literal(str(address)),
                    source=f"service:{workload_name}",
                )
            )
    return records


def build_host_records(workloads: list[tuple[str, dict[str, Any], str]], args: argparse.Namespace) -> list[DesiredDomainRecord]:
    records: list[DesiredDomainRecord] = []
    for workload_name, workload, kind in workloads:
        runtime_ip = workload_runtime_ip(workload, kind, args)
        if not runtime_ip:
            continue
        for record_name in hostname_candidates(workload):
            records.append(
                DesiredDomainRecord(
                    section_id=normalize_section_id(f"host-{kind}", record_name),
                    name=record_name,
                    ip=runtime_ip,
                    source=f"host:{workload_name}",
                )
            )
    return records


def dedupe_records(records: list[DesiredDomainRecord]) -> list[DesiredDomainRecord]:
    by_name: dict[str, DesiredDomainRecord] = {}
    for record in records:
        current = by_name.get(record.name)
        if current is None:
            by_name[record.name] = record
            continue
        if current.ip != record.ip:
            raise SystemExit(
                f"Conflicting DNS targets for {record.name}: {current.ip} ({current.source}) vs {record.ip} ({record.source})"
            )
    return sorted(by_name.values(), key=lambda item: (item.name, item.section_id))


def is_managed_domain(section: UciSection) -> bool:
    return section.section_type == "domain" and (section.section_id.startswith("dns_") or section.section_id.startswith("host_"))


def current_domain_options(section: UciSection) -> dict[str, str]:
    options: dict[str, str] = {}
    for key in ("name", "ip"):
        value = option_first(section, key)
        if value:
            options[key] = value
    return options


def reconcile_domains(client: OpenWrtClient, desired_records: list[DesiredDomainRecord], apply: bool) -> int:
    sections = parse_uci_show(client.show_config("dhcp"), "dhcp")
    current_by_id = {section.section_id: section for section in sections if is_managed_domain(section)}
    desired_by_id = {record.section_id: record for record in desired_records}
    drift = False
    changed = False

    for section_id, record in sorted(desired_by_id.items()):
        desired_options = {"name": record.name, "ip": record.ip}
        current = current_by_id.get(section_id)
        if current is None:
            drift = True
            print(f"CREATE {section_id}: {json.dumps(desired_options, sort_keys=True)}")
            if apply:
                client.add_section("dhcp", "domain", section_id, desired_options)
                changed = True
            continue

        current_options = current_domain_options(current)
        if current_options == desired_options:
            print(f"KEEP {section_id}: {json.dumps(desired_options, sort_keys=True)}")
            continue

        drift = True
        print(f"UPDATE {section_id}: {json.dumps(current_options, sort_keys=True)} -> {json.dumps(desired_options, sort_keys=True)}")
        if apply:
            client.set_section_values("dhcp", section_id, desired_options)
            extra_keys = [key for key in current.options.keys() if key not in desired_options]
            client.delete_options("dhcp", section_id, extra_keys)
            changed = True

    for section_id, current in sorted(current_by_id.items()):
        if section_id in desired_by_id:
            continue
        drift = True
        print(f"DELETE {section_id}: {json.dumps(current_domain_options(current), sort_keys=True)}")
        if apply:
            client.delete_section("dhcp", section_id)
            changed = True

    if apply and changed:
        client.commit("dhcp")
        result = client.exec("/etc/init.d/dnsmasq", ["restart"])
        if result.code != 0:
            detail = result.stderr or result.stdout or "dnsmasq restart failed"
            raise OpenWrtRPCError(detail)

    if drift and not apply:
        return 1
    return 0


def main() -> int:
    args = parse_args()
    inventory_root = resolve_inventory_root(args.inventory_root)
    _, ingress, cts, vms = load_inventory(inventory_root, args.environment)
    host_workloads = [(name, workload, "ct") for name, workload in cts.items()] + [
        (name, workload, "vm") for name, workload in vms.items()
    ]
    service_workloads = [(name, workload) for name, workload, _ in host_workloads]
    desired_records = dedupe_records(
        build_service_records(service_workloads, ingress) + build_host_records(host_workloads, args)
    )
    client = OpenWrtClient(
        host=args.host,
        user=args.username,
        password=args.password or "",
        private_key_path=args.private_key_path,
        port=args.port,
        scheme=args.scheme,
        tls_insecure=True,
    )
    return reconcile_domains(client, desired_records, args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
