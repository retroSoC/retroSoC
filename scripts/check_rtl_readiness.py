#!/usr/bin/env python3
"""Validate the machine-readable RTL readiness and synthesis-intent record."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


STATUSES = {"prototype", "verified", "rtl-freeze", "tapeout-ready"}
INTENT_KEYS = {"registers", "reset", "clock_enable", "memory", "pipeline"}
EVIDENCE_KINDS = {
    "cdc",
    "equivalence",
    "formal",
    "format",
    "lint",
    "metrics",
    "release",
    "simulation",
    "sta",
    "synthesis",
    "warning",
}
REQUIRED_EVIDENCE_BY_STATUS = {
    "verified": {"format", "lint", "simulation", "synthesis"},
    "rtl-freeze": {"equivalence"},
    "tapeout-ready": {
        "cdc",
        "equivalence",
        "format",
        "lint",
        "metrics",
        "release",
        "simulation",
        "sta",
        "synthesis",
        "warning",
    },
}


def issue(path: Path, message: str) -> str:
    return f"{path}: {message}"


def nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def check_evidence(root: Path, record_path: Path, target: dict[str, Any]) -> list[str]:
    problems: list[str] = []
    evidence = target.get("required_evidence")
    if not isinstance(evidence, list):
        return [issue(record_path, f"target {target.get('name', '<unnamed>')} required_evidence must be a list")]

    kinds: set[str] = set()
    for index, item in enumerate(evidence):
        if not isinstance(item, dict):
            problems.append(issue(record_path, f"evidence {index} must be an object"))
            continue
        kind = item.get("kind")
        evidence_path = item.get("path")
        if kind not in EVIDENCE_KINDS:
            problems.append(issue(record_path, f"evidence {index} has an unsupported kind"))
        elif kind in kinds:
            problems.append(issue(record_path, f"target {target.get('name')} duplicates evidence kind {kind}"))
        else:
            kinds.add(kind)
        if not nonempty_string(evidence_path):
            problems.append(issue(record_path, f"evidence {index} must contain a non-empty path"))
        elif not (root / evidence_path).is_file():
            problems.append(issue(record_path, f"evidence path does not exist: {evidence_path}"))

    status = target.get("status")
    required_kinds = set(REQUIRED_EVIDENCE_BY_STATUS.get(status, set()))
    missing = sorted(required_kinds - kinds)
    if missing:
        problems.append(issue(record_path, f"target {target['name']} is missing evidence: {', '.join(missing)}"))
    return problems


def check_target(root: Path, record_path: Path, target: Any) -> list[str]:
    if not isinstance(target, dict):
        return [issue(record_path, "each target must be an object")]
    problems: list[str] = []
    name = target.get("name")
    if not nonempty_string(name):
        problems.append(issue(record_path, "target name must be a non-empty string"))
    status = target.get("status")
    if status not in STATUSES:
        problems.append(issue(record_path, f"target {name or '<unnamed>'} has invalid status"))

    paths = target.get("paths")
    if not isinstance(paths, list) or not paths or not all(nonempty_string(path) for path in paths):
        problems.append(issue(record_path, f"target {name or '<unnamed>'} paths must be a non-empty string list"))
    else:
        for path in paths:
            if not (root / path).exists():
                problems.append(issue(record_path, f"target {name} path does not exist: {path}"))

    profiles = target.get("configuration_profiles")
    if not isinstance(profiles, list) or not profiles or not all(nonempty_string(profile) for profile in profiles):
        problems.append(issue(record_path, f"target {name or '<unnamed>'} configuration_profiles must be a non-empty string list"))

    intent = target.get("synthesis_intent")
    if not isinstance(intent, dict):
        problems.append(issue(record_path, f"target {name or '<unnamed>'} synthesis_intent must be an object"))
    else:
        for key in sorted(INTENT_KEYS):
            if not nonempty_string(intent.get(key)):
                problems.append(issue(record_path, f"target {name or '<unnamed>'} synthesis_intent.{key} is required"))

    if status in {"rtl-freeze", "tapeout-ready"}:
        if not nonempty_string(target.get("baseline_revision")):
            problems.append(issue(record_path, f"target {name} requires baseline_revision at {status} status"))
        if not nonempty_string(target.get("configuration_digest")):
            problems.append(issue(record_path, f"target {name} requires configuration_digest at {status} status"))

    problems.extend(check_evidence(root, record_path, target))

    waivers = target.get("waivers", [])
    if not isinstance(waivers, list):
        problems.append(issue(record_path, f"target {name or '<unnamed>'} waivers must be a list"))
    else:
        for index, waiver in enumerate(waivers):
            if not isinstance(waiver, dict):
                problems.append(issue(record_path, f"waiver {index} must be an object"))
                continue
            for key in ("reason", "owner", "path", "issue", "expiry"):
                if not nonempty_string(waiver.get(key)):
                    problems.append(issue(record_path, f"waiver {index} is missing {key}"))
    return problems


def check(args: argparse.Namespace) -> int:
    record_path = args.root.resolve() / args.record
    try:
        document = json.loads(record_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(issue(record_path, f"cannot read JSON: {error}"), file=sys.stderr)
        return 1

    problems: list[str] = []
    if document.get("schema_version") != 1:
        problems.append(issue(record_path, "schema_version must be 1"))
    targets = document.get("targets")
    if not isinstance(targets, list) or not targets:
        problems.append(issue(record_path, "targets must be a non-empty list"))
    else:
        selected_targets = targets
        if args.target is not None:
            selected_targets = [
                target for target in targets
                if isinstance(target, dict) and target.get("name") == args.target
            ]
            if not selected_targets:
                problems.append(issue(record_path, f"target not found: {args.target}"))
        else:
            selected_targets = targets
        names: set[str] = set()
        for target in selected_targets:
            if isinstance(target, dict) and target.get("name") in names:
                problems.append(issue(record_path, f"duplicate target name: {target.get('name')}"))
            if isinstance(target, dict) and nonempty_string(target.get("name")):
                names.add(target["name"])
            problems.extend(check_target(args.root.resolve(), record_path, target))

    if problems:
        print("RTL readiness violations:", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"rtl-readiness-check: passed ({len(targets) if isinstance(targets, list) else 0} targets)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--record", default="rtl/rtl_readiness.json")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--target", help="check one named readiness target")
    selection.add_argument(
        "--all",
        action="store_true",
        help="check all readiness targets (the default)",
    )
    args = parser.parse_args()
    return check(args)


if __name__ == "__main__":
    raise SystemExit(main())
