#!/usr/bin/env python3
"""Generate unapproved Mini build-control review candidates without source writes."""

from __future__ import annotations

import argparse
import copy
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import emit_json, git_output, read_json  # noqa: E402

REVISION = re.compile(r"^[0-9a-f]{40}$")
SYSTEM_REFERENCE = "publications/datasheets/system-reference.json"


def review_reason(reason: str) -> str:
    normalized = reason.strip()
    if not normalized or len(normalized) > 2000 or "\n" in normalized or "\r" in normalized:
        raise ValueError("control review reason must be one non-empty line of at most 2000 characters")
    return normalized


def build_plan(root: Path, revision: str, reason: str) -> dict[str, Any]:
    reason = review_reason(reason)
    result: dict[str, Any] = {
        "schema_version": 1,
        "status": "BLOCKED",
        "approval_status": "REVIEW_REQUIRED",
        "applied": False,
        "source_files_modified": False,
        "source_revision": None,
        "candidate_revision": None,
        "candidate_review": None,
        "candidate_validation": "NOT_AVAILABLE",
        "ci_evidence": {"status": "NOT_AVAILABLE"},
        "issues": [],
    }
    try:
        from publications import build_datasheet as mini
        from publications.dev_reference import validate_ci_snapshot

        config = mini.read_json(root / "publications/datasheets/mini.json")
        current_review = config.get("build_control_review")
        if not isinstance(current_review, dict):
            raise ValueError("Mini build-control review must already define its evidence contract")
        source_revision = config["source_revision"]
        if REVISION.fullmatch(source_revision) is None:
            raise ValueError("Mini source revision must be a complete Git revision")
        result["source_revision"] = source_revision
        resolved = git_output(root, "rev-parse", f"{revision}^{{commit}}")
        if REVISION.fullmatch(resolved) is None:
            raise ValueError("control review requires a complete Git revision")
        if git_output(root, "merge-base", source_revision, resolved) != source_revision:
            raise ValueError("control review revision does not descend from the Mini technical snapshot")
        document_blobs = current_review.get("documentation_blobs", {})
        if not isinstance(document_blobs, dict):
            raise ValueError("Mini documentation_blobs must be an object")
        candidate = {
            "revision": resolved,
            "makefile_blob": git_output(root, "rev-parse", f"{resolved}:Makefile"),
            "documentation_blobs": {
                path: git_output(root, "rev-parse", f"{resolved}:{path}")
                for path in sorted(document_blobs)
            },
            "reason": reason,
        }
        if REVISION.fullmatch(candidate["makefile_blob"]) is None or any(
            REVISION.fullmatch(blob) is None for blob in candidate["documentation_blobs"].values()
        ):
            raise ValueError("control review requires complete blob identities")
        result["candidate_revision"] = resolved
        result["candidate_review"] = candidate
        reference = read_json(root / SYSTEM_REFERENCE)
        if reference.get("source_revision") != source_revision:
            raise ValueError("Mini system-reference and document source revisions differ")
        snapshot = reference.get("ci_snapshot")
        if not isinstance(snapshot, dict):
            raise ValueError("Mini CI snapshot is required")
        validate_ci_snapshot(snapshot, source_revision)
        result["ci_evidence"] = {
            "status": "RETAINED_UNCHANGED",
            "revision": snapshot["revision"],
            "checked_at": snapshot["checked_at"],
            "run_ids": [run["run_id"] for run in snapshot["runs"]],
        }
        candidate_config = copy.deepcopy(config)
        candidate_config["build_control_review"] = candidate
        mini.validate_source_snapshot(candidate_config)
        result["candidate_validation"] = "PASS"
        result["status"] = "READY"
    except (ImportError, KeyError, OSError, TypeError, ValueError, subprocess.CalledProcessError) as error:
        result["issues"].append(str(error))
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan", help="emit an unapproved candidate without changing source files")
    plan.add_argument("--root", type=Path, default=ROOT)
    plan.add_argument("--revision", required=True, help="Git revision whose exact control blobs are reviewed")
    plan.add_argument("--reason", required=True, help="one-line review rationale, not an approval")
    plan.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = build_plan(args.root.resolve(), args.revision, args.reason)
        emit_json(result, args.output)
        return int(result["status"] != "READY")
    except (OSError, ValueError) as error:
        print(f"publication control: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
