#!/usr/bin/env python3
"""Build the repository BSP against the unmodified, locked RT-Thread kernel."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

try:
    from scripts.hp_tools import cross_prefix, require_revision, require_rv64_elf
except ModuleNotFoundError:
    from hp_tools import cross_prefix, require_revision, require_rv64_elf


def build(root: Path, output: Path, jobs: int) -> None:
    source = require_revision(root, "rtthread_hp")
    bsp = output / "bsp"
    bsp.mkdir(parents=True, exist_ok=True)
    for path in (root / "app/ports/rtthread").iterdir():
        if path.is_file():
            shutil.copy2(path, bsp / path.name)
    environment = dict(os.environ)
    for key in ("CONFIG", "MAKEFLAGS", "MAKEOVERRIDES", "MFLAGS"):
        environment.pop(key, None)
    environment.update(RTT_ROOT=str(source), RTT_EXEC_PATH=str(Path(cross_prefix(root)).parent),
                       RETROSOC_ROOT=str(root))
    expected = re.search(r"^scons==([\d.]+)", (root / "requirements/rtthread.txt").read_text(), re.M)
    actual = subprocess.check_output([str(root / ".cache/retrosoc/rtthread-venv/bin/python"),
                                      "-c", "import SCons; print(SCons.__version__)"], text=True).strip()
    if expected is None or actual != expected[1]:
        raise ValueError(f"RT-Thread SCons version does not match requirements: {actual}")
    subprocess.run([str(root / ".cache/retrosoc/rtthread-venv/bin/scons"), f"-j{jobs}"],
                   cwd=bsp, env=environment, check=True)
    require_rv64_elf(bsp / "rtthread.elf")
    images = output / "images"
    images.mkdir(parents=True, exist_ok=True)
    for name in ("rtthread.elf", "rtthread.bin", "rtthread.map"):
        shutil.copy2(bsp / name, images / name)
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"],
                                       text=True).strip()
    manifest = {"schema_version": 1, "xlen": 64, "abi": "lp64d", "hart_id": 1,
                "rtthread_revision": revision,
                "scons_version": actual,
                "compiler": subprocess.check_output([cross_prefix(root) + "gcc", "--version"],
                                                     text=True).splitlines()[0],
                "sha256": hashlib.sha256((images / "rtthread.bin").read_bytes()).hexdigest()}
    manifest["inputs"] = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in sorted((root / "app/ports/rtthread").iterdir()) if path.is_file()}
    manifest["inputs"]["requirements/rtthread.txt"] = hashlib.sha256(
        (root / "requirements/rtthread.txt").read_bytes()).hexdigest()
    (images / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=1)
    args = parser.parse_args()
    build(args.root.resolve(), args.output.resolve(), args.jobs)


if __name__ == "__main__":
    main()
