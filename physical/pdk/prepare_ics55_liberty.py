#!/usr/bin/env python3
"""Prepare the locked ICS55 H7CR Liberty timing views."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, sha256  # noqa: E402


TT_OUTPUT = "ics55_h7cr_tt.lib"
SS_OUTPUT = "ics55_h7cr_ss.lib"
MARKER = ".complete"


def find_corner(root: Path, tokens: Iterable[str]) -> Path:
    normalized_tokens = tuple(token.lower() for token in tokens)
    matches = [
        path
        for path in sorted(root.rglob("*.lib"))
        if all(token in path.name.lower() for token in normalized_tokens)
    ]
    if len(matches) != 1:
        description = ", ".join(normalized_tokens)
        raise FileNotFoundError(
            f"expected one ICS55 Liberty corner matching {description}, found {len(matches)}"
        )
    return matches[0]


def prepare(archive: Path, output_dir: Path, revision: str) -> None:
    archive = archive.resolve()
    if not archive.is_file():
        raise FileNotFoundError(f"ICS55 Liberty archive not found: {archive}")

    output_dir = output_dir.resolve()
    marker_content = f"{revision}\n{sha256(archive)}\n"
    marker = output_dir / MARKER
    if (
        marker.is_file()
        and marker.read_text(encoding="utf-8") == marker_content
        and (output_dir / TT_OUTPUT).is_file()
        and (output_dir / SS_OUTPUT).is_file()
    ):
        print(f"ICS55 Liberty is ready: {output_dir}")
        return

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output_dir.name}.", dir=output_dir.parent) as temp:
        candidate = Path(temp) / "content"
        extracted = Path(temp) / "extracted"
        candidate.mkdir()
        extracted.mkdir()
        safe_extract(archive, extracted)
        shutil.copy2(find_corner(extracted, ("tt", "1p2", "25")), candidate / TT_OUTPUT)
        shutil.copy2(find_corner(extracted, ("ss", "1p08", "125")), candidate / SS_OUTPUT)
        atomic_write(candidate / MARKER, marker_content)
        if output_dir.exists():
            shutil.rmtree(output_dir)
        os.replace(candidate, output_dir)
    print(f"prepared ICS55 Liberty: {output_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract locked ICS55 H7CR Liberty timing views into the cache"
    )
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    prepare(args.archive, args.output_dir, args.revision)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
