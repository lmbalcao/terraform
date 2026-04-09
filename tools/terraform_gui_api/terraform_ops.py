from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Any


def _run(repo_root: Path, args: list[str]) -> dict[str, Any]:
    container = os.environ.get("TERRAFORM_CONTAINER", "").strip()
    effective_args = ["docker", "exec", container] + args if container else args
    completed = subprocess.run(
        effective_args,
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    raw_output = ((completed.stdout or "") + (completed.stderr or "")).strip()
    return {
        "command": args,
        "exit_code": completed.returncode,
        "raw_output": raw_output,
    }


def summarize_plan_output(raw_output: str) -> dict[str, Any]:
    if "No changes." in raw_output:
        return {"status": "no_changes", "line": "No changes."}

    match = re.search(r"Plan:\s+(\d+)\s+to add,\s+(\d+)\s+to change,\s+(\d+)\s+to destroy\.", raw_output)
    if match:
        return {
            "status": "changes",
            "add": int(match.group(1)),
            "change": int(match.group(2)),
            "destroy": int(match.group(3)),
        }

    return {"status": "unknown", "line": next((line for line in reversed(raw_output.splitlines()) if line.strip()), "")}


def summarize_apply_output(raw_output: str) -> dict[str, Any]:
    match = re.search(r"Apply complete!\s+Resources:\s+(\d+)\s+added,\s+(\d+)\s+changed,\s+(\d+)\s+destroyed\.", raw_output)
    if match:
        return {
            "status": "applied",
            "add": int(match.group(1)),
            "change": int(match.group(2)),
            "destroy": int(match.group(3)),
        }

    if "No changes." in raw_output:
        return {"status": "no_changes", "line": "No changes."}

    return {"status": "unknown", "line": next((line for line in reversed(raw_output.splitlines()) if line.strip()), "")}


def _openwrt_tfvars_exists(repo_root: Path, environment: str) -> bool:
    return (repo_root / "env" / environment / "openwrt-dns.tfvars").exists()


def run_plan(repo_root: Path, environment: str) -> dict[str, Any]:
    result = _run(repo_root, ["bash", "scripts/plan-stack.sh", "proxmox-base", environment, "-no-color"])
    result["summary"] = summarize_plan_output(result["raw_output"])

    if _openwrt_tfvars_exists(repo_root, environment):
        openwrt_result = _run(repo_root, ["bash", "scripts/plan-stack.sh", "openwrt-dns", environment, "-no-color"])
        result["raw_output"] += f"\n\n=== openwrt-dns plan ===\n{openwrt_result['raw_output']}"
        result["openwrt_plan"] = openwrt_result

    return result


def run_apply(repo_root: Path, environment: str) -> dict[str, Any]:
    result = _run(repo_root, ["bash", "scripts/apply-stack.sh", "proxmox-base", environment, "-no-color"])
    result["summary"] = summarize_apply_output(result["raw_output"])

    if _openwrt_tfvars_exists(repo_root, environment):
        openwrt_result = _run(repo_root, ["bash", "scripts/apply-stack.sh", "openwrt-dns", environment, "-no-color"])
        result["raw_output"] += f"\n\n=== openwrt-dns apply ===\n{openwrt_result['raw_output']}"
        result["openwrt_apply"] = openwrt_result
        if openwrt_result["exit_code"] != 0:
            result["exit_code"] = openwrt_result["exit_code"]

    return result

