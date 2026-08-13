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
FORBIDDEN_TOKEN_RE = {
    "wildcard instance connection": re.compile(r"\.\*\s*\)"),
    "defparam": re.compile(r"\bdefparam\b"),
    "casex": re.compile(r"\bcasex\b"),
    "full_case pragma": re.compile(r"\bfull_case\b"),
    "parallel_case pragma": re.compile(r"\bparallel_case\b"),
    "synthesizable delay": re.compile(r"#\s*\d"),
    "task declaration": re.compile(r"\btask(?:\s+automatic)?\s+[A-Za-z_]"),
    "hierarchical reference": re.compile(r"\b[A-Za-z_]\w*(?:\.[A-Za-z_]\w*){2,}\b"),
}
UNNAMED_GENERATE_RE = re.compile(
    r"\bgenerate\b(?:(?!\bendgenerate\b).)*?"
    r"\b(?:if|for)\b(?:(?!\bbegin\b).)*?\bbegin\s*(?!:)",
    re.DOTALL,
)
LONG_LOCAL_RE = re.compile(
    r"\b[sr]_[A-Za-z0-9_$]*(?:command|request|response|address|enable|error|status|"
    r"counter|configuration|select|length)(?:_|$)"
)
MODULE_RE = re.compile(r"^\s*module\s+(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\b")
PORT_RE = re.compile(
    r"^\s*(?:input|output|inout)\b.*?\b(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\s*(?:[,)]|$)"
)
INTERFACE_INSTANCE_RE = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_$]*_if|axi4_if|axi4_stream_if)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\s*\("
)
MACRO_RE = re.compile(r"^\s*`define\s+(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\b")
ENUM_TYPE_RE = re.compile(r"typedef\s+enum\b[\s\S]*?}\s*(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\s*;")
PARAM_RE = re.compile(
    r"\b(?:localparam|parameter)\b(?:\s+(?:bit|logic|int|integer|unsigned|signed)"
    r"|\s*\[[^\]]+\])*\s+(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\s*(?:=|,|$)"
)
UPPER_CAMEL_RE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
LOWER_SNAKE_RE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [Path(item.decode("utf-8")) for item in result.stdout.split(b"\0") if item]


