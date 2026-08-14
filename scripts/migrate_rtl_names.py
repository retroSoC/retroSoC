#!/usr/bin/env python3
"""Shorten long local RTL identifiers without changing public interfaces."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ABBREVIATIONS = (
    ("command", "cmd"),
    ("request", "req"),
    ("response", "resp"),
    ("address", "addr"),
    ("enable", "en"),
    ("error", "err"),
    ("status", "stat"),
    ("counter", "cnt"),
    ("configuration", "cfg"),
    ("select", "sel"),
    ("length", "len"),
)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_$]*\b")
LOCAL_PREFIX_RE = re.compile(r"^[sr]_")
AUTOMATIC_LOCALS = {
    "read_request": "read_req",
    "write_request": "write_req",
}


def shorten_identifier(identifier: str) -> str:
    if identifier in AUTOMATIC_LOCALS:
        return AUTOMATIC_LOCALS[identifier]
    if not LOCAL_PREFIX_RE.match(identifier):
        return identifier
    result = identifier
    for long_name, short_name in ABBREVIATIONS:
        result = re.sub(rf"(?<=_){long_name}(?=_|$)", short_name, result)
    return result


def rewrite(path: Path, apply: bool) -> int:
    source = path.read_text(encoding="utf-8")
    changed = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal changed
        original = match.group(0)
        replacement = shorten_identifier(original)
        if replacement != original:
            changed += 1
        return replacement

    rewritten = IDENTIFIER_RE.sub(replace, source)
    if apply and rewritten != source:
        path.write_text(rewritten, encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    paths = sorted((root / "rtl/ip").rglob("*.sv")) + sorted((root / "rtl/mini/top").rglob("*.sv"))
    changed = sum(rewrite(path, args.apply) for path in paths if path.is_file())
    print(f"short names: rewritten={changed} files={len(paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
