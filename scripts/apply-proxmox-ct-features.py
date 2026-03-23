#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


FALSE_VALUES = {"0", "false", "no", "off", ""}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply post-create manual Proxmox CT features via the Proxmox API."
    )
    parser.add_argument("--node", required=True, help="Target Proxmox node name.")
    parser.add_argument("--vmid", required=True, type=int, help="Container VMID.")
    parser.add_argument("--keyctl", action="store_true", help="Enable keyctl=1.")
    parser.add_argument("--fuse", action="store_true", help="Enable fuse=1.")
    parser.add_argument("--create", action="store_true", help="Enable create=1.")
    parser.add_argument("--mount", default="", help="Set mount=<value>.")
    parser.add_argument(
        "--api-url",
        default=os.environ.get("PROXMOX_API_URL"),
        help="Proxmox API URL. Defaults to PROXMOX_API_URL.",
    )
    parser.add_argument(
        "--token-id",
        default=os.environ.get("PROXMOX_API_TOKEN_ID"),
        help="Proxmox API token ID. Defaults to PROXMOX_API_TOKEN_ID.",
    )
    parser.add_argument(
        "--token-secret",
        default=os.environ.get("PROXMOX_API_TOKEN_SECRET") or os.environ.get("PROXMOX_API_TOKEN"),
        help="Proxmox API token secret. Defaults to PROXMOX_API_TOKEN_SECRET or PROXMOX_API_TOKEN.",
    )
    parser.add_argument(
        "--tls-insecure",
        action="store_true",
        default=(os.environ.get("PROXMOX_TLS_INSECURE", "true").strip().lower() not in FALSE_VALUES),
        help="Disable TLS verification. Defaults to PROXMOX_TLS_INSECURE or true.",
    )
    return parser.parse_args()


def build_feature_tokens(args: argparse.Namespace) -> list[str]:
    tokens: list[str] = []
    if args.keyctl:
        tokens.append("keyctl=1")
    if args.fuse:
        tokens.append("fuse=1")
    mount_value = args.mount.strip()
    if mount_value:
        tokens.append(f"mount={mount_value}")
    if args.create:
        tokens.append("create=1")
    return tokens


def normalize_feature_string(value: str) -> list[str]:
    tokens = [token.strip() for token in value.split(",") if token.strip()]
    return sorted(tokens)


def make_context(tls_insecure: bool) -> ssl.SSLContext | None:
    if not tls_insecure:
        return None
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def api_request(
    method: str,
    url: str,
    token_id: str,
    token_secret: str,
    tls_insecure: bool,
    data: dict[str, str] | None = None,
) -> Any:
    headers = {
        "Authorization": f"PVEAPIToken={token_id}={token_secret}",
    }
    payload = None
    if data is not None:
        payload = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    request = urllib.request.Request(url, data=payload, headers=headers, method=method)
    context = make_context(tls_insecure)

    try:
        with urllib.request.urlopen(request, context=context) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Proxmox API {method} {url} failed with HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Proxmox API {method} {url} failed: {exc.reason}") from exc

    if not body:
        return {}
    return json.loads(body)


def main() -> int:
    args = parse_args()
    for name, value in (
        ("api-url", args.api_url),
        ("token-id", args.token_id),
        ("token-secret", args.token_secret),
    ):
        if not value:
            raise SystemExit(f"--{name} or matching environment variable is required.")

    feature_tokens = build_feature_tokens(args)
    if not feature_tokens:
        print(json.dumps({"node": args.node, "vmid": args.vmid, "changed": False, "features": []}, sort_keys=True))
        return 0

    features_value = ",".join(feature_tokens)
    config_url = f"{args.api_url.rstrip('/')}/nodes/{urllib.parse.quote(args.node, safe='')}/lxc/{args.vmid}/config"

    current_response = api_request(
        "GET",
        config_url,
        args.token_id,
        args.token_secret,
        args.tls_insecure,
    )
    current_value = str(current_response.get("data", {}).get("features") or "")
    if normalize_feature_string(current_value) == normalize_feature_string(features_value):
        print(
            json.dumps(
                {
                    "node": args.node,
                    "vmid": args.vmid,
                    "changed": False,
                    "features": normalize_feature_string(features_value),
                },
                sort_keys=True,
            )
        )
        return 0

    update_response = api_request(
        "PUT",
        config_url,
        args.token_id,
        args.token_secret,
        args.tls_insecure,
        data={"features": features_value},
    )
    print(
        json.dumps(
            {
                "node": args.node,
                "vmid": args.vmid,
                "changed": True,
                "features": normalize_feature_string(features_value),
                "response": update_response.get("data"),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
