from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def runtime_dir(repo_root: Path) -> Path:
    path = repo_root / ".cache" / "terraform-gui-api"
    path.mkdir(parents=True, exist_ok=True)
    return path


def drafts_path(repo_root: Path, environment: str) -> Path:
    return runtime_dir(repo_root) / f"drafts-{environment}.json"


def load_drafts(repo_root: Path, environment: str) -> list[dict[str, Any]]:
    path = drafts_path(repo_root, environment)
    if not path.exists():
        return []
    payload = json.loads(path.read_text(encoding="utf-8"))
    drafts = payload.get("drafts", [])
    return drafts if isinstance(drafts, list) else []


def save_drafts(repo_root: Path, environment: str, drafts: list[dict[str, Any]]) -> None:
    path = drafts_path(repo_root, environment)
    payload = {"environment": environment, "drafts": drafts}
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def clear_drafts(repo_root: Path, environment: str) -> None:
    path = drafts_path(repo_root, environment)
    if path.exists():
        path.unlink()


def clear_all_drafts(repo_root: Path) -> None:
    for path in runtime_dir(repo_root).glob("drafts-*.json"):
        path.unlink()

