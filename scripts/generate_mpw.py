#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import TextIO


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    if not root.exists():
        return ""
    for path in sorted(
        item for item in root.rglob("*") if item.is_file() and item.name != ".stamp"
    ):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def run(root: Path, log: TextIO, script: Path, *args: str) -> None:
    command = ["python3", str(script), *args]
    log.write("+ " + " ".join(command) + "\n")
    log.flush()
    subprocess.run(
        command,
        cwd=root,
        check=True,
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
    )


def rewrite_filelists(root: Path, old_prefix: Path, new_prefix: Path) -> None:
    for filelist in root.rglob("*.fl"):
        content = filelist.read_text(encoding="utf-8")
        content = content.replace(str(old_prefix.resolve()), str(new_prefix.resolve()))
        filelist.write_text(content, encoding="utf-8")


def generate(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    mpw = root / "rtl/mini/mpw"
    shared = mpw / ".build"
    output = args.output.resolve()
    needs_core = args.core == "MDD"
    needs_ip = args.ip == "MDD"
    log_path = output.parent / f"{output.name}-generation.log"

    output.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log, tempfile.TemporaryDirectory(
        prefix=f".{output.name}.", dir=output.parent
    ) as temp:
        log.write(f"simulator={args.simu} core={args.core} ip={args.ip}\n")
        candidate = Path(temp) / "output"
        candidate.mkdir()
        (shared / "user_design_info.h").unlink(missing_ok=True)

        if needs_ip:
            run(root, log, mpw / "ip.py")
            run(root, log, mpw / "info.py", "IP")
            shutil.copytree(shared / "ip", candidate / "ip")
        if needs_core:
            run(root, log, mpw / "core.py", args.simu)
            run(root, log, mpw / "info.py", "CORE")
            shutil.copytree(shared / "core", candidate / "core")
        info = shared / "user_design_info.h"
        if info.is_file():
            shutil.copy2(info, candidate / info.name)

        rewrite_filelists(candidate, shared, output)
        if tree_digest(candidate) == tree_digest(output):
            print(f"[mpw] generated output unchanged: {output} (log: {log_path})")
            return
        if output.exists():
            shutil.rmtree(output)
        os.replace(candidate, output)
        print(f"[mpw] generated isolated output: {output} (log: {log_path})")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate isolated MPW build sources")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--simu", choices=("VCS", "VERILATOR", "IVERILOG"), required=True)
    parser.add_argument("--core", choices=("PICORV32", "HAZARD3", "MDD"), required=True)
    parser.add_argument("--ip", choices=("NONE", "MDD"), required=True)
    parser.add_argument("--lock-file", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.lock_file.parent.mkdir(parents=True, exist_ok=True)
    with args.lock_file.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        generate(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
