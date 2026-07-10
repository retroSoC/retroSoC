#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from filelist import atomic_write, parse_filelists


HEADER_SUFFIXES = {".h", ".vh", ".svh"}


def make_escape(path: Path) -> str:
    return (
        str(path.resolve())
        .replace("\\", "\\\\")
        .replace("$", "$$")
        .replace(" ", "\\ ")
        .replace("#", "\\#")
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Make dependencies from RTL filelists")
    parser.add_argument("-f", "--filelist", type=Path, action="append", default=[])
    parser.add_argument("--extra", type=Path, action="append", default=[])
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.filelist:
        parser.error("at least one -f/--filelist is required")

    parsed = parse_filelists(args.filelist)
    dependencies = {
        *(path.resolve() for path in args.filelist),
        *(path.resolve() for path in parsed.files),
        *(path.resolve() for path in parsed.library_files),
        *(path.resolve() for path in args.extra),
    }
    for directory in parsed.incdirs:
        if directory.is_dir():
            dependencies.update(
                path.resolve()
                for path in directory.rglob("*")
                if path.is_file() and path.suffix.lower() in HEADER_SUFFIXES
            )
    content = f"{make_escape(args.target)}:"
    if dependencies:
        content += " \\\n  " + " \\\n  ".join(make_escape(path) for path in sorted(dependencies))
    content += "\n"
    atomic_write(args.output, content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
