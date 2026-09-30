"""Shared locked RV64 build helpers for HP payloads."""

from __future__ import annotations

import argparse
import struct
import subprocess
from pathlib import Path

try:
    from scripts.dependency_lock import load_lock
except ModuleNotFoundError:
    from dependency_lock import load_lock


def cross_prefix(root: Path) -> str:
    spec = load_lock(root / "dependencies/dependencies.lock.json")["toolchains"]["ubuntu-22.04"][
        "riscv_gnu_hp"
    ]
    return str(root / ".cache/retrosoc/development/toolchains" /
               f"riscv_gnu_hp-{spec['version']}" / spec["path"] / "riscv64-unknown-elf-")


def require_rv64_elf(path: Path) -> None:
    header = path.read_bytes()[:64]
    if (len(header) < 64 or header[:6] != b"\x7fELF\x02\x01" or
            struct.unpack_from("<H", header, 18)[0] != 243):
        raise ValueError(f"expected a little-endian RV64 ELF: {path}")


def require_revision(root: Path, name: str) -> Path:
    spec = load_lock(root / "dependencies/dependencies.lock.json")["sources"][name]
    source = root / spec["destination"]
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != spec["revision"]:
        raise ValueError(f"{name} revision mismatch: {actual} != {spec['revision']}")
    if subprocess.run(["git", "-C", str(source), "diff", "--quiet", "HEAD", "--"],
                      check=False).returncode:
        raise ValueError(f"{name} has modified tracked source files: {source}")
    return source


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    print(cross_prefix(parser.parse_args().root.resolve()))
