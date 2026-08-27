#!/usr/bin/env python3
"""Generate the locked VexiiRiscv HP core below the selected build variant."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any


GENERATOR_CLASS = "vexiiriscv.GenerateRetroSocHp"
GENERATED_MODULE = "vexii_riscv_hp_generated"


def run(command: list[str], cwd: Path) -> str:
    result = subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def git_revision(source: Path) -> str:
    return run(["git", "rev-parse", "HEAD"], source)


def git_status(source: Path) -> list[str]:
    output = run(["git", "status", "--short"], source)
    return output.splitlines() if output else []


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def locked_revision(lock_path: Path) -> str:
    document: dict[str, Any] = json.loads(lock_path.read_text(encoding="utf-8"))
    source = document.get("sources", {}).get("vexiiriscv")
    if not isinstance(source, dict) or not isinstance(source.get("revision"), str):
        raise ValueError("dependency lock has no vexiiriscv source revision")
    return source["revision"]


def generate(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    source = args.source.resolve()
    output = args.output.resolve()
    expected = locked_revision(args.lock.resolve())
    actual = git_revision(source)
    if actual != expected:
        raise ValueError(f"VexiiRiscv revision mismatch: expected {expected}, found {actual}")

    scala_dir = root / "scripts" / "vexiiriscv"
    output.mkdir(parents=True, exist_ok=True)
    command = [
        str(args.sbt),
        f'set Compile / unmanagedSourceDirectories += file("{scala_dir}")',
        f"runMain {GENERATOR_CLASS} {output}",
    ]
    environment = os.environ.copy()
    java_home = environment.get("HOME")
    if java_home:
        inherited = environment.get("JAVA_TOOL_OPTIONS", "").strip()
        environment["JAVA_TOOL_OPTIONS"] = (
            f"{inherited} -Duser.home={java_home}".strip()
        )
    subprocess.run(command, cwd=source, check=True, env=environment)

    generated = output / "vexii_riscv_hp_generated.v"
    if not generated.is_file():
        raise FileNotFoundError(f"VexiiRiscv generator did not create {generated}")

    submodules = run(["git", "submodule", "status", "--recursive"], source).splitlines()
    manifest = {
        "schema_version": 1,
        "module": GENERATED_MODULE,
        "configuration": "rv32imafdc_max",
        "vexiiriscv_revision": actual,
        "source_status": git_status(source),
        "submodules": submodules,
        "generator": str((scala_dir / "GenerateRetroSocHp.scala").relative_to(root)),
        "files": {generated.name: sha256(generated)},
    }
    args.manifest.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.manifest.resolve().write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output / "vexiiriscv.fl").write_text(str(generated) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--sbt", type=Path, required=True)
    generate(parser.parse_args())


if __name__ == "__main__":
    main()
