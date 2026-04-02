from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "render-local-tfvars.py"


class RenderLocalTfvarsTest(unittest.TestCase):
    def test_render_local_tfvars_writes_expected_outputs(self) -> None:
        manifest = {
            "environment": "dev",
            "bootstrap": {
                "root_password": "bootstrap-secret",
            },
            "proxmox": {
                "api_url": "https://192.168.99.100:8006/api2/json",
                "password": "proxmox-root-password",
                "api_token_id": "root@pam!terraform-local",
                "api_token": "proxmox-secret",
                "tls_insecure": True,
            },
            "openwrt": {
                "hostname": "192.168.99.200",
                "port": 80,
                "scheme": "http",
                "username": "root",
                "password": "openwrt-secret",
                "firewall_enabled": True,
                "firewall_apply": True,
                "firewall_ssh_host": "192.168.99.200",
                "firewall_ssh_port": 22,
                "firewall_ssh_user": "root",
            },
            "hosts": {
                "dev-proxmox": {
                    "kind": "proxmox",
                    "address": "192.168.99.100",
                    "ssh_user": "root",
                    "ssh_private_key_path": "/mnt/data/ssh/id_ed25519_lab_hosts",
                    "api_token_id": "root@pam!terraform-local",
                    "api_token_secret": "proxmox-secret",
                },
                "DEV-openwrt": {
                    "kind": "openwrt",
                    "address": "192.168.99.200",
                    "ssh_user": "root",
                    "ssh_private_key_path": "/mnt/data/ssh/id_ed25519_lab_hosts",
                    "username": "root",
                    "password": "openwrt-secret",
                },
            },
            "traefik_proxmox_provider": {
                "poll_interval": "45s",
                "api_logging": "debug",
                "plugin_module_name": "github.com/lmbalcao/traefik-proxmox-provider",
                "plugin_version": "v0.1.0",
            },
        }

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            manifest_path = tmp_path / "manifest.json"
            output_dir = tmp_path / "out"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest_path), "--output-dir", str(output_dir)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)

            proxmox_base = json.loads((output_dir / "dev-proxmox-base.tfvars.json").read_text(encoding="utf-8"))
            openwrt_dns = json.loads((output_dir / "dev-openwrt-dns.tfvars.json").read_text(encoding="utf-8"))
            hosts_manifest = json.loads((output_dir / "dev-external-hosts.json").read_text(encoding="utf-8"))
            traefik_env = dict(
                line.split("=", 1)
                for line in (output_dir / "dev-traefik-proxmox-provider.env").read_text(encoding="utf-8").splitlines()
                if line
            )

            self.assertEqual(
                proxmox_base,
                {
                    "proxmox_api_url": "https://192.168.99.100:8006/api2/json",
                    "proxmox_password": "proxmox-root-password",
                    # Optional token pass-throughs kept so GUI tfvars files remain valid.
                    "proxmox_api_token_id": "root@pam!terraform-local",
                    "proxmox_api_token": "proxmox-secret",
                    "proxmox_tls_insecure": True,
                    "root_password": "bootstrap-secret",
                },
            )
            self.assertEqual(
                openwrt_dns,
                {
                    "environment": "dev",
                    "openwrt_hostname": "192.168.99.200",
                    "openwrt_port": 80,
                    "openwrt_scheme": "http",
                    "openwrt_username": "root",
                    "openwrt_password": "openwrt-secret",
                    "openwrt_firewall_enabled": True,
                    "openwrt_firewall_apply": True,
                    "openwrt_firewall_ssh_host": "192.168.99.200",
                    "openwrt_firewall_ssh_port": 22,
                    "openwrt_firewall_ssh_user": "root",
                    "proxmox_api_url": "https://192.168.99.100:8006/api2/json",
                    "proxmox_api_token_id": "root@pam!terraform-local",
                    "proxmox_api_token": "proxmox-secret",
                    "proxmox_tls_insecure": True,
                },
            )
            self.assertEqual(hosts_manifest["hosts"]["dev-proxmox"]["api_token_id"], "root@pam!terraform-local")
            self.assertEqual(hosts_manifest["hosts"]["DEV-openwrt"]["password"], "openwrt-secret")
            self.assertEqual(
                traefik_env,
                {
                    "PROXMOX_API_ENDPOINT": "https://192.168.99.100:8006",
                    "PROXMOX_TOKEN_ID": "root@pam!terraform-local",
                    "PROXMOX_TOKEN_SECRET": "proxmox-secret",
                    "PROXMOX_POLL_INTERVAL": "45s",
                    "PROXMOX_API_LOGGING": "debug",
                    "PROXMOX_API_VALIDATE_SSL": "false",
                    "TRAEFIK_PROXMOX_PLUGIN_MODULE_NAME": "github.com/lmbalcao/traefik-proxmox-provider",
                    "TRAEFIK_PROXMOX_PLUGIN_VERSION": "v0.1.0",
                },
            )


if __name__ == "__main__":
    unittest.main()
