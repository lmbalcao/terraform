#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import ipaddress
import json
import os
import re
import shlex
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
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
MANAGED_RULE_PREFIX = "tfw_"
MANAGED_RULE_OPTION_KEYS = {
    "name",
    "enabled",
    "target",
    "proto",
    "src",
    "src_ip",
    "dest",
    "dest_port",
    "family",
}
PROXMOX_DISCOVERY_ATTEMPTS = 12
PROXMOX_DISCOVERY_DELAY_SECONDS = 5


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


@dataclass(frozen=True)
class DesiredRule:
    section_id: str
    name: str
    traefik_tag: str
    source_ip: str
    source_zone: str
    target_zone: str
    family: str
    dest_ports: tuple[str, ...]
    workloads: tuple[str, ...]
    services: tuple[str, ...]
    uris: tuple[str, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "section_id": self.section_id,
            "name": self.name,
            "traefik_tag": self.traefik_tag,
            "source_ip": self.source_ip,
            "source_zone": self.source_zone,
            "target_zone": self.target_zone,
            "family": self.family,
            "dest_ports": list(self.dest_ports),
            "workloads": list(self.workloads),
            "services": list(self.services),
            "uris": list(self.uris),
        }


@dataclass
class UciSection:
    qualified_id: str
    section_id: str
    section_type: str | None = None
    options: dict[str, list[str]] = field(default_factory=dict)


@dataclass(frozen=True)
class ExecResult:
    code: int
    stdout: str
    stderr: str


class ProxmoxRequestError(RuntimeError):
    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class OpenWrtRPCError(RuntimeError):
    pass


