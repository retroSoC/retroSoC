#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, lock_digest, load_lock  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402


TOOLS = {
    "python": ("python3", "--version"),
    "make": ("make", "--version"),
    "riscv_gcc": ("riscv32-unknown-elf-gcc", "--version"),
    "iverilog": ("iverilog", "-V"),
    "verilator": ("verilator", "--version"),
    "yosys": ("yosys", "--version"),
    "opensta": ("sta", "-version"),
}


def command_output(command: tuple[str, ...]) -> str | None:
    if shutil.which(command[0]) is None:
        return None
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    output = (result.stdout or result.stderr).strip().splitlines()
    return output[0] if output else None


def git_info(root: Path) -> dict[str, object]:
    def git(*args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL
        ).strip()

    try:
        return {
            "commit": git("rev-parse", "HEAD"),
            "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(git("status", "--porcelain")),
        }
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"commit": "unknown", "branch": "unknown", "dirty": None}


def parse_pairs(values: list[str]) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for item in values:
        key, separator, value = item.partition("=")
        if not separator or not key or key in parsed:
            raise ValueError(f"invalid or duplicate key=value item: {item}")
        parsed[key] = value
    return dict(sorted(parsed.items()))


def file_hashes(root: Path) -> dict[str, str]:
    hashes: dict[str, str] = {}
    if not root.exists():
        return hashes
    for path in sorted(root.rglob("*.fl")):
        hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def create_manifest(args: argparse.Namespace) -> dict[str, object]:
    root = args.root.resolve()
    lock = args.lock.resolve()
    load_lock(lock)
    variant_root = args.output.resolve().parents[1]
    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "repository": git_info(root),
        "profile": args.profile,
        "configuration": parse_pairs(args.config),
        "dependency_lock": {
            "path": str(lock.relative_to(root)),
            "sha256": lock_digest(lock),
        },
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
        },
        "tools": {name: command_output(command) for name, command in TOOLS.items()},
        "filelists": file_hashes(variant_root),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a retroSoC build manifest")
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--root", type=Path, required=True)
    create.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--profile", required=True)
    create.add_argument("--config", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        data = create_manifest(args)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    atomic_write(args.output, json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(f"manifest: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
