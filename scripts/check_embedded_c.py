#!/usr/bin/env python3
"""Check the self-owned embedded C surface without scanning vendored code."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


SOURCE_SUFFIXES = {".c", ".h"}
TINY_TOKEN = re.compile(r"\btiny[a-zA-Z0-9_]*\b", re.IGNORECASE)
LEGACY_INCLUDE = re.compile(r"#\s*include\s*[<\"](?:rs_|tiny)", re.IGNORECASE)


def load_policy(root: Path) -> dict[str, object]:
    path = root / "quality" / "embedded_c_policy.json"
    with path.open(encoding="utf-8") as policy_file:
        return json.load(policy_file)


def is_excluded(relative_path: str, prefixes: list[str]) -> bool:
    return any(relative_path.startswith(prefix) for prefix in prefixes)


def embedded_c_files(root: Path, policy: dict[str, object]) -> list[Path]:
    prefixes = [str(prefix) for prefix in policy["excluded_prefixes"]]
    files: list[Path] = []
    for source_root in (root / "crt", root / "app"):
        if not source_root.exists():
            continue
        for path in source_root.rglob("*"):
            if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:
                continue
            relative_path = path.relative_to(root).as_posix()
            if not is_excluded(relative_path, prefixes):
                files.append(path)
    return sorted(files)


def format_issues(path: Path) -> list[str]:
    data = path.read_bytes()
    issues: list[str] = []
    if b"\r" in data:
        issues.append("contains CR line endings")
    if data and not data.endswith(b"\n"):
        issues.append("does not end with a newline")

    for line_number, raw_line in enumerate(data.splitlines(), start=1):
        if raw_line.rstrip(b" \t") != raw_line:
            issues.append(f"line {line_number}: trailing whitespace")
        if b"\t" in raw_line:
            issues.append(f"line {line_number}: tab indentation is not allowed")
    return issues


def policy_issues(root: Path, path: Path, policy: dict[str, object]) -> list[str]:
    relative_path = path.relative_to(root).as_posix()
    compatibility_files = {str(item) for item in policy["compatibility_files"]}
    forbidden_calls = "|".join(str(item) for item in policy["forbidden_calls"])
    forbidden_call = re.compile(rf"\b(?:{forbidden_calls})\s*\(")
    text = path.read_text(encoding="utf-8")
    issues: list[str] = []

    if TINY_TOKEN.search(text):
        issues.append("contains a retired tiny-prefixed identifier or label")
    if LEGACY_INCLUDE.search(text):
        issues.append("contains a retired legacy include path")
    if relative_path not in compatibility_files and forbidden_call.search(text):
        issues.append("uses a banned unsafe C library call")
    return issues


def print_issues(root: Path, files: list[Path], callback: object) -> int:
    count = 0
    for path in files:
        for issue in callback(path):
            print(f"{path.relative_to(root)}: {issue}")
            count += 1
    return count


def run_clang_format(files: list[Path], formatter: str) -> int:
    executable = shutil.which(formatter)
    if executable is None:
        print(f"clang-format executable not found: {formatter}", file=sys.stderr)
        return 1
    subprocess.run([executable, "-i", *(str(path) for path in files)], check=True)
    return 0


def check_clang_format(files: list[Path], formatter: str) -> int:
    executable = shutil.which(formatter)
    if executable is None:
        print(f"clang-format executable not found: {formatter}", file=sys.stderr)
        return 1
    result = subprocess.run(
        [executable, "--dry-run", "--Werror", *(str(path) for path in files)],
        check=False,
    )
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--format-check", action="store_true")
    parser.add_argument("--clang-format-check", action="store_true")
    parser.add_argument("--policy-check", action="store_true")
    parser.add_argument("--apply-format", action="store_true")
    parser.add_argument("--clang-format", default="clang-format")
    args = parser.parse_args()

    if not (args.format_check or args.clang_format_check or args.policy_check or args.apply_format):
        parser.error("select a format, policy, or apply action")

    root = args.root.resolve()
    policy = load_policy(root)
    files = embedded_c_files(root, policy)
    failures = 0
    if args.format_check:
        failures += print_issues(root, files, format_issues)
    if args.policy_check:
        failures += print_issues(
            root,
            files,
            lambda path: policy_issues(root, path, policy),
        )
    if args.clang_format_check:
        failures += check_clang_format(files, args.clang_format)
    if args.apply_format:
        return run_clang_format(files, args.clang_format)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
