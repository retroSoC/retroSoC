#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


DEFAULT_CORNER = "tt_025C_5v00"
DEFAULT_LIBRARY = "gf180mcu_fd_sc_mcu7t5v0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Assemble a GF180 Liberty model from locked PDK fragments"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--library", default=DEFAULT_LIBRARY)
    parser.add_argument("--cell", action="append")
    parser.add_argument("--output-name")
    parser.add_argument("--corner", default=DEFAULT_CORNER)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    library_dir = source / "libraries" / args.library / "latest"
    header = library_dir / "liberty" / f"{args.library}__{args.corner}.lib"
    cells_dir = library_dir / "cells"
    if args.cell:
        cell_libraries = [
            cells_dir / cell / f"{args.library}__{cell}__{args.corner}.lib"
            for cell in sorted(set(args.cell))
        ]
    else:
        cell_libraries = sorted(cells_dir.glob(f"*/*__{args.corner}.lib"))
    if not header.is_file() or not cell_libraries:
        raise FileNotFoundError(f"missing GF180 Liberty inputs below {library_dir}")

    output_dir = args.output_dir.resolve()
    output_name = args.output_name or f"{args.library}__{args.corner}.lib"
    output = output_dir / output_name
    revision = output.with_suffix(output.suffix + ".revision")
    revision_contents = (
        f"{args.revision}\n{args.library}\n{','.join(sorted(set(args.cell or ())))}\n"
    )
    if (
        output.is_file()
        and revision.is_file()
        and revision.read_text(encoding="utf-8") == revision_contents
    ):
        print(f"GF180 Liberty is ready: {output}")
        return 0

    prefix, separator, _ = header.read_text(encoding="utf-8").rpartition("\n}")
    if not separator:
        raise RuntimeError(f"GF180 Liberty header is malformed: {header}")
    cells = "\n\n".join(path.read_text(encoding="utf-8") for path in cell_libraries)
    atomic_write(output, f"{prefix}\n\n{cells}\n}}\n")
    atomic_write(revision, revision_contents)
    print(f"generated GF180 Liberty: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
