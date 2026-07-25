#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


WARNING_TOOLS = ("iverilog", "verilator", "rtl-lint", "vcs", "yosys", "opensta")


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
TIMESTAMP_RE = re.compile(r"^\[[^]]+\]\s*")
LOCATION_RE = re.compile(
    r"(?P<path>(?:[A-Za-z]:)?[^\s:]+?\."
    r"(?:c|cc|cpp|cxx|h|hpp|py|sv|svh|tcl|v|vh)):\d+(?::\d+)?",
    re.IGNORECASE,
)


def warning_line(tool: str, line: str) -> tuple[str, str] | None:
    patterns = {
        "verilator": re.compile(r"%Warning-([A-Z0-9_]+):\s*(.*)"),
        "rtl-lint": re.compile(r"%Warning-([A-Z0-9_]+):\s*(.*)"),
        "iverilog": re.compile(r"\b(warning|sorry):\s*(.*)", re.IGNORECASE),
        "yosys": re.compile(r"\b(?:ABC:\s*)?Warning:\s*(.*)", re.IGNORECASE),
        "opensta": re.compile(r"\bWarning\s+(\d+):\s*(.*)", re.IGNORECASE),
        "vcs": re.compile(r"\bWarning(?:-\[([^]]+)\])?:\s*(.*)", re.IGNORECASE),
    }
    match = patterns[tool].search(line)
    if not match:
        return None
    if tool in ("verilator", "rtl-lint", "opensta"):
        return match.group(1), match.group(2)
    if tool == "iverilog":
        return match.group(1).lower(), match.group(2)
    if tool == "vcs":
        return match.group(1) or "warning", match.group(2)
    return "warning", match.group(1)


def normalize(root: Path, identifier: str, message: str) -> str:
    value = ANSI_RE.sub("", TIMESTAMP_RE.sub("", message.strip()))
    resolved_root = str(root.resolve())
    value = re.sub(
        re.escape(resolved_root) + r"/build/[^/\s:]+",
        "$BUILD",
        value,
    )
    value = value.replace(resolved_root, "$ROOT")
    value = LOCATION_RE.sub(lambda match: match.group("path") + ":<line>", value)
    value = re.sub(r"\s+", " ", value)
    return f"{identifier}:{value}"


def scan(tool: str, logs: list[Path], root: Path) -> dict[str, object]:
    counts: Counter[str] = Counter()
    examples: dict[str, str] = {}
    for log in logs:
        if not log.is_file():
            continue
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            parsed = warning_line(tool, line)
            if parsed is None:
                continue
            normalized = normalize(root, *parsed)
            signature = hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]
            counts[signature] += 1
            examples.setdefault(signature, normalized)
    entries = [
        {"signature": signature, "count": count, "example": examples[signature]}
        for signature, count in sorted(counts.items())
    ]
    return {"tool": tool, "logs": [str(path) for path in logs], "entries": entries}


def discover(variant_root: Path) -> dict[str, list[Path]]:
    return {
        "iverilog": sorted((variant_root / "sim/iverilog").glob("*/*.log")),
        "verilator": sorted((variant_root / "sim/verilator").glob("*.log")),
        "rtl-lint": sorted((variant_root / "lint/verilator").glob("lint.log")),
        "vcs": sorted((variant_root / "sim/vcs").glob("*/*.log")),
        "yosys": sorted((variant_root / "syn/yosys").glob("*.log")),
        "opensta": sorted((variant_root / "sta/opensta").glob("*.log")),
    }


def write_baseline(args: argparse.Namespace) -> int:
    result = scan(args.tool, [path.resolve() for path in args.log], args.root.resolve())
    baseline = {
        "schema_version": 1,
        "profile": args.profile,
        "tool": args.tool,
        "entries": result["entries"],
    }
    atomic_write(args.output, json.dumps(baseline, indent=2, sort_keys=True) + "\n")
    print(f"warning baseline: {args.output.resolve()}")
    return 0


def check(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    variant_root = args.variant_root.resolve()
    tools = [args.tool] if args.tool else WARNING_TOOLS
    logs = discover(variant_root)
    reports: dict[str, object] = {}
    failures: list[str] = []
    for tool in tools:
        if not logs[tool]:
            reports[tool] = {"status": "not_run", "entries": []}
            continue
        current = scan(tool, logs[tool], root)
        baseline_path = root / "quality/warnings" / args.profile / f"{tool}.json"
        baseline_entries: dict[str, int] = {}
        if baseline_path.is_file():
            baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
            baseline_entries = {entry["signature"]: entry["count"] for entry in baseline["entries"]}
        current_entries = {entry["signature"]: entry["count"] for entry in current["entries"]}
        new = sorted(set(current_entries) - set(baseline_entries))
        increased = sorted(
            signature
            for signature, count in current_entries.items()
            if signature in baseline_entries and count > baseline_entries[signature]
        )
        if new or increased:
            failures.append(tool)
        reports[tool] = {
            **current,
            "status": "failed" if new or increased else "passed",
            "baseline": str(baseline_path),
            "new_signatures": new,
            "increased_signatures": increased,
            "resolved_signatures": sorted(set(baseline_entries) - set(current_entries)),
        }
    output = {
        "schema_version": 1,
        "profile": args.profile,
        "status": "failed" if failures else "passed",
        "failed_tools": failures,
        "tools": reports,
    }
    atomic_write(args.output, json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"warning check: {output['status']} ({args.output.resolve()})")
    return int(bool(failures))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Manage normalized EDA warning baselines")
    subparsers = parser.add_subparsers(dest="command", required=True)
    baseline = subparsers.add_parser("baseline")
    baseline.add_argument("--root", type=Path, default=ROOT)
    baseline.add_argument("--profile", required=True)
    baseline.add_argument("--tool", choices=WARNING_TOOLS, required=True)
    baseline.add_argument("--log", type=Path, action="append", required=True)
    baseline.add_argument("--output", type=Path, required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--root", type=Path, default=ROOT)
    check_parser.add_argument("--profile", required=True)
    check_parser.add_argument("--variant-root", type=Path, required=True)
    check_parser.add_argument("--tool", choices=WARNING_TOOLS)
    check_parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return write_baseline(args) if args.command == "baseline" else check(args)


if __name__ == "__main__":
    raise SystemExit(main())
