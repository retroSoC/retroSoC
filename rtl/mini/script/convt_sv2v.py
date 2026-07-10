#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from filelist import parse_filelists


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert the behavioral RTL with sv2v")
    parser.add_argument("-f", "--filelist", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sv2v", default="sv2v", help="sv2v executable")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected = [path for path in args.filelist if not path.name.startswith("pdk_")]
    if not selected:
        raise SystemExit("at least one non-PDK -f/--filelist is required")

    filelist = parse_filelists(selected)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    command = [args.sv2v]
    command.extend(f"-D{item[len('+define+'):]}" for item in filelist.defines)
    command.extend(f"-I{path}" for path in filelist.incdirs)
    command.extend(str(path) for path in filelist.files)
    command.extend(("--write", str(args.output.resolve())))
    subprocess.run(command, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