class OpenWrtClient:
    def __init__(
        self,
        host: str,
        user: str,
        password: str,
        port: int = 22,
        scheme: str = "http",
        tls_insecure: bool = True,
    ) -> None:
        self.host = host
        self.user = user
        self.password = password
        self.port = port
        self.scheme = scheme
        self.tls_insecure = tls_insecure

    def _run_remote(self, command: list[str]) -> ExecResult:
        askpass_path = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False, prefix="openwrt-askpass-", suffix=".sh") as handle:
                handle.write('#!/bin/sh\nprintf "%s\n" "$OPENWRT_SSH_PASSWORD"\n')
                askpass_path = handle.name
            os.chmod(askpass_path, 0o700)

            environment = dict(os.environ)
            environment["DISPLAY"] = environment.get("DISPLAY") or "codex:0"
            environment["OPENWRT_SSH_PASSWORD"] = self.password
            environment["SSH_ASKPASS"] = askpass_path
            environment["SSH_ASKPASS_REQUIRE"] = "force"

            completed = subprocess.run(
                [
                    "setsid",
                    "-w",
                    "ssh",
                    "-o",
                    "BatchMode=no",
                    "-o",
                    "StrictHostKeyChecking=accept-new",
                    "-o",
                    "PubkeyAuthentication=no",
                    "-o",
                    "PreferredAuthentications=password,keyboard-interactive",
                    "-p",
                    str(self.port),
                    f"{self.user}@{self.host}",
                    shlex.join(command),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            return ExecResult(
                code=completed.returncode,
                stdout=(completed.stdout or "").strip(),
                stderr=(completed.stderr or "").strip(),
            )
        finally:
            if askpass_path:
                try:
                    os.unlink(askpass_path)
                except FileNotFoundError:
                    pass

    def _run_shell(self, script: str) -> ExecResult:
        return self._run_remote(["sh", "-lc", script])

    def exec(self, command: str, params: list[str]) -> ExecResult:
        return self._run_remote([command, *params])

    def show_config(self, config_name: str) -> str:
        result = self.exec("uci", ["-q", "show", config_name])
        if result.code != 0:
            detail = result.stderr or result.stdout or f"uci show {config_name} failed"
            raise OpenWrtRPCError(detail)
        return result.stdout.strip()

    def route_get(self, ip_text: str) -> str:
        ip_obj = ipaddress.ip_address(ip_text)
        params = ["route", "get", ip_text] if ip_obj.version == 4 else ["-6", "route", "get", ip_text]
        result = self.exec("ip", params)
        if result.code != 0:
            detail = result.stderr or result.stdout or f"ip route get {ip_text} failed"
            raise OpenWrtRPCError(detail)
        return result.stdout.strip()

    def add_section(self, config: str, section_type: str, section: str, values: dict[str, Any]) -> None:
        commands = [f"uci set {config}.{section}={shlex.quote(section_type)}"]
        for key, value in values.items():
            commands.append(f"uci set {config}.{section}.{key}={shlex.quote(str(value))}")
        result = self._run_shell(" && ".join(commands))
        if result.code != 0:
            detail = result.stderr or result.stdout or f"unable to create {config}.{section}"
            raise OpenWrtRPCError(detail)

    def set_section_values(self, config: str, section: str, values: dict[str, Any]) -> None:
        commands = [f"uci set {config}.{section}.{key}={shlex.quote(str(value))}" for key, value in values.items()]
        if not commands:
            return
        result = self._run_shell(" && ".join(commands))
        if result.code != 0:
            detail = result.stderr or result.stdout or f"unable to update {config}.{section}"
            raise OpenWrtRPCError(detail)

    def delete_section(self, config: str, section: str) -> None:
        result = self.exec("uci", ["delete", f"{config}.{section}"])
        if result.code != 0:
            detail = result.stderr or result.stdout or f"unable to delete {config}.{section}"
            raise OpenWrtRPCError(detail)

    def delete_options(self, config: str, section: str, options: list[str]) -> None:
        if not options:
            return
        commands = [f"uci delete {config}.{section}.{option}" for option in options]
        result = self._run_shell(" && ".join(commands))
        if result.code != 0:
            detail = result.stderr or result.stdout or f"unable to delete options from {config}.{section}"
            raise OpenWrtRPCError(detail)

    def commit(self, config: str) -> None:
        result = self.exec("uci", ["commit", config])
        if result.code != 0:
            detail = result.stderr or result.stdout or f"uci commit {config} failed"
            raise OpenWrtRPCError(detail)

    def reload_firewall(self) -> None:
        result = self.exec("/etc/init.d/firewall", ["reload"])
        if result.code != 0:
            detail = result.stderr or result.stdout or "firewall reload failed"
            raise OpenWrtRPCError(detail)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ensure aggregated OpenWrt firewall rules exist for Traefik-to-workload traffic."
    )
    parser.add_argument("--environment", required=True, help="Inventory environment name.")
    parser.add_argument(
        "--inventory-root",
        default="inventory",
        help="Path to the inventory root relative to the repository root.",
    )
    parser.add_argument("--workload", help="Filter by workload name.")
    parser.add_argument("--service", help="Filter by service name.")
    parser.add_argument("--uri", help="Filter by service URI.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create, update and delete managed OpenWrt firewall rules to match the derived intent.",
    )
    parser.add_argument(
        "--plan-only",
        action="store_true",
        help="Only print the derived service checks and aggregated firewall rules.",
    )
    parser.add_argument(
        "--openwrt-host",
        default=os.environ.get("OPENWRT_HOSTNAME") or os.environ.get("OPENWRT_HOST"),
        help="OpenWrt LuCI hostname or IP. Defaults to OPENWRT_HOSTNAME or OPENWRT_HOST.",
    )
    parser.add_argument(
        "--openwrt-user",
        default=os.environ.get("OPENWRT_USERNAME") or os.environ.get("OPENWRT_USER", "root"),
        help="OpenWrt LuCI username. Defaults to OPENWRT_USERNAME or OPENWRT_USER or root.",
    )
    parser.add_argument(
        "--openwrt-password",
        default=os.environ.get("OPENWRT_PASSWORD"),
        help="OpenWrt LuCI password. Defaults to OPENWRT_PASSWORD.",
    )
    parser.add_argument(
        "--openwrt-port",
        type=int,
        default=int(os.environ.get("OPENWRT_PORT", "80")),
        help="OpenWrt LuCI port. Defaults to OPENWRT_PORT or 80.",
    )
    parser.add_argument(
        "--openwrt-scheme",
        default=os.environ.get("OPENWRT_SCHEME", "http"),
        help="OpenWrt LuCI scheme. Defaults to OPENWRT_SCHEME or http.",
    )
    parser.add_argument(
        "--openwrt-tls-insecure",
        action="store_true",
        default=(os.environ.get("OPENWRT_TLS_INSECURE", "true").strip().lower() not in FALSE_VALUES),
        help="Disable TLS verification for LuCI HTTPS. Defaults to OPENWRT_TLS_INSECURE or true.",
    )
    parser.add_argument(
        "--proxmox-api-url",
        default=os.environ.get("PROXMOX_API_URL"),
        help="Proxmox API URL. Defaults to PROXMOX_API_URL.",
    )
    parser.add_argument(
        "--proxmox-token-id",
        default=os.environ.get("PROXMOX_API_TOKEN_ID"),
        help="Proxmox API token ID. Defaults to PROXMOX_API_TOKEN_ID.",
    )
    parser.add_argument(
        "--proxmox-token-secret",
        default=os.environ.get("PROXMOX_API_TOKEN_SECRET") or os.environ.get("PROXMOX_API_TOKEN"),
        help="Proxmox API token secret. Defaults to PROXMOX_API_TOKEN_SECRET or PROXMOX_API_TOKEN.",
    )
    parser.add_argument(
        "--proxmox-tls-insecure",
        action="store_true",
        default=(os.environ.get("PROXMOX_TLS_INSECURE", "true").strip().lower() not in FALSE_VALUES),
        help="Disable TLS verification for Proxmox API requests. Defaults to PROXMOX_TLS_INSECURE or true.",
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


def make_context(tls_insecure: bool) -> ssl.SSLContext | None:
    if not tls_insecure:
        return None
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def proxmox_api_request(
    method: str,
    url: str,
    token_id: str,
    token_secret: str,
    tls_insecure: bool,
    data: dict[str, str] | None = None,
) -> Any:
    headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}
    payload = None
    if data is not None:
        payload = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    request = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, context=make_context(tls_insecure), timeout=30) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ProxmoxRequestError(
            f"Proxmox API {method} {url} failed with HTTP {exc.code}: {body}",
            status_code=exc.code,
        ) from exc
    except urllib.error.URLError as exc:
        raise ProxmoxRequestError(f"Proxmox API {method} {url} failed: {exc.reason}") from exc

    if not body:
        return {}
    return json.loads(body)


