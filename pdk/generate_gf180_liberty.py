#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


CORNER = "tt_025C_5v00"
LIBRARY = "gf180mcu_fd_sc_mcu7t5v0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Assemble the GF180 standard-cell Liberty model from locked PDK fragments"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    library_dir = source / "libraries" / LIBRARY / "latest"
    header = library_dir / "liberty" / f"{LIBRARY}__{CORNER}.lib"
    cells_dir = library_dir / "cells"
    cell_libraries = sorted(cells_dir.glob(f"*/*__{CORNER}.lib"))
    if not header.is_file() or not cell_libraries:
        raise FileNotFoundError(f"missing GF180 Liberty inputs below {library_dir}")

    output_dir = args.output_dir.resolve()
    output = output_dir / f"{LIBRARY}__{CORNER}.lib"
    revision = output.with_suffix(output.suffix + ".revision")
    if (
        output.is_file()
        and revision.is_file()
        and revision.read_text(encoding="utf-8") == f"{args.revision}\n"
    ):
        print(f"GF180 Liberty is ready: {output}")
        return 0

    prefix, separator, _ = header.read_text(encoding="utf-8").rpartition("\n}")
    if not separator:
        raise RuntimeError(f"GF180 Liberty header is malformed: {header}")
    cells = "\n\n".join(path.read_text(encoding="utf-8") for path in cell_libraries)
    atomic_write(output, f"{prefix}\n\n{cells}\n}}\n")
    atomic_write(revision, f"{args.revision}\n")
    print(f"generated GF180 Liberty: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
