#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import ssl
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


FALSE_VALUES = {"0", "false", "no", "off", ""}
MANUAL_FEATURE_KEYS = {"nesting", "keyctl", "fuse", "mount"}
LOCK_TIMEOUT_MARKERS = ("trying to acquire lock", "can't lock file")
LOCK_RETRY_ATTEMPTS = 24
LOCK_RETRY_DELAY_SECONDS = 5
OPTIONAL_CONFIG_FIELDS = ("description", "nameserver", "searchdomain")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply post-create Proxmox CT feature and config reconciliation via the Proxmox API or local pct CLI."
    )
    parser.add_argument("--node", required=True, help="Target Proxmox node name.")
    parser.add_argument("--vmid", required=True, type=int, help="Container VMID.")
    parser.add_argument("--nesting", action="store_true", help="Enable nesting=1.")
    parser.add_argument("--keyctl", action="store_true", help="Enable keyctl=1.")
    parser.add_argument("--fuse", action="store_true", help="Enable fuse=1.")
    parser.add_argument("--mount", default="", help="Set mount=<value>.")
    parser.add_argument("--description", default=None, help="Set CT description.")
    parser.add_argument("--delete-description", action="store_true", help="Delete CT description.")
    parser.add_argument("--nameserver", default=None, help="Set CT nameserver.")
    parser.add_argument("--delete-nameserver", action="store_true", help="Delete CT nameserver.")
    parser.add_argument("--searchdomain", default=None, help="Set CT search domain.")
    parser.add_argument("--delete-searchdomain", action="store_true", help="Delete CT search domain.")
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
    if args.nesting:
        tokens.append("nesting=1")
    if args.keyctl:
        tokens.append("keyctl=1")
    if args.fuse:
        tokens.append("fuse=1")
    mount_value = args.mount.strip()
    if mount_value:
        tokens.append(f"mount={mount_value}")
    return tokens


def normalize_feature_tokens(tokens: list[str]) -> list[str]:
    return sorted(token.strip() for token in tokens if token.strip())


def feature_key(token: str) -> str:
    return token.split("=", 1)[0].strip()


def parse_feature_tokens(value: str) -> dict[str, str]:
    tokens: dict[str, str] = {}
    for raw_token in value.split(","):
        token = raw_token.strip()
        if not token:
            continue
        tokens[feature_key(token)] = token
    return tokens


def merge_feature_tokens(current_value: str, desired_manual_tokens: list[str]) -> list[str]:
    current_tokens = parse_feature_tokens(current_value)
    unmanaged_tokens = [
        token for key, token in current_tokens.items() if key not in MANUAL_FEATURE_KEYS
    ]
    return normalize_feature_tokens(unmanaged_tokens + desired_manual_tokens)


def normalize_config_value(field: str, value: str) -> str:
    if field == "description":
        return value.rstrip()
    return value.strip()


def build_desired_config_values(args: argparse.Namespace) -> dict[str, str]:
    desired: dict[str, str] = {}
    for field in OPTIONAL_CONFIG_FIELDS:
        delete_attr = f"delete_{field}"
        value = getattr(args, field)
        if getattr(args, delete_attr):
            desired[field] = ""
        else:
            desired[field] = normalize_config_value(field, "" if value is None else str(value))
    return desired


def extract_current_config_values(current_data: dict[str, Any]) -> dict[str, str]:
    return {
        field: normalize_config_value(field, "" if current_data.get(field) is None else str(current_data.get(field)))
        for field in OPTIONAL_CONFIG_FIELDS
    }


def make_context(tls_insecure: bool) -> ssl.SSLContext | None:
    if not tls_insecure:
        return None
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def api_error_is_lock_timeout(status_code: int, body: str) -> bool:
    if status_code not in {409, 500}:
        return False
    detail = body.lower()
    return any(marker in detail for marker in LOCK_TIMEOUT_MARKERS)


def api_request(
    method: str,
    url: str,
    token_id: str,
    token_secret: str,
    tls_insecure: bool,
    data: dict[str, str] | None = None,
    retry_on_lock: bool = False,
) -> Any:
    headers = {
        "Authorization": f"PVEAPIToken={token_id}={token_secret}",
    }
    payload = None
    if data is not None:
        payload = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    context = make_context(tls_insecure)
    attempts = LOCK_RETRY_ATTEMPTS if retry_on_lock else 1

    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, context=context) as response:
                body = response.read().decode("utf-8")
                if not body:
                    return {}
                return json.loads(body)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if retry_on_lock and attempt < attempts and api_error_is_lock_timeout(exc.code, body):
                time.sleep(LOCK_RETRY_DELAY_SECONDS)
                continue
            raise SystemExit(f"Proxmox API {method} {url} failed with HTTP {exc.code}: {body}") from exc
        except urllib.error.URLError as exc:
            raise SystemExit(f"Proxmox API {method} {url} failed: {exc.reason}") from exc

    raise SystemExit(f"Proxmox API {method} {url} failed after exhausting lock retries.")


def pct_available() -> bool:
    return os.geteuid() == 0 and shutil.which("pct") is not None