def changed_files(root: Path) -> set[Path]:
    """Return RTL files changed in the worktree, including untracked files."""
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
    names += subprocess.run(
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"],
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


def add_changed_profile_files(
    root: Path, profile_files: list[Path], profile: dict[str, object], changed: set[Path]
) -> list[Path]:
    """Include new, untracked owned sources in changed-only checks."""
    roots = profile.get("roots", [])
    suffixes = set(profile.get("suffixes", []))
    root_paths = [Path(item) for item in roots]
    candidates = {
        path
        for path in changed
        if path.suffix in suffixes
        and any(path == candidate or candidate in path.parents for candidate in root_paths)
        and (root / path).is_file()
    }
    return sorted(set(profile_files) | candidates)


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
            if (
                text
                and not text.startswith(".")
                and not text.startswith("//")
                and not text.startswith("`")
            ):
                issues.append(f"{path}:{cursor + 1}: positional port connection")
                break
            cursor += 1
    return issues


def check_file(path: Path, source: str, profile: str) -> list[str]:
    issues: list[str] = []
    if profile == "owned":
        issues.extend(instance_issues(path, source))
        format_disabled = False
        for number, line in enumerate(source.splitlines(), start=1):
            code = line.split("//", 1)[0]
            if "verilog_format: off" in line:
                format_disabled = True
            format_exception = format_disabled
            if LEGACY_ALWAYS_RE.search(code):
                issues.append(f"{path}:{number}: use always_ff/always_comb in owned RTL")
            if re.search(r"\bwire\b", code) and not re.search(r"\binout\s+wire\b", code):
                issues.append(f"{path}:{number}: explicit wire in owned RTL; justify net semantics")
            if LONG_LOCAL_RE.search(code):
                issues.append(f"{path}:{number}: prefer the local short-name abbreviation")
            if not format_exception:
                if any(character == "\t" for character in line):
                    issues.append(f"{path}:{number}: tabs are not permitted in owned RTL")
                if line.rstrip() != line:
                    issues.append(f"{path}:{number}: trailing whitespace")
                if any(ord(character) > 127 for character in line):
                    issues.append(f"{path}:{number}: non-ASCII character")
                if len(line) > 100:
                    issues.append(f"{path}:{number}: line exceeds 100 characters")
            for description, pattern in FORBIDDEN_TOKEN_RE.items():
                if pattern.search(code):
                    issues.append(f"{path}:{number}: {description} is not permitted")
            if "verilog_format: on" in line:
                format_disabled = False
        if source and not source.endswith("\n"):
            issues.append(f"{path}: missing final newline")
        if UNNAMED_GENERATE_RE.search(source):
            issues.append(f"{path}: generated if/for block must have a label")
    return issues


def naming_issues(path: Path, source: str, manifest: dict[str, object]) -> list[str]:
    """Check the staged naming contract without touching protocol ABI fields."""
    naming = manifest.get("naming", {})
    if not isinstance(naming, dict):
        return []
    issues: list[str] = []
    lines = source.splitlines()
    for number, line in enumerate(lines, start=1):
        code = line.split("//", 1)[0]
        module_match = MODULE_RE.match(code)
        if module_match and not LOWER_SNAKE_RE.fullmatch(module_match.group("name")):
            issues.append(f"{path}:{number}: module name must use lower_snake_case")
        port_match = PORT_RE.match(code)
        if port_match:
            name = port_match.group("name")
            if not name.endswith(("_i", "_o", "_io")):
                issues.append(f"{path}:{number}: port '{name}' needs _i, _o, or _io suffix")
        interface_match = INTERFACE_INSTANCE_RE.match(code)
        if interface_match and not interface_match.group("name").startswith("u_"):
            issues.append(f"{path}:{number}: interface instance must start with u_")
        macro_match = MACRO_RE.match(code)
        if macro_match:
            name = macro_match.group("name")
            exceptions = naming.get("macro_namespace_exceptions", [])
            if not isinstance(exceptions, list):
                exceptions = []
            if not name.startswith("RETROSOC_") and not any(
                name.startswith(str(prefix)) for prefix in exceptions
            ):
                issues.append(f"{path}:{number}: macro '{name}' needs a reviewed namespace")
        if re.search(r"\brst_ni\b", code):
            issues.append(f"{path}:{number}: use project reset spelling rst_n_i")
    for match in ENUM_TYPE_RE.finditer(source):
        if not match.group("name").endswith("_e"):
            line = source.count("\n", 0, match.start()) + 1
            issues.append(f"{path}:{line}: enum typedef must end in _e")
    for number, line in enumerate(lines, start=1):
        code = line.split("//", 1)[0]
        if re.search(r"\b(?:parameter|localparam)\b", code):
            for match in PARAM_RE.finditer(code):
                if not UPPER_CAMEL_RE.fullmatch(match.group("name")):
                    issues.append(
                        f"{path}:{number}: parameter '{match.group('name')}' must use UpperCamelCase"
                    )
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
    parser.add_argument(
        "--enforce-naming",
        action="store_true",
        help="enforce the staged naming rules for the selected files",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = args.manifest or root / "rtl/rtl_style_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    profile_files = selected_files(root, manifest)[args.profile]
    if args.changed_only:
        changed = changed_files(root)
        raw_profile = manifest["profiles"][args.profile]
        assert isinstance(raw_profile, dict)
        profile_files = add_changed_profile_files(root, profile_files, raw_profile, changed)
        profile_files = [path for path in profile_files if path in changed]
    issues = [
        issue
        for path in profile_files
        for issue in check_file(path, (root / path).read_text(encoding="utf-8"), args.profile)
    ]
    if args.profile == "owned" and (args.changed_only or args.enforce_naming):
        issues.extend(
            naming_issues(path, (root / path).read_text(encoding="utf-8"), manifest)
            for path in profile_files
        )
        issues = [issue for group in issues for issue in (group if isinstance(group, list) else [group])]
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