def proxmox_available(args: argparse.Namespace) -> bool:
    return bool(args.proxmox_api_url and args.proxmox_token_id and args.proxmox_token_secret)


def proxmox_error_is_nonfatal(error: ProxmoxRequestError) -> bool:
    text = str(error).lower()
    return any(marker in text for marker in ("does not exist", "not running", "vm is not running", "no such file"))


def collect_ip_candidates(value: Any) -> list[str]:
    candidates: set[str] = set()

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            for key, child in node.items():
                if key.lower() in {"hwaddr", "mac", "hardware-address"}:
                    continue
                visit(child)
            return
        if isinstance(node, list):
            for child in node:
                visit(child)
            return
        if not isinstance(node, str):
            return

        text = node.strip()
        if not text:
            return
        try:
            ip_obj = ipaddress.ip_interface(text).ip if "/" in text else ipaddress.ip_address(text)
        except ValueError:
            return
        if ip_obj.is_loopback or ip_obj.is_link_local or ip_obj.is_multicast or ip_obj.is_unspecified:
            return
        candidates.add(str(ip_obj))

    visit(value)
    return sorted(candidates, key=lambda item: (ipaddress.ip_address(item).version, item))


def choose_runtime_ip(
    candidates: list[str],
    preferred_cidr: str | None,
    configured_address: str | None,
) -> str | None:
    if not candidates:
        return None

    normalized_configured = None
    if configured_address:
        normalized_configured = normalize_ip_literal(str(configured_address))
        if normalized_configured in candidates:
            return normalized_configured

    preferred_network = None
    if preferred_cidr:
        try:
            preferred_network = ipaddress.ip_network(str(preferred_cidr), strict=False)
        except ValueError:
            preferred_network = None

    candidate_ips = [ipaddress.ip_address(item) for item in candidates]
    if preferred_network is not None:
        matching = [item for item in candidate_ips if item in preferred_network]
        if len(matching) == 1:
            return str(matching[0])
        if len(matching) > 1:
            ipv4_matching = [item for item in matching if item.version == 4]
            if len(ipv4_matching) == 1:
                return str(ipv4_matching[0])
            raise SystemExit(
                f"Multiple runtime IPs match preferred network {preferred_network}: {', '.join(str(item) for item in matching)}"
            )

    ipv4_candidates = [item for item in candidate_ips if item.version == 4]
    if len(ipv4_candidates) == 1:
        return str(ipv4_candidates[0])
    if len(candidate_ips) == 1:
        return str(candidate_ips[0])
    raise SystemExit(f"Unable to choose a unique runtime IP from: {', '.join(candidates)}")


