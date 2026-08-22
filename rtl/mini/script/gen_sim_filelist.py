#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from pathlib import Path

from filelist import FileList, atomic_write, parse_filelists


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a simulator filelist")
    parser.add_argument("--format", choices=("cvc", "xezim"), required=True)
    parser.add_argument("--filelist", action="append", type=Path, required=True)
    parser.add_argument("--source", action="append", type=Path, default=[])
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--exclude-pattern", action="append", default=[])
    parser.add_argument("--drop-option", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def quote(value: str) -> str:
    if not any(character.isspace() for character in value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def define_name(value: str) -> str:
    return value[len("+define+") :] if value.startswith("+define+") else value


def as_tokens(filelist: FileList, simulator: str) -> list[str]:
    options = list(filelist.options)
    if simulator == "xezim":
        tokens: list[str] = [f"-D{define_name(value)}" for value in filelist.defines]
        tokens.extend(f"-I{quote(str(path))}" for path in filelist.incdirs)
    else:
        tokens = list(filelist.defines)
        tokens.extend(quote(f"+incdir+{path}") for path in filelist.incdirs)
    tokens.extend(
        token
        for path in filelist.library_files
        for token in ("-v", quote(str(path)))
    )
    tokens.extend(options)
    tokens.extend(quote(str(path)) for path in filelist.files)
    return tokens


def main() -> int:
    args = parse_args()
    filelist = parse_filelists(path.resolve() for path in args.filelist)
    filelist.options = [
        option for option in filelist.options if option not in set(args.drop_option)
    ]
    filelist.defines.extend(args.define)
    patterns = [re.compile(pattern) for pattern in args.exclude_pattern]
    if patterns:
        filelist.files = [
            path
            for path in filelist.files
            if not any(pattern.search(str(path)) for pattern in patterns)
        ]
        filelist.library_files = [
            path
            for path in filelist.library_files
            if not any(pattern.search(str(path)) for pattern in patterns)
        ]
    filelist.files.extend(path.resolve() for path in args.source)
    filelist.deduplicate()
    content = "\n".join(as_tokens(filelist, args.format)) + "\n"
    atomic_write(args.output.resolve(), content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
