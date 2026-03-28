#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit


def build_proxmox_base(manifest: dict[str, Any]) -> dict[str, Any]:
    proxmox = manifest["proxmox"]
    bootstrap = manifest["bootstrap"]
    return {
        "proxmox_api_url": proxmox["api_url"],
        "proxmox_api_token_id": proxmox["api_token_id"],
        "proxmox_api_token": proxmox["api_token"],
        "proxmox_tls_insecure": bool(proxmox.get("tls_insecure", False)),
        "root_password": bootstrap["root_password"],
    }


def build_openwrt_dns(manifest: dict[str, Any]) -> dict[str, Any]:
    proxmox = manifest["proxmox"]
    openwrt = manifest["openwrt"]
    return {
        "environment": manifest["environment"],
        "openwrt_hostname": openwrt["hostname"],
        "openwrt_port": openwrt["port"],
        "openwrt_scheme": openwrt["scheme"],
        "openwrt_username": openwrt["username"],
        "openwrt_password": openwrt["password"],
        "openwrt_firewall_enabled": bool(openwrt.get("firewall_enabled", True)),
        "openwrt_firewall_apply": bool(openwrt.get("firewall_apply", True)),
        "openwrt_firewall_ssh_host": openwrt.get("firewall_ssh_host", openwrt["hostname"]),
        "openwrt_firewall_ssh_port": openwrt.get("firewall_ssh_port", 22),
        "openwrt_firewall_ssh_user": openwrt.get("firewall_ssh_user", "root"),
        "proxmox_api_url": proxmox["api_url"],
        "proxmox_api_token_id": proxmox["api_token_id"],
        "proxmox_api_token": proxmox["api_token"],
        "proxmox_tls_insecure": bool(proxmox.get("tls_insecure", False)),
    }


def normalize_proxmox_api_endpoint(api_url: str) -> str:
    parsed = urlsplit(api_url)
    path = parsed.path.rstrip("/")
    if path.endswith("/api2/json"):
        path = path[: -len("/api2/json")]
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))


def build_traefik_proxmox_provider_env(manifest: dict[str, Any]) -> dict[str, str]:
    proxmox = manifest["proxmox"]
    traefik = manifest.get("traefik_proxmox_provider", {})
    validate_ssl = bool(traefik.get("api_validate_ssl", not bool(proxmox.get("tls_insecure", False))))

    payload = {
        "PROXMOX_API_ENDPOINT": str(traefik.get("api_endpoint", normalize_proxmox_api_endpoint(proxmox["api_url"]))),
        "PROXMOX_TOKEN_ID": str(traefik.get("api_token_id", proxmox["api_token_id"])),
        "PROXMOX_TOKEN_SECRET": str(traefik.get("api_token", proxmox["api_token"])),
        "PROXMOX_POLL_INTERVAL": str(traefik.get("poll_interval", "30s")),
        "PROXMOX_API_LOGGING": str(traefik.get("api_logging", "info")),
        "PROXMOX_API_VALIDATE_SSL": "true" if validate_ssl else "false",
    }

    if "label_prefix" in traefik:
        payload["TRAEFIK_PROXMOX_LABEL_PREFIX"] = str(traefik["label_prefix"])
    if "plugin_module_name" in traefik:
        payload["TRAEFIK_PROXMOX_PLUGIN_MODULE_NAME"] = str(traefik["plugin_module_name"])
    if "plugin_version" in traefik:
        payload["TRAEFIK_PROXMOX_PLUGIN_VERSION"] = str(traefik["plugin_version"])

    return payload


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_env(path: Path, payload: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{key}={value}" for key, value in payload.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render local Terraform tfvars files from a credentials manifest.")
    parser.add_argument("--manifest", required=True, help="Path to the consolidated credentials manifest JSON.")
    parser.add_argument("--output-dir", required=True, help="Directory where rendered tfvars files will be written.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    environment = manifest["environment"]

    write_json(output_dir / f"{environment}-proxmox-base.tfvars.json", build_proxmox_base(manifest))
    write_json(output_dir / f"{environment}-openwrt-dns.tfvars.json", build_openwrt_dns(manifest))
    write_json(output_dir / f"{environment}-external-hosts.json", {"environment": environment, "hosts": manifest["hosts"]})
    write_env(output_dir / f"{environment}-traefik-proxmox-provider.env", build_traefik_proxmox_provider_env(manifest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
