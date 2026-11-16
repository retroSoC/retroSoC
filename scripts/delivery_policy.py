#!/usr/bin/env python3
"""Evaluate merge-queue and metric-promotion readiness without applying changes."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import emit_json, read_json, safe_relative_path  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402
from scripts.flow_control import utc_now  # noqa: E402

REVISION = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
METRIC_KEYS = (
    "firmware.retrosoc_fw.bin.bytes",
    "synthesis.top_area",
    "synthesis.top_cells",
    "timing.wns_max",
)


def load_policy(root: Path) -> dict[str, Any]:
    policy = read_json(root / "quality/delivery-policy.json")
    if policy.get("schema_version") != 1:
        raise ValueError("delivery policy schema_version must be 1")
    queue = policy.get("merge_queue", {})
    if queue.get("minimum_ready_prs") != 3 or queue.get("minimum_conflicting_prs") != 2:
        raise ValueError("merge queue requires three ready PRs and two conflicting PRs before evaluation")
    if not isinstance(queue.get("required_workflows"), list) or not queue["required_workflows"]:
        raise ValueError("merge queue requires an explicit workflow parity set")
    metrics = policy.get("metrics", {})
    baseline_policy = read_json(root / "quality/metrics/policy.json")
    if metrics.get("required_samples") != baseline_policy.get("required_baseline_samples"):
        raise ValueError("delivery metric sample count differs from the active metrics policy")
    if metrics["required_samples"] != 10 or metrics.get("require_reviewed_baseline") is not True:
        raise ValueError("metric promotion requires ten samples and a reviewed baseline")
    return policy


def merge_group_parity(root: Path, workflows: list[str]) -> dict[str, Any]:
    missing = []
    for name in workflows:
        path = root / ".github/workflows" / name
        if not path.is_file() or not re.search(r"^  merge_group:\s*$", path.read_text(encoding="utf-8"), re.MULTILINE):
            missing.append(name)
    return {
        "supported": not missing,
        "missing": missing,
        "reason": "every required workflow needs merge_group coverage with its existing aggregate gates" if missing else None,
    }


def evaluate_merge_queue(root: Path, policy: dict[str, Any], pulls: list[dict[str, Any]]) -> dict[str, Any]:
    ready = [
        pull
        for pull in pulls
        if pull.get("baseRefName") == "dev"
        and pull.get("isDraft") is False
        and pull.get("headRepositoryOwner", {}).get("login") == "retroSoC"
    ]
    conflicts = [
        pull["number"]
        for pull in ready
        if pull.get("mergeable") == "CONFLICTING" or pull.get("mergeStateStatus") == "DIRTY"
    ]
    parity = merge_group_parity(root, policy["required_workflows"])
    reasons = []
    if len(ready) < policy["minimum_ready_prs"]:
        reasons.append("fewer than three ready PRs compete for dev")
    if len(conflicts) < policy["minimum_conflicting_prs"]:
        reasons.append("fewer than two conflicting PRs show an integration bottleneck")
    if not parity["supported"]:
        reasons.append("required merge_group workflow coverage is incomplete")
    return {
        "decision": "NOT_RECOMMENDED" if reasons else "ELIGIBLE_FOR_REVIEW",
        "ready_pr_count": len(ready),
        "conflicting_pr_numbers": sorted(conflicts),
        "conflicting_pr_count": len(conflicts),
        "merge_group": parity,
        "reasons": reasons,
        "changes_applied": False,
    }


def numeric_values(value: Any, prefix: str = "") -> dict[str, float]:
    if isinstance(value, dict):
        output = {}
        for key, child in value.items():
            output.update(numeric_values(child, f"{prefix}.{key}" if prefix else key))
        return output
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return {prefix: float(value)}
    return {}


def validate_samples(root: Path, samples: Any) -> tuple[list[dict[str, Any]], list[str]]:
    if not isinstance(samples, list):
        return [], ["metric samples must be a list"]
    valid = []
    issues = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            issues.append(f"sample {index} is not an object")
            continue
        required = {"source_revision", "profile", "tool_lock_sha256", "status", "metrics"}
        if set(sample) != required:
            issues.append(f"sample {index} fields do not match the required identity contract")
            continue
        if not REVISION.fullmatch(sample["source_revision"]):
            issues.append(f"sample {index} has an invalid source revision")
        if not DIGEST.fullmatch(sample["tool_lock_sha256"]):
            issues.append(f"sample {index} has an invalid tool lock digest")
        if sample["status"] not in {"PASS", "passed", "success"}:
            issues.append(f"sample {index} is not successful")
        if not safe_relative_path(sample["profile"]) or not (root / sample["profile"]).is_file():
            issues.append(f"sample {index} profile is missing or unsafe")
        values = numeric_values(sample["metrics"])
        if any(key not in values for key in METRIC_KEYS):
            issues.append(f"sample {index} lacks required firmware, synthesis, and timing metrics")
        valid.append(sample)
    revisions = [sample["source_revision"] for sample in valid]
    if len(set(revisions)) != len(revisions):
        issues.append("metric sample source revisions must be unique")
    profiles = {sample["profile"] for sample in valid}
    if len(profiles) > 1:
        issues.append("metric samples must use the same profile")
    locks = {sample["tool_lock_sha256"] for sample in valid}
    if len(locks) > 1:
        issues.append("metric samples must use identical locked tools")
    return valid, issues


def reviewed_baseline(root: Path, samples: list[dict[str, Any]]) -> dict[str, Any]:
    path = root / "quality/metrics/baseline.json"
    if not path.is_file():
        return {"present": False, "valid": False, "reason": "no committed reviewed baseline exists"}
    baseline = read_json(path)
    issues = []
    if baseline.get("sample_count") != 10 or not isinstance(baseline.get("values"), dict):
        issues.append("baseline must contain median values from ten samples")
    review = baseline.get("review", {})
    if not isinstance(review.get("approved_by"), str) or not review["approved_by"].startswith("@"):
        issues.append("baseline review must name a maintainer")
    if not review.get("approved_at"):
        issues.append("baseline review timestamp is missing")
    if samples:
        if baseline.get("profile") != samples[0]["profile"] or baseline.get("tool_lock_sha256") != samples[0]["tool_lock_sha256"]:
            issues.append("baseline profile or tool lock differs from the validated samples")
    elif not safe_relative_path(baseline.get("profile", "")) or not DIGEST.fullmatch(baseline.get("tool_lock_sha256", "")):
        issues.append("baseline identity is incomplete")
    return {"present": True, "valid": not issues, "issues": issues}


def evaluate_metrics(root: Path, policy: dict[str, Any], runs: list[dict[str, Any]], samples: Any) -> dict[str, Any]:
    successful_main = [
        run["id"]
        for run in runs
        if run.get("name") == "quality"
        and run.get("conclusion") == "success"
        and run.get("event") in {"push", "workflow_dispatch", "schedule"}
    ]
    valid_samples, issues = validate_samples(root, samples)
    baseline = reviewed_baseline(root, valid_samples)
    reasons = list(issues)
    if len(valid_samples) < policy["required_samples"]:
        reasons.append("fewer than ten validated same-profile, same-tool metric samples exist")
    if not baseline["valid"]:
        reasons.append("a valid reviewed baseline is missing")
    return {
        "decision": "HOLD" if reasons else "ELIGIBLE_FOR_REVIEW",
        "mode": read_json(root / "quality/metrics/policy.json")["mode"],
        "successful_main_quality_run_count": len(successful_main),
        "successful_main_quality_run_ids": successful_main,
        "valid_metric_sample_count": len(valid_samples),
        "baseline": baseline,
        "reasons": reasons,
        "changes_applied": False,
    }


def evaluate(
    root: Path,
    pulls: list[dict[str, Any]],
    runs: list[dict[str, Any]],
    samples: Any,
    source: str,
) -> dict[str, Any]:
    policy = load_policy(root)
    return {
        "schema_version": 1,
        "source": source,
        "collected_at": utc_now(),
        "evaluation_only": True,
        "merge_queue": evaluate_merge_queue(root, policy["merge_queue"], pulls),
        "metrics": evaluate_metrics(root, policy["metrics"], runs, samples),
        "policy_changes": [],
    }


def collect_github(root: Path, repository: str) -> dict[str, Any]:
    del root
    pulls = gh_json(
        [
            "pr",
            "list",
            "--repo",
            repository,
            "--state",
            "open",
            "--limit",
            "50",
            "--json",
            "number,isDraft,baseRefName,headRefName,mergeable,mergeStateStatus,headRepositoryOwner",
        ]
    )
    runs = gh_json(["api", f"repos/{repository}/actions/runs?branch=main&status=success&per_page=100"])
    return {"pulls": pulls, "runs": runs.get("workflow_runs", []), "samples": []}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--pulls", type=Path)
    parser.add_argument("--runs", type=Path)
    parser.add_argument("--samples", type=Path)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = args.root.resolve()
        if args.offline:
            if not args.pulls or not args.runs or not args.samples:
                raise ValueError("offline evaluation requires --pulls, --runs, and --samples")
            pulls = read_json(args.pulls)
            runs_document = read_json(args.runs)
            runs = runs_document.get("workflow_runs", runs_document) if isinstance(runs_document, dict) else runs_document
            samples = read_json(args.samples)
            source = "offline"
        else:
            if args.pulls or args.runs or args.samples:
                raise ValueError("offline evidence paths require --offline")
            document = collect_github(root, args.repository)
            pulls = document["pulls"]
            runs = document["runs"]
            samples = document["samples"]
            source = "github"
        if not isinstance(pulls, list) or not isinstance(runs, list):
            raise ValueError("pull and run evidence must be lists")
        result = evaluate(root, pulls, runs, samples, source)
        emit_json(result, args.output)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"delivery policy: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