def fetch_ct_runtime_ip(workload: dict[str, Any], args: argparse.Namespace) -> str | None:
    if not proxmox_available(args):
        return None

    node = workload.get("node")
    vmid = workload.get("vmid")
    if node is None or vmid is None:
        raise SystemExit(f"CT workload {workload.get('name')} is missing node/vmid for runtime IP resolution.")

    network = workload.get("network", {})
    preferred_cidr = network.get("cidr")
    configured_address = network.get("address")
    mode = str(network.get("mode") or "")
    status_endpoint = f"{args.proxmox_api_url.rstrip('/')}/nodes/{node}/lxc/{vmid}/status/current"
    interfaces_endpoint = f"{args.proxmox_api_url.rstrip('/')}/nodes/{node}/lxc/{vmid}/interfaces"

    try:
        status_response = proxmox_api_request(
            "GET",
            status_endpoint,
            args.proxmox_token_id,
            args.proxmox_token_secret,
            args.proxmox_tls_insecure,
        )
    except ProxmoxRequestError as error:
        if proxmox_error_is_nonfatal(error):
            return None
        raise SystemExit(str(error)) from error

    ct_status = str(status_response.get("data", {}).get("status") or "")
    if mode == "dhcp" and ct_status and ct_status.lower() != "running":
        return None

    for _ in range(1, PROXMOX_DISCOVERY_ATTEMPTS + 1):
        try:
            response = proxmox_api_request(
                "GET",
                interfaces_endpoint,
                args.proxmox_token_id,
                args.proxmox_token_secret,
                args.proxmox_tls_insecure,
            )
        except ProxmoxRequestError as error:
            if proxmox_error_is_nonfatal(error):
                return None
            raise SystemExit(str(error)) from error

        payload = response.get("data", response)
        runtime_ip = choose_runtime_ip(collect_ip_candidates(payload), preferred_cidr, configured_address)
        if runtime_ip is not None:
            return runtime_ip
        if mode != "dhcp":
            return None

        time.sleep(PROXMOX_DISCOVERY_DELAY_SECONDS)

    return None


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
            configured_address = network.get("address")
            mode = network.get("mode")
            services = workload.get("services", [])

            runtime_target_ip: str | None = None
            if workload_kind == "ct":
                runtime_target_ip = fetch_ct_runtime_ip(workload, args)

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
                if traefik_tag not in ingress:
                    raise SystemExit(
                        f"Service {service_name} references unknown Traefik instance {traefik_tag}."
                    )

                traefik_address = ingress[traefik_tag].get("address")
                if not traefik_address:
                    raise SystemExit(f"Traefik instance {traefik_tag} is missing address in ingress.yaml.")

                target_ip = runtime_target_ip
                if target_ip is None and mode == "static" and configured_address:
                    target_ip = normalize_ip_literal(str(configured_address))
                if target_ip is None and workload_kind == "vm" and configured_address:
                    target_ip = normalize_ip_literal(str(configured_address))
                if target_ip is None:
                    print(
                        f"SKIP {workload_kind}/{workload_name}/{service_name}: unable to determine backend IP.",
                        file=sys.stderr,
                    )
                    continue

                checks.append(
                    ServiceCheck(
                        workload_kind=workload_kind,
                        workload_name=workload_name,
                        service_name=service_name,
                        uri=str(uri),
                        traefik_tag=str(traefik_tag),
                        traefik_label=traefik_label,
                        source_ip=normalize_ip_literal(str(traefik_address)),
                        target_ip=target_ip,
                        target_port=int(port),
                    )
                )

    return sorted(checks, key=lambda item: (item.traefik_tag, item.workload_name, item.service_name, item.uri, item.target_port))


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
            section = UciSection(qualified_id=f"{package_name}.{section_id}", section_id=section_id)
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


