#!/usr/bin/env python3
"""Check ownership-aware style rules for retroSoC RTL."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


SUFFIXES = {".sv", ".svh", ".v", ".vh"}
INSTANCE_RE = re.compile(
    r"^\s*(?P<module>[A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*\([^;]*\)\s*)?"
    r"u_[A-Za-z_][A-Za-z0-9_$]*\s*\($"
)
LEGACY_ALWAYS_RE = re.compile(r"\balways\s*@")
DECL_RE = re.compile(r"\b(?:wire|tri|wand|wor)\b")
LONG_NAME_DECL_RE = re.compile(
    r"\b(?:logic|wire|reg)\b[^;\n]*\b(?:command|request|response|address|enable|error|status|counter|configuration|select|length)\b"
)


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [Path(item.decode("utf-8")) for item in result.stdout.split(b"\0") if item]


def changed_files(root: Path) -> set[Path]:
    """Return tracked RTL files changed in the worktree or current commit."""
    names = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", "--diff-filter=ACMR"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.splitlines()
    names += subprocess.run(
        ["git", "-C", str(root), "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.splitlines()
    return {Path(name) for name in names}


def selected_files(root: Path, manifest: dict[str, object]) -> dict[str, list[Path]]:
    profiles = manifest["profiles"]
    assert isinstance(profiles, dict)
    files: dict[str, list[Path]] = {}
    for profile, raw in profiles.items():
        assert isinstance(raw, dict)
        roots = raw["roots"]
        suffixes = raw["suffixes"]
        assert isinstance(roots, list) and isinstance(suffixes, list)
        root_paths = [Path(item) for item in roots]
        files[profile] = sorted(
            path
            for path in tracked_files(root)
            if path.suffix in set(suffixes)
            and any(path == candidate or candidate in path.parents for candidate in root_paths)
            and (root / path).is_file()
        )
    return files


def instance_issues(path: Path, source: str) -> list[str]:
    lines = source.splitlines()
    issues: list[str] = []
    for index, line in enumerate(lines):
        match = INSTANCE_RE.match(line)
        if match is None:
            continue
        cursor = index + 1
        while cursor < len(lines) and ");" not in lines[cursor]:
            text = lines[cursor].strip()
            if text and not text.startswith(".") and not text.startswith("//"):
                issues.append(f"{path}:{cursor + 1}: positional port connection")
                break
            cursor += 1
    return issues


def check_file(path: Path, source: str, profile: str) -> list[str]:
    issues: list[str] = []
    if profile == "owned":
        issues.extend(instance_issues(path, source))
        for number, line in enumerate(source.splitlines(), start=1):
            if LEGACY_ALWAYS_RE.search(line):
                issues.append(f"{path}:{number}: use always_ff/always_comb in owned RTL")
            if re.search(r"\bwire\b", line) and not re.search(r"\binout\s+wire\b", line):
                issues.append(f"{path}:{number}: explicit wire in owned RTL; justify net semantics")
            if LONG_NAME_DECL_RE.search(line) and not line.lstrip().startswith("//"):
                issues.append(f"{path}:{number}: prefer the local short-name abbreviation")
    return issues


def verible_issues(tool: str, paths: list[Path], root: Path) -> list[str]:
    if not paths:
        return []
    result = subprocess.run(
        [
            tool,
            "--ruleset=none",
            "--rules=module-port,module-parameter,always-comb,always-ff-non-blocking,case-missing-default",
            *(str(root / path) for path in paths),
        ],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode == 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--profile", default="owned", choices=("owned", "verification", "technology"))
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--verible-verilog-lint", default="verible-verilog-lint")
    parser.add_argument(
        "--changed-only",
        action="store_true",
        help="check only files changed in the worktree or current commit",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = args.manifest or root / "rtl/rtl_style_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    profile_files = selected_files(root, manifest)[args.profile]
    if args.changed_only:
        changed = changed_files(root)
        profile_files = [path for path in profile_files if path in changed]
    issues = [
        issue
        for path in profile_files
        for issue in check_file(path, (root / path).read_text(encoding="utf-8"), args.profile)
    ]
    if args.profile == "owned":
        issues.extend(verible_issues(args.verible_verilog_lint, profile_files, root))
    baseline: set[str] = set()
    if args.baseline and args.baseline.is_file():
        baseline = set(json.loads(args.baseline.read_text(encoding="utf-8")))
    new_issues = [issue for issue in issues if issue not in baseline]
    if new_issues:
        print("RTL style violations:", file=sys.stderr)
        print("\n".join(new_issues), file=sys.stderr)
        return 1
    print(f"rtl-style-check: {args.profile} passed ({len(issues)} baseline findings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
