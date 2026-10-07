#!/usr/bin/env python3
"""Materialize a locked OpenECOS ICS55 SRAM release archive."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, sha256  # noqa: E402


def materialize(archive: Path, output_dir: Path, expected_sha256: str) -> None:
    archive = archive.resolve()
    if not archive.is_file():
        raise FileNotFoundError(f"ICS55 SRAM archive not found: {archive}")
    actual = sha256(archive)
    if actual != expected_sha256:
        raise ValueError(f"ICS55 SRAM checksum mismatch: {actual} != {expected_sha256}")

    output_dir = output_dir.resolve()
    marker = output_dir / ".complete"
    if marker.is_file() and marker.read_text(encoding="utf-8").strip() == expected_sha256:
        print(f"ICS55 SRAM is ready: {output_dir}")
        return

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output_dir.name}.", dir=output_dir.parent) as temp:
        extracted = Path(temp) / "content"
        extracted.mkdir()
        safe_extract(archive, extracted)
        entries = list(extracted.iterdir())
        if len(entries) == 1 and entries[0].is_dir():
            nested = entries[0]
            for child in nested.iterdir():
                shutil.move(str(child), extracted / child.name)
            nested.rmdir()
        atomic_write(extracted / ".complete", expected_sha256 + "\n")
        if output_dir.exists():
            shutil.rmtree(output_dir)
        os.replace(extracted, output_dir)
    print(f"prepared ICS55 SRAM: {output_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    args = parser.parse_args()
    materialize(args.archive, args.output_dir, args.archive_sha256)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
