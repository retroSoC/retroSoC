#!/usr/bin/env python3
"""Generate native RIBP MPW sources from the locked mini-ver-mpw manifest."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10
    import tomli as tomllib


def toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return "[" + ", ".join(json.dumps(item, ensure_ascii=True) for item in value) + "]"
    raise ValueError(f"unsupported MPW manifest value: {value!r}")


def render_active_manifest(manifest_path: Path, extensions_path: Path) -> str:
    """Select and renumber locked MPW designs from the self-owned extension map."""
    document = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
    if document.get("schema_version") != 2:
        raise ValueError(f"{manifest_path}: schema_version must be 2")
    generator = document.get("generator")
    if not isinstance(generator, dict):
        raise ValueError(f"{manifest_path}: generator must be a table")
    designs = document.get("design")
    if not isinstance(designs, list):
        raise ValueError(f"{manifest_path}: design must be an array")

    available: dict[tuple[str, str], dict[str, Any]] = {}
    for design in designs:
        if not isinstance(design, dict):
            raise ValueError(f"{manifest_path}: design contains a non-table entry")
        key = (design.get("kind"), design.get("id"))
        if not all(isinstance(item, str) for item in key):
            raise ValueError(f"{manifest_path}: every design requires string kind and id")
        if key in available:
            raise ValueError(f"{manifest_path}: duplicate {key[0]} design id {key[1]}")
        available[key] = design

    extensions = json.loads(extensions_path.read_text(encoding="utf-8"))
    if not isinstance(extensions, dict) or extensions.get("schema_version") != 2:
        raise ValueError(f"{extensions_path}: schema_version must be 2")
    selected: list[dict[str, Any]] = []
    selected_ids: set[tuple[str, str]] = set()
    for kind, target_key in (("core", "core_targets"), ("ip", "ip_targets")):
        targets = extensions.get(target_key)
        if not isinstance(targets, list):
            raise ValueError(f"{extensions_path}: {target_key} must be a list")
        for index, target in enumerate(targets):
            if not isinstance(target, dict):
                raise ValueError(f"{extensions_path}: {target_key}[{index}] must be an object")
            design_id = target.get("design_id")
            slot = target.get("slot")
            key = (kind, design_id)
            if not isinstance(design_id, str) or key not in available:
                raise ValueError(
                    f"{extensions_path}: {target_key}[{index}] selects unknown {kind} design {design_id!r}"
                )
            if key in selected_ids:
                raise ValueError(f"{extensions_path}: {kind} design {design_id} is selected more than once")
            if not isinstance(slot, int) or slot < 0:
                raise ValueError(f"{extensions_path}: {target_key}[{index}].slot must be non-negative")
            expected_module = f"mpw_{kind[0]}{slot}"
            if target.get("module") != expected_module:
                raise ValueError(
                    f"{extensions_path}: {target_key}[{index}].module must be {expected_module}"
                )
            design = dict(available[key])
            if kind == "core" and target.get("reset") != design.get("reset"):
                raise ValueError(
                    f"{extensions_path}: {target_key}[{index}].reset does not match {design_id}"
                )
            design["slot"] = slot
            design.pop("enabled", None)
            selected.append(design)
            selected_ids.add(key)

    lines = [f"schema_version = {document['schema_version']}", "", "[generator]"]
    lines.extend(f"{key} = {toml_value(value)}" for key, value in generator.items())
    for design in selected:
        lines.extend(["", "[[design]]"])
        lines.extend(f"{key} = {toml_value(value)}" for key, value in design.items())
    return "\n".join(lines) + "\n"


def generate(root: Path, output: Path, extensions: Path) -> None:
    managed_mpw = root / "rtl/managed/mpw"
    manifest = managed_mpw / "mpw.toml"
    if not manifest.is_file():
        raise FileNotFoundError(f"MPW v2 manifest is missing: {manifest}")
    descriptor, manifest_name = tempfile.mkstemp(
        prefix=".retrosoc-active-", suffix=".toml", dir=managed_mpw
    )
    active_manifest = Path(manifest_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(render_active_manifest(manifest, extensions))
        command = [
            sys.executable,
            "-m",
            "mpwgen",
            "generate",
            "--manifest",
            str(active_manifest),
            "--output",
            str(output),
        ]
        subprocess.run(command, cwd=managed_mpw, check=True)
    finally:
        active_manifest.unlink(missing_ok=True)
    validate_extension_bindings(extensions, output)


def validate_extension_bindings(extensions_path: Path, output: Path) -> None:
    """Require SoC slot bindings to match the generated MPW v2 manifest."""
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
            if target.get("design_id") != design.get("id"):
                raise ValueError(
                    f"{extensions_path}: {kind} slot {slot} design ID does not match MPW v2"
                )
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
    parser.add_argument("--extensions", required=True, type=Path)
    parser.add_argument("--lock-file", required=True, type=Path)
    arguments = parser.parse_args()
    arguments.lock_file.parent.mkdir(parents=True, exist_ok=True)
    with arguments.lock_file.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        generate(
            arguments.root.resolve(),
            arguments.output.resolve(),
            arguments.extensions.resolve(),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
