#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


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


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
