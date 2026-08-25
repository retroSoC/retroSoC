#!/usr/bin/env python3
"""Install the checksum-locked ECOS Chip Compiler CLI into the local cache."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import archive  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file  # noqa: E402


ARCHIVE_NAME = "ecc_cli_linux_x86_64"
EXPECTED_VERSION = "0.1.0a10"


def ecc_version(binary: Path) -> str:
    result = subprocess.run(
        [str(binary), "--version"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    for line in reversed(lines):
        if line.startswith("ecc "):
            return line
    return result.stdout.strip()


def install(root: Path, lock_path: Path, output_dir: Path, update: bool) -> Path:
    spec = archive(ARCHIVE_NAME, lock_path)
    archive_path = root / spec["destination"]
    download_file(spec["url"], archive_path, spec["sha256"], update=update, timeout=120)

    output_dir = output_dir.resolve()
    marker = output_dir / ".complete"
    binary = output_dir / "ecc"
    marker_text = f"{EXPECTED_VERSION}\n{spec['sha256']}\n"
    if binary.is_file() and marker.is_file() and marker.read_text(encoding="utf-8") == marker_text:
        return binary

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output_dir.name}.", dir=output_dir.parent) as temp:
        extracted = Path(temp) / "extracted"
        extracted.mkdir()
        safe_extract(archive_path, extracted)
        candidates = sorted(
            path for path in extracted.rglob("ecc") if path.is_file() and os.access(path, os.X_OK)
        )
        if len(candidates) != 1:
            raise RuntimeError(
                "expected exactly one executable named ecc in the ECC release archive, "
                f"found {len(candidates)}"
            )
        bundle_root = candidates[0].parent
        candidate = Path(temp) / "content"
        shutil.copytree(bundle_root, candidate)
        installed_binary = candidate / "ecc"
        installed_binary.chmod(installed_binary.stat().st_mode | stat.S_IXUSR)
        version = ecc_version(installed_binary)
        if version != f"ecc {EXPECTED_VERSION}":
            raise RuntimeError(
                f"expected ECC version ecc {EXPECTED_VERSION}, found {version or '<empty>'}"
            )
        atomic_write(candidate / ".complete", marker_text)
        if output_dir.exists():
            shutil.rmtree(output_dir)
        os.replace(candidate, output_dir)
    return binary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    binary = install(args.root.resolve(), args.lock.resolve(), args.output_dir, args.update)
    print(f"ECC is ready: {binary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
