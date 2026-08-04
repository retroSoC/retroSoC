#!/usr/bin/env python3
"""Generate native RIBP MPW sources from the locked mini-ver-mpw manifest."""

from __future__ import annotations

import argparse
import fcntl
import json
import subprocess
import sys
from pathlib import Path


def generate(root: Path, output: Path) -> None:
    managed_mpw = root / "rtl/managed/mpw"
    manifest = managed_mpw / "mpw.toml"
    if not manifest.is_file():
        raise FileNotFoundError(f"MPW v2 manifest is missing: {manifest}")
    command = [
        sys.executable,
        "-m",
        "mpwgen",
        "generate",
        "--manifest",
        str(manifest),
        "--output",
        str(output),
    ]
    subprocess.run(command, cwd=managed_mpw, check=True)
    validate_extension_bindings(root, output)


def validate_extension_bindings(root: Path, output: Path) -> None:
    """Require SoC slot bindings to match the generated MPW v2 manifest."""
    extensions_path = root / "rtl/mini/integration/user_extensions.json"
    manifest_path = output / "manifest.json"
    extensions = json.loads(extensions_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    designs = manifest.get("designs")
    if not isinstance(designs, list):
        raise ValueError("generated MPW manifest has no design list")
    for kind, target_key in (("core", "core_targets"), ("ip", "ip_targets")):
        expected: dict[object, object] = {}
        for design in designs:
            if not isinstance(design, dict) or design.get("kind") != kind:
                continue
            slot = design.get("slot")
            if slot in expected:
                raise ValueError(f"generated MPW manifest duplicates {kind} slot {slot}")
            expected[slot] = design
        targets = extensions.get(target_key)
        if not isinstance(targets, list):
            raise ValueError(f"{extensions_path}: {target_key} must be a list")
        actual: dict[object, object] = {}
        for target in targets:
            if not isinstance(target, dict):
                raise ValueError(f"{extensions_path}: {target_key} contains a non-object entry")
            slot = target.get("slot")
            if slot in actual:
                raise ValueError(f"{extensions_path}: {target_key} duplicates slot {slot}")
            actual[slot] = target
        if set(actual) != set(expected):
            raise ValueError(f"{extensions_path}: {target_key} slots do not match MPW v2")
        for slot, design in expected.items():
            target = actual[slot]
            if target.get("module") != design.get("top"):
                raise ValueError(
                    f"{extensions_path}: {kind} slot {slot} does not match {design.get('top')}"
                )
            if kind == "core" and target.get("reset") != design.get("reset"):
                raise ValueError(f"{extensions_path}: core slot {slot} reset type does not match MPW v2")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock-file", required=True, type=Path)
    arguments = parser.parse_args()
    arguments.lock_file.parent.mkdir(parents=True, exist_ok=True)
    with arguments.lock_file.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        generate(arguments.root.resolve(), arguments.output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