def pct_run(command: list[str]) -> str:
    for attempt in range(1, LOCK_RETRY_ATTEMPTS + 1):
        try:
            completed = subprocess.run(command, check=True, capture_output=True, text=True)
            return (completed.stdout or "").strip()
        except subprocess.CalledProcessError as exc:
            stderr = (exc.stderr or "").strip()
            stdout = (exc.stdout or "").strip()
            detail = stderr or stdout or str(exc)
            detail_lower = detail.lower()
            if attempt < LOCK_RETRY_ATTEMPTS and any(marker in detail_lower for marker in LOCK_TIMEOUT_MARKERS):
                time.sleep(LOCK_RETRY_DELAY_SECONDS)
                continue
            raise SystemExit(f"pct command failed ({' '.join(command)}): {detail}") from exc

    raise SystemExit(f"pct command failed after exhausting retries: {' '.join(command)}")


def pct_update_features(vmid: int, target_tokens: list[str]) -> str:
    if target_tokens:
        command = ["pct", "set", str(vmid), "-features", ",".join(target_tokens)]
    else:
        command = ["pct", "set", str(vmid), "-delete", "features"]
    return pct_run(command)


def pct_reconcile_config(vmid: int, current_values: dict[str, str], desired_values: dict[str, str]) -> dict[str, Any]:
    delete_fields: list[str] = []
    set_args: list[str] = []
    set_values: dict[str, str] = {}

    for field in OPTIONAL_CONFIG_FIELDS:
        current = current_values.get(field, "")
        desired = desired_values.get(field, "")
        if desired == "":
            if current != "":
                delete_fields.append(field)
            continue
        if current != desired:
            set_args.extend([f"-{field}", desired])
            set_values[field] = desired

    if delete_fields:
        pct_run(["pct", "set", str(vmid), "-delete", ",".join(delete_fields)])
    if set_args:
        pct_run(["pct", "set", str(vmid)] + set_args)

    return {
        "deleted": delete_fields,
        "set": set_values,
    }


def build_api_update_data(
    current_tokens: list[str],
    target_tokens: list[str],
    current_config_values: dict[str, str],
    desired_config_values: dict[str, str],
) -> dict[str, str]:
    update_data: dict[str, str] = {}
    delete_fields: list[str] = []

    if current_tokens != target_tokens:
        if target_tokens:
            update_data["features"] = ",".join(target_tokens)
        else:
            delete_fields.append("features")

    for field in OPTIONAL_CONFIG_FIELDS:
        current = current_config_values.get(field, "")
        desired = desired_config_values.get(field, "")
        if desired == "":
            if current != "":
                delete_fields.append(field)
        elif current != desired:
            update_data[field] = desired

    if delete_fields:
        update_data["delete"] = ",".join(delete_fields)

    return update_data


def main() -> int:
    args = parse_args()
    for field in OPTIONAL_CONFIG_FIELDS:
        if getattr(args, field) is not None and getattr(args, f"delete_{field}"):
            raise SystemExit(f"--{field} cannot be combined with --delete-{field}.")

    for name, value in (
        ("api-url", args.api_url),
        ("token-id", args.token_id),
        ("token-secret", args.token_secret),
    ):
        if not value:
            raise SystemExit(f"--{name} or matching environment variable is required.")

    desired_manual_tokens = build_feature_tokens(args)
    desired_config_values = build_desired_config_values(args)
    config_url = f"{args.api_url.rstrip('/')}/nodes/{urllib.parse.quote(args.node, safe='')}/lxc/{args.vmid}/config"

    current_response = api_request(
        "GET",
        config_url,
        args.token_id,
        args.token_secret,
        args.tls_insecure,
    )
    current_data = current_response.get("data", {})
    current_value = str(current_data.get("features") or "")
    current_tokens = normalize_feature_tokens(list(parse_feature_tokens(current_value).values()))
    target_tokens = merge_feature_tokens(current_value, desired_manual_tokens)
    current_config_values = extract_current_config_values(current_data)

    features_changed = current_tokens != target_tokens
    config_changed = current_config_values != desired_config_values

    if not features_changed and not config_changed:
        print(
            json.dumps(
                {
                    "node": args.node,
                    "vmid": args.vmid,
                    "changed": False,
                    "features": target_tokens,
                    "config": desired_config_values,
                },
                sort_keys=True,
            )
        )
        return 0

    response_data: Any = None
    if pct_available():
        response: dict[str, Any] = {}
        if features_changed:
            response["features"] = pct_update_features(args.vmid, target_tokens)
        if config_changed:
            response["config"] = pct_reconcile_config(args.vmid, current_config_values, desired_config_values)
        response_data = response
    else:
        update_data = build_api_update_data(
            current_tokens,
            target_tokens,
            current_config_values,
            desired_config_values,
        )
        update_response = api_request(
            "PUT",
            config_url,
            args.token_id,
            args.token_secret,
            args.tls_insecure,
            data=update_data,
            retry_on_lock=True,
        )
        response_data = update_response.get("data")

    print(
        json.dumps(
            {
                "node": args.node,
                "vmid": args.vmid,
                "changed": True,
                "features": target_tokens,
                "config": desired_config_values,
                "response": response_data,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