def sanitize_identifier(text: str) -> str:
    normalized = re.sub(r"[^0-9a-z_]+", "_", text.lower())
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    return normalized or "rule"


def bounded_identifier(*parts: str) -> str:
    raw = sanitize_identifier("_".join(parts))
    if len(raw) <= 63:
        return raw
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:8]
    return f"{raw[:54]}_{digest}"


def port_sort_key(token: str) -> tuple[int, str]:
    return (0, f"{int(token):05d}") if token.isdigit() else (1, token)


def normalize_port_tokens(tokens: list[str]) -> list[str]:
    unique = sorted({token for token in tokens if token}, key=port_sort_key)
    return unique


def desired_rule_options(rule: DesiredRule) -> dict[str, str]:
    return {
        "name": rule.name,
        "enabled": "1",
        "target": "ACCEPT",
        "proto": "tcp",
        "src": rule.source_zone,
        "src_ip": rule.source_ip,
        "dest": rule.target_zone,
        "dest_port": " ".join(rule.dest_ports),
        "family": rule.family,
    }


def current_managed_rule_options(section: UciSection) -> dict[str, str]:
    return {
        "name": option_first(section, "name") or "",
        "enabled": option_first(section, "enabled") or "1",
        "target": option_first(section, "target") or "",
        "proto": " ".join(split_option_words(option_values(section, "proto"))),
        "src": option_first(section, "src") or "",
        "src_ip": " ".join(split_option_words(option_values(section, "src_ip"))),
        "dest": option_first(section, "dest") or "",
        "dest_port": " ".join(normalize_port_tokens(split_option_words(option_values(section, "dest_port")))),
        "family": option_first(section, "family") or "",
    }


def is_managed_rule(section: UciSection) -> bool:
    return section.section_type == "rule" and section.section_id.startswith(MANAGED_RULE_PREFIX)


def build_desired_rules(
    checks: list[ServiceCheck],
    network_sections: list[UciSection],
    firewall_sections: list[UciSection],
    route_cache: dict[str, str],
) -> list[DesiredRule]:
    device_map = build_device_interface_map(network_sections)
    interface_zone_map = build_interface_zone_map(firewall_sections)
    grouped: dict[tuple[str, str, str, str, str], dict[str, set[str]]] = {}

    for check in checks:
        source_route = route_cache[check.source_ip]
        target_route = route_cache[check.target_ip]
        source_device = extract_route_device(source_route)
        target_device = extract_route_device(target_route)
        source_interface = resolve_interface(source_device, device_map)
        target_interface = resolve_interface(target_device, device_map)
        source_zone = interface_zone_map.get(source_interface)
        target_zone = interface_zone_map.get(target_interface)
        if source_zone is None:
            raise SystemExit(f"No firewall zone maps to interface {source_interface} for source IP {check.source_ip}.")
        if target_zone is None:
            raise SystemExit(f"No firewall zone maps to interface {target_interface} for target IP {check.target_ip}.")

        family = "ipv6" if ipaddress.ip_address(check.target_ip).version == 6 else "ipv4"
        print(
            json.dumps(
                {
                    "service": check.service_name,
                    "uri": check.uri,
                    "traefik_tag": check.traefik_tag,
                    "source_ip": check.source_ip,
                    "source_zone": source_zone,
                    "target_ip": check.target_ip,
                    "target_zone": target_zone,
                    "target_port": check.target_port,
                },
                sort_keys=True,
            )
        )
        key = (check.traefik_tag, check.source_ip, source_zone, target_zone, family)
        bucket = grouped.setdefault(
            key,
            {"ports": set(), "workloads": set(), "services": set(), "uris": set()},
        )
        bucket["ports"].add(str(check.target_port))
        bucket["workloads"].add(check.workload_name)
        bucket["services"].add(f"{check.workload_name}/{check.service_name}")
        bucket["uris"].add(check.uri)

    rules: list[DesiredRule] = []
    for (traefik_tag, source_ip, source_zone, target_zone, family), bucket in sorted(grouped.items()):
        name = f"{traefik_tag} -> {target_zone}" if family == "ipv4" else f"{traefik_tag} -> {target_zone} ({family})"
        rules.append(
            DesiredRule(
                section_id=bounded_identifier(MANAGED_RULE_PREFIX.rstrip("_"), traefik_tag, target_zone, family),
                name=name,
                traefik_tag=traefik_tag,
                source_ip=source_ip,
                source_zone=source_zone,
                target_zone=target_zone,
                family=family,
                dest_ports=tuple(normalize_port_tokens(list(bucket["ports"]))),
                workloads=tuple(sorted(bucket["workloads"])),
                services=tuple(sorted(bucket["services"])),
                uris=tuple(sorted(bucket["uris"])),
            )
        )

    return rules


