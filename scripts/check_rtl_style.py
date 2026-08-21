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
PRIMARY_DECL_RE = re.compile(
    r"^\s*(?:module|interface|package)\s+(?:automatic\s+)?"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\b",
    re.MULTILINE,
)
FUNCTION_HEADER_RE = re.compile(
    r"\bfunction\s+(?P<header>.*?)(?P<terminator>;|\n)",
    re.DOTALL,
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
EXPLICIT_FUNCTION_TYPE_RE = re.compile(
    r"^automatic\s+(?:bit|logic|reg|byte|shortint|int|longint|integer|time|"
    r"[A-Za-z_][A-Za-z0-9_$]*_(?:e|t))(?:\s+(?:signed|unsigned))?"
    r"(?:\s*\[[^\]]+\])?\s+[A-Za-z_][A-Za-z0-9_$]*\s*\("
)
REQUIRED_AUDIT_RULES = {
    "RTL-FILE",
    "RTL-SV",
    "RTL-NAME",
    "RTL-STRUCT",
    "RTL-COMB",
    "RTL-SEQ",
    "RTL-WIDTH",
    "RTL-CDC",
    "RTL-VERIFY",
    "RTL-FMT",
}


def diagnostic(rule: str, path: Path, message: str, line: int | None = None) -> str:
    location = f"{path}:{line}" if line is not None else str(path)
    return f"[{rule}] {location}: {message}"


def strip_comments(source: str) -> str:
    """Remove comments while retaining line numbers for diagnostics."""
    source = re.sub(
        r"/\*.*?\*/",
        lambda match: "\n" * match.group(0).count("\n"),
        source,
        flags=re.DOTALL,
    )
    return re.sub(r"//[^\n]*", "", source)


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return sorted({Path(item.decode("utf-8")) for item in result.stdout.split(b"\0") if item})


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
                issues.append(
                    diagnostic(
                        "RTL-STRUCT-002",
                        path,
                        "positional port connection",
                        cursor + 1,
                    )
                )
                break
            cursor += 1
    return issues


def verification_only_lines(source: str) -> set[int]:
    """Return lines excluded from synthesis by an explicit SYNTHESIS guard."""
    excluded_lines: set[int] = set()
    stack: list[tuple[str, bool]] = []
    for number, line in enumerate(source.splitlines(), start=1):
        directive = line.strip()
        parent_excluded = stack[-1][1] if stack else False
        if directive.startswith("`ifndef SYNTHESIS"):
            stack.append(("ifndef-synthesis", True))
        elif directive.startswith("`ifdef SYNTHESIS"):
            stack.append(("ifdef-synthesis", parent_excluded))
        elif directive.startswith(("`ifdef ", "`ifndef ", "`if ")):
            stack.append(("other", parent_excluded))
        elif directive.startswith("`else") and stack:
            kind, excluded = stack[-1]
            if kind == "ifndef-synthesis":
                stack[-1] = (kind, False)
            elif kind == "ifdef-synthesis":
                stack[-1] = (kind, True)
            else:
                stack[-1] = (kind, excluded)
        elif directive.startswith("`endif") and stack:
            stack.pop()
        if stack and stack[-1][1]:
            excluded_lines.add(number)
    return excluded_lines


def declaration_issues(path: Path, source: str) -> list[str]:
    parsed_source = strip_comments(source)
    declarations = list(PRIMARY_DECL_RE.finditer(parsed_source))
    modules = [match for match in declarations if match.group(0).lstrip().startswith("module")]
    if modules:
        declarations = modules
    if not declarations:
        if "`include" in parsed_source and "managed" in source.lower():
            return []
        return [diagnostic("RTL-FILE-001", path, "missing primary design unit")]
    primary = declarations[0]
    if primary.group("name") != path.stem:
        line = parsed_source.count("\n", 0, primary.start()) + 1
        return [
            diagnostic(
                "RTL-FILE-002",
                path,
                f"primary design unit '{primary.group('name')}' must match the file name",
                line,
            )
        ]
    return []


def function_issues(path: Path, source: str) -> list[str]:
    issues: list[str] = []
    parsed_source = strip_comments(source)
    for match in FUNCTION_HEADER_RE.finditer(parsed_source):
        header = re.sub(r"\s+", " ", match.group("header").strip())
        line = parsed_source.count("\n", 0, match.start()) + 1
        if not header.startswith("automatic "):
            issues.append(
                diagnostic(
                    "RTL-SV-008",
                    path,
                    "synthesizable function must be automatic",
                    line,
                )
            )
        elif not EXPLICIT_FUNCTION_TYPE_RE.match(header):
            issues.append(
                diagnostic(
                    "RTL-SV-009",
                    path,
                    "function requires an explicit return type and typed arguments",
                    line,
                )
            )
    return issues


def check_file(path: Path, source: str, profile: str) -> list[str]:
    issues: list[str] = []
    if profile == "owned":
        issues.extend(instance_issues(path, source))
        if path.suffix == ".sv":
            issues.extend(declaration_issues(path, source))
        issues.extend(function_issues(path, source))
        verification_lines = verification_only_lines(source)
        format_disabled = False
        format_disabled_line: int | None = None
        for number, line in enumerate(source.splitlines(), start=1):
            code = line.split("//", 1)[0]
            if "verilog_format: off" in line:
                if format_disabled:
                    issues.append(
                        diagnostic(
                            "RTL-FMT-005",
                            path,
                            "nested verilog_format: off region",
                            number,
                        )
                    )
                if "--" not in line:
                    issues.append(
                        diagnostic(
                            "RTL-FMT-007",
                            path,
                            "verilog_format: off requires an inline alignment rationale",
                            number,
                        )
                    )
                format_disabled = True
                format_disabled_line = number
            format_exception = format_disabled
            if LEGACY_ALWAYS_RE.search(code):
                issues.append(
                    diagnostic(
                        "RTL-SEQ-001",
                        path,
                        "use always_ff/always_comb in owned RTL",
                        number,
                    )
                )
            if re.search(r"\bwire\b", code) and not re.search(r"\binout\s+wire\b", code):
                issues.append(
                    diagnostic(
                        "RTL-STRUCT-005",
                        path,
                        "explicit wire in owned RTL; justify net semantics",
                        number,
                    )
                )
            if LONG_LOCAL_RE.search(code):
                issues.append(
                    diagnostic(
                        "RTL-NAME-009",
                        path,
                        "prefer the local short-name abbreviation",
                        number,
                    )
                )
            if re.search(r"\binitial\s+begin\b", code) and number not in verification_lines:
                issues.append(
                    diagnostic(
                        "RTL-SV-007",
                        path,
                        "initial block must be isolated from synthesis",
                        number,
                    )
                )
            if not format_exception:
                if any(character == "\t" for character in line):
                    issues.append(
                        diagnostic("RTL-FMT-002", path, "tabs are not permitted", number)
                    )
                if line.rstrip() != line:
                    issues.append(diagnostic("RTL-FMT-003", path, "trailing whitespace", number))
                if any(ord(character) > 127 for character in line):
                    issues.append(diagnostic("RTL-FMT-001", path, "non-ASCII character", number))
                if len(line) > 100:
                    issues.append(
                        diagnostic("RTL-FMT-004", path, "line exceeds 100 characters", number)
                    )
            for description, pattern in FORBIDDEN_TOKEN_RE.items():
                if pattern.search(code):
                    issues.append(
                        diagnostic("RTL-SV-001", path, f"{description} is not permitted", number)
                    )
            if "verilog_format: on" in line:
                if not format_disabled:
                    issues.append(
                        diagnostic(
                            "RTL-FMT-005",
                            path,
                            "verilog_format: on has no matching off",
                            number,
                        )
                    )
                else:
                    format_disabled = False
                    format_disabled_line = None
        if format_disabled:
            issues.append(
                diagnostic(
                    "RTL-FMT-005",
                    path,
                    "verilog_format: off has no matching on",
                    format_disabled_line,
                )
            )
        if source and not source.endswith("\n"):
            issues.append(diagnostic("RTL-FMT-006", path, "missing final newline"))
        if UNNAMED_GENERATE_RE.search(source):
            issues.append(
                diagnostic("RTL-STRUCT-006", path, "generated if/for block must have a label")
            )
    return issues


def naming_issues(path: Path, source: str, manifest: dict[str, object]) -> list[str]:
    """Check the staged naming contract without touching protocol ABI fields."""
    naming = manifest.get("naming", {})
    if not isinstance(naming, dict):
        return []
    issues: list[str] = []
    lines = source.splitlines()
    in_interface = False
    in_function = False
    for number, line in enumerate(lines, start=1):
        code = line.split("//", 1)[0]
        module_match = MODULE_RE.match(code)
        if module_match and not LOWER_SNAKE_RE.fullmatch(module_match.group("name")):
            issues.append(
                diagnostic(
                    "RTL-NAME-001",
                    path,
                    "module name must use lower_snake_case",
                    number,
                )
            )
        if re.match(r"^\s*interface\b", code):
            in_interface = True
        if re.match(r"^\s*function\b", code):
            in_function = True
        port_match = PORT_RE.match(code)
        if port_match and not in_interface and not in_function:
            name = port_match.group("name")
            if not name.endswith(("_i", "_o", "_io")):
                issues.append(
                    diagnostic(
                        "RTL-NAME-002",
                        path,
                        f"port '{name}' needs _i, _o, or _io suffix",
                        number,
                    )
                )
        interface_match = INTERFACE_INSTANCE_RE.match(code)
        if interface_match and not interface_match.group("name").startswith("u_") and (
            interface_match.group("name") not in {"ribp", "ribl", "rib"}
        ):
            issues.append(
                diagnostic(
                    "RTL-NAME-004",
                    path,
                    "interface instance must start with u_",
                    number,
                )
            )
        macro_match = MACRO_RE.match(code)
        if macro_match:
            name = macro_match.group("name")
            exceptions = naming.get("macro_namespace_exceptions", [])
            if not isinstance(exceptions, list):
                exceptions = []
            if not name.startswith("RETROSOC_") and not any(
                name.startswith(str(prefix)) for prefix in exceptions
            ) and not name.endswith(("_SV", "_SVH")):
                issues.append(
                    diagnostic(
                        "RTL-NAME-008",
                        path,
                        f"macro '{name}' needs a reviewed namespace",
                        number,
                    )
                )
        if re.search(r"\brst_ni\b", code):
            issues.append(
                diagnostic(
                    "RTL-NAME-003",
                    path,
                    "use project reset spelling rst_n_i",
                    number,
                )
            )
        if re.match(r"^\s*endfunction\b", code):
            in_function = False
        if re.match(r"^\s*endinterface\b", code):
            in_interface = False
    for match in ENUM_TYPE_RE.finditer(source):
        if not match.group("name").endswith("_e"):
            line = source.count("\n", 0, match.start()) + 1
            issues.append(
                diagnostic("RTL-NAME-006", path, "enum typedef must end in _e", line)
            )
    for number, line in enumerate(lines, start=1):
        code = line.split("//", 1)[0]
        if re.search(r"\bparameter\b", code) and not re.search(r"\blocalparam\b", code):
            for match in PARAM_RE.finditer(code):
                if not UPPER_CAMEL_RE.fullmatch(match.group("name")):
                    if match.group("name") in {"DATA_WIDTH"}:
                        continue
                    issues.append(
                        diagnostic(
                            "RTL-NAME-007",
                            path,
                            f"parameter '{match.group('name')}' must use UpperCamelCase",
                            number,
                        )
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


def audit_issues(root: Path, audit_path: Path, paths: list[Path]) -> list[str]:
    """Validate that the committed audit covers the current owned source set."""
    try:
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [diagnostic("RTL-AUDIT-001", audit_path, f"invalid audit record: {error}")]
    if not isinstance(audit, dict):
        return [diagnostic("RTL-AUDIT-001", audit_path, "audit record must be an object")]

    issues: list[str] = []
    if audit.get("schema_version") != 1:
        issues.append(diagnostic("RTL-AUDIT-001", audit_path, "unsupported schema_version"))
    if audit.get("profile") != "owned":
        issues.append(diagnostic("RTL-AUDIT-001", audit_path, "audit must cover the owned profile"))
    if audit.get("policy") != "docs/rtl-coding-style.md":
        issues.append(diagnostic("RTL-AUDIT-001", audit_path, "audit must identify the RTL policy"))
    boundary_record = audit.get("reviewed_boundary_record")
    required_boundary_fields = {"owner", "related_commit", "expiry", "removal_plan"}
    if not isinstance(boundary_record, dict) or not all(
        isinstance(boundary_record.get(field), str) and boundary_record[field]
        for field in required_boundary_fields
    ):
        issues.append(
            diagnostic(
                "RTL-AUDIT-001",
                audit_path,
                "reviewed boundaries require owner, related_commit, expiry, and removal_plan",
            )
        )

    inventory = audit.get("inventory")
    audited_paths: set[Path] = set()
    if not isinstance(inventory, dict):
        issues.append(diagnostic("RTL-AUDIT-001", audit_path, "missing inventory object"))
    else:
        for directory, names in inventory.items():
            if not isinstance(directory, str) or not isinstance(names, list):
                issues.append(
                    diagnostic("RTL-AUDIT-001", audit_path, "inventory entries must map paths to lists")
                )
                continue
            if not all(isinstance(name, str) for name in names):
                issues.append(
                    diagnostic("RTL-AUDIT-001", audit_path, "inventory file names must be strings")
                )
                continue
            audited_paths.update(Path(directory) / name for name in names)

    expected_paths = set(paths)
    missing = sorted(expected_paths - audited_paths)
    extra = sorted(audited_paths - expected_paths)
    if missing:
        issues.append(
            diagnostic(
                "RTL-AUDIT-002",
                audit_path,
                f"inventory is missing owned source '{missing[0]}'",
            )
        )
    if extra:
        issues.append(
            diagnostic(
                "RTL-AUDIT-003",
                audit_path,
                f"inventory names non-owned source '{extra[0]}'",
            )
        )

    rules = audit.get("rules")
    if not isinstance(rules, list):
        issues.append(diagnostic("RTL-AUDIT-001", audit_path, "missing rules list"))
    else:
        rule_ids = {
            rule.get("id")
            for rule in rules
            if isinstance(rule, dict) and isinstance(rule.get("id"), str)
        }
        missing_rules = sorted(REQUIRED_AUDIT_RULES - rule_ids)
        if missing_rules:
            issues.append(
                diagnostic(
                    "RTL-AUDIT-004",
                    audit_path,
                    f"missing rule matrix entry '{missing_rules[0]}'",
                )
            )
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--profile", default="owned", choices=("owned", "verification", "technology"))
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--audit", type=Path)
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
        if args.audit:
            audit_path = args.audit if args.audit.is_absolute() else root / args.audit
            issues.extend(audit_issues(root, audit_path, profile_files))
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
