#!/usr/bin/env python3
"""Reject compiler warnings emitted from self-owned embedded C sources."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
WARNING_RE = re.compile(
    r"^(?P<path>.+?\.(?:c|h)):(?P<line>\d+)(?::\d+)?: warning: (?P<message>.+)$"
)


def excluded_prefixes(root: Path) -> list[str]:
    policy_path = root / "quality" / "embedded_c_policy.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    return [str(prefix) for prefix in policy["excluded_prefixes"]]


def self_owned_warnings(root: Path, output: str) -> list[str]:
    prefixes = excluded_prefixes(root)
    warnings: list[str] = []

    for raw_line in output.splitlines():
        line = ANSI_RE.sub("", raw_line)
        match = WARNING_RE.match(line)
        if match is None:
            continue
        path = Path(match.group("path"))
        absolute_path = path if path.is_absolute() else root / path
        try:
            relative_path = absolute_path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        if any(relative_path.startswith(prefix) for prefix in prefixes):
            continue
        warnings.append(
            f"{relative_path}:{match.group('line')}: warning: {match.group('message')}"
        )
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    warnings = self_owned_warnings(root, args.log.read_text(encoding="utf-8", errors="replace"))
    for warning in warnings:
        print(warning)
    return int(bool(warnings))


if __name__ == "__main__":
    raise SystemExit(main())