def load_openwrt_client(args: argparse.Namespace) -> OpenWrtClient:
    if not args.openwrt_host or not args.openwrt_password:
        raise SystemExit("OpenWrt host and password are required for firewall reconciliation.")
    return OpenWrtClient(
        host=args.openwrt_host,
        user=args.openwrt_user,
        password=args.openwrt_password,
        port=args.openwrt_port,
        scheme=args.openwrt_scheme,
        tls_insecure=args.openwrt_tls_insecure,
    )


def reconcile_rules(
    client: OpenWrtClient,
    firewall_sections: list[UciSection],
    desired_rules: list[DesiredRule],
    apply: bool,
) -> tuple[bool, list[str]]:
    desired_by_id = {rule.section_id: rule for rule in desired_rules}
    current_by_id = {section.section_id: section for section in firewall_sections if is_managed_rule(section)}
    actions: list[str] = []
    drift = False

    for section_id, rule in desired_by_id.items():
        desired_options = desired_rule_options(rule)
        current = current_by_id.get(section_id)
        if current is None:
            drift = True
            actions.append(f"CREATE {rule.name}: {json.dumps(rule.as_dict(), sort_keys=True)}")
            if apply:
                client.add_section("firewall", "rule", section_id, desired_options)
            continue

        current_options = current_managed_rule_options(current)
        set_values = {key: value for key, value in desired_options.items() if current_options.get(key, "") != value}
        delete_keys = [
            key for key in MANAGED_RULE_OPTION_KEYS if key not in desired_options and option_values(current, key)
        ]
        if set_values or delete_keys:
            drift = True
            actions.append(
                f"UPDATE {rule.name}: {json.dumps({'set': set_values, 'delete': delete_keys}, sort_keys=True)}"
            )
            if apply:
                if set_values:
                    client.set_section_values("firewall", section_id, set_values)
                if delete_keys:
                    client.delete_options("firewall", section_id, delete_keys)
        else:
            actions.append(f"MATCH {rule.name}: {json.dumps(rule.as_dict(), sort_keys=True)}")

    for section_id, current in sorted(current_by_id.items()):
        if section_id in desired_by_id:
            continue
        drift = True
        actions.append(
            f"DELETE {option_first(current, 'name') or section_id}: {json.dumps(current_managed_rule_options(current), sort_keys=True)}"
        )
        if apply:
            client.delete_section("firewall", section_id)

    if apply and drift:
        client.commit("firewall")
        client.reload_firewall()

    return drift, actions


def main() -> int:
    args = parse_args()
    if not args.plan_only and (not args.openwrt_host or not args.openwrt_password):
        print(
            "OpenWrt connection details are required unless --plan-only is used.",
            file=sys.stderr,
        )
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    document = load_inventory_environment(repo_root, args.inventory_root, args.environment)
    checks = build_service_checks(document, args)

    if args.plan_only and not checks:
        print("No Traefik-exposed services produced firewall checks.")

    client = load_openwrt_client(args)
    network_sections = parse_uci_show(client.show_config("network"), "network")
    firewall_sections = parse_uci_show(client.show_config("firewall"), "firewall")

    route_cache: dict[str, str] = {}
    unique_ips = sorted({check.source_ip for check in checks} | {check.target_ip for check in checks})
    for ip_text in unique_ips:
        route_cache[ip_text] = client.route_get(ip_text)

    desired_rules = build_desired_rules(checks, network_sections, firewall_sections, route_cache)
    if args.plan_only:
        print("DESIRED_RULES")
        for rule in desired_rules:
            print(json.dumps(rule.as_dict(), sort_keys=True))

    drift, actions = reconcile_rules(client, firewall_sections, desired_rules, args.apply)
    for action in actions:
        print(action)

    if drift and not args.apply:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
