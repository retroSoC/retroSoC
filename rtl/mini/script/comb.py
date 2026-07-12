#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from filelist import parse_filelists, write_filelist


DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / ".generated_fl" / "yosys.fl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Combine synthesis filelists")
    parser.add_argument("-f", "--filelist", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected = [path for path in args.filelist if not path.name.startswith("pdk_")]
    if not selected:
        raise SystemExit("at least one non-PDK -f/--filelist is required")
    combined = parse_filelists(selected)
    write_filelist(args.output.resolve(), combined)
    print(f"generated synthesis filelist: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
