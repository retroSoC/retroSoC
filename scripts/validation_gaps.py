#!/usr/bin/env python3
"""Validate and expose explicitly owned validation gaps."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.agent_control import dump_json, read_json, safe_relative_path  # noqa: E402
from scripts.flow_control import write_json  # noqa: E402

SOC_VALUES = {"TINY", "MINI", "STD", "PRO"}
PDK_VALUES = {"IHP130", "ICS55", "GF180", "SKY130"}
GAP_STATUSES = {"deferred", "blocked", "resolved"}
EVIDENCE_STATUSES = {"PASS", "FAIL", "SKIPPED", "NOT_RUN"}
REQUIRED_GAP_FIELDS = {
    "id",
    "status",
    "scope",
    "source_revision",
    "owner",
    "approved_by",
    "approved_at",
    "review_by",
    "reason",
    "blocked_stages",
    "prohibited_claims",
    "evidence",
    "resolution",
}


def parse_date(value: str) -> date:
    return date.fromisoformat(value)


def validate_gap(gap: dict[str, Any], *, today: date | None = None) -> list[str]:
    issues = []
    if set(gap) != REQUIRED_GAP_FIELDS:
        issues.append("gap fields must match the declared contract")
    for field in ("id", "owner", "approved_by", "reason"):
        if not isinstance(gap.get(field), str) or not gap.get(field):
            issues.append(f"gap {field} must be non-empty")
    if gap.get("status") not in GAP_STATUSES:
        issues.append("gap status is invalid")
    if (
        not isinstance(gap.get("source_revision"), str)
        or len(gap["source_revision"]) != 40
        or any(character not in "0123456789abcdef" for character in gap["source_revision"])
    ):
        issues.append("gap source_revision must be a full lowercase SHA")
    for field in ("approved_at",):
        try:
            datetime.fromisoformat(gap.get(field, "").replace("Z", "+00:00"))
        except (TypeError, ValueError) as error:
            issues.append(f"gap {field} is invalid: {error}")
    try:
        review_by = parse_date(gap.get("review_by", ""))
        if gap.get("status") != "resolved" and today is not None and review_by < today:
            issues.append("gap review_by is overdue")
    except (TypeError, ValueError) as error:
        issues.append(f"gap review_by is invalid: {error}")
    scope = gap.get("scope", {})
    if set(scope) != {"soc", "pdk", "profile"}:
        issues.append("gap scope must contain soc, pdk, and profile")
    if scope.get("soc") not in SOC_VALUES or scope.get("pdk") not in PDK_VALUES:
        issues.append("gap scope has an unsupported SoC or PDK")
    if not isinstance(scope.get("profile"), str) or not safe_relative_path(scope["profile"]):
        issues.append("gap profile must be repository-relative")
    for field in ("blocked_stages", "prohibited_claims", "resolution"):
        if not isinstance(gap.get(field), list) or not gap[field] or any(not isinstance(item, str) or not item for item in gap[field]):
            issues.append(f"gap {field} must be a non-empty string list")
    evidence = gap.get("evidence", [])
    if not isinstance(evidence, list):
        issues.append("gap evidence must be a list")
    else:
        for item in evidence:
            if set(item) != {"kind", "uri", "status"} or item.get("status") not in EVIDENCE_STATUSES:
                issues.append("gap evidence has an invalid kind/uri/status")
                continue
            uri = item.get("uri", "")
            if not isinstance(uri, str) or not uri or not (uri.startswith(("http://", "https://")) or safe_relative_path(uri)):
                issues.append("gap evidence URI is unsafe")
    return issues


def validate_document(document: dict[str, Any], *, today: date | None = None) -> list[str]:
    if document.get("schema_version") != 1 or not isinstance(document.get("gaps"), list):
        return ["validation gap document must have schema_version 1 and a gaps list"]
    identifiers = [item.get("id") for item in document["gaps"] if isinstance(item, dict)]
    issues = []
    if len(set(identifiers)) != len(identifiers):
        issues.append("validation gap IDs must be unique")
    for gap in document["gaps"]:
        if not isinstance(gap, dict):
            issues.append("gap must be an object")
        else:
            issues.extend(validate_gap(gap, today=today))
    return sorted(set(issues))


def load_gaps(root: Path) -> list[dict[str, Any]]:
    document = read_json(root / "quality/validation-gaps.json")
    issues = validate_document(document, today=date.today())
    if issues:
        raise ValueError("invalid validation gap registry: " + "; ".join(issues))
    return document["gaps"]


def relevant_gaps(task: dict[str, Any], gaps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    targets = set(task.get("target_socs", []))
    pdks = set(task.get("validation", {}).get("pdks", []))
    resolved = set(task.get("resolves_gaps", []))
    selected = []
    for gap in gaps:
        scope = gap["scope"]
        if gap["status"] == "resolved" or gap["id"] in resolved:
            continue
        if targets and scope["soc"] not in targets:
            continue
        if pdks and scope["pdk"] not in pdks:
            continue
        selected.append(gap)
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        root = args.root.resolve()
        document = read_json(root / "quality/validation-gaps.json")
        issues = validate_document(document, today=date.today())
        open_count = sum(item.get("status") != "resolved" for item in document.get("gaps", []))
        result = {"schema_version": 1, "status": "FAIL" if issues else "PASS", "issues": issues, "open_count": open_count}
        if args.output:
            write_json(args.output, result)
        print(dump_json(result), end="")
        return int(bool(issues))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"validation gaps: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
