#!/usr/bin/env python3
"""Collect privacy-preserving delivery metrics from GitHub run and pull-request metadata."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402


def timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def seconds_between(start: str | None, end: str | None) -> float | None:
    first = timestamp(start)
    second = timestamp(end)
    if first is None or second is None:
        return None
    return round((second - first).total_seconds(), 3)


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return round(ordered[index], 3)


def median(values: list[float]) -> float | None:
    return round(statistics.median(values), 3) if values else None


def pr_category(pull: dict[str, Any]) -> str:
    branch = pull.get("headRefName", "")
    if pull.get("baseRefName") == "main" and branch == "dev":
        return "release_integration"
    if branch.startswith("dependabot/"):
        return "dependabot"
    return "topic"


def normalize_runs(document: dict[str, Any]) -> list[dict[str, Any]]:
    runs = []
    for run in document.get("workflow_runs", document.get("runs", [])):
        runs.append(
            {
                "id": run["id"],
                "name": run["name"],
                "event": run.get("event"),
                "status": run.get("status"),
                "conclusion": run.get("conclusion"),
                "head_branch": run.get("head_branch", run.get("headBranch")),
                "head_sha": run.get("head_sha", run.get("headSha")),
                "run_attempt": int(run.get("run_attempt", run.get("runAttempt", 1))),
                "created_at": run.get("created_at", run.get("createdAt")),
                "updated_at": run.get("updated_at", run.get("updatedAt")),
                "duration_seconds": seconds_between(
                    run.get("run_started_at", run.get("created_at", run.get("createdAt"))),
                    run.get("updated_at", run.get("updatedAt")),
                ),
            }
        )
    return runs


def normalize_pulls(document: Any) -> list[dict[str, Any]]:
    source = document.get("pull_requests", document) if isinstance(document, dict) else document
    pulls = []
    for pull in source:
        commits = pull.get("commits", [])
        reviews = pull.get("reviews", [])
        pulls.append(
            {
                "number": pull["number"],
                "base": pull.get("baseRefName", pull.get("base")),
                "branch": pull.get("headRefName", pull.get("branch")),
                "category": pr_category(pull),
                "created_at": pull.get("created_at", pull.get("createdAt")),
                "closed_at": pull.get("closed_at", pull.get("closedAt")),
                "merged_at": pull.get("merged_at", pull.get("mergedAt")),
                "merge_commit": (pull.get("mergeCommit") or {}).get("oid")
                if isinstance(pull.get("mergeCommit"), dict)
                else pull.get("merge_commit"),
                "commit_count": len(commits) if isinstance(commits, list) else pull.get("commit_count", 0),
                "review_count": len(reviews) if isinstance(reviews, list) else pull.get("review_count", 0),
                "lead_time_seconds": seconds_between(
                    pull.get("created_at", pull.get("createdAt")),
                    pull.get("merged_at", pull.get("mergedAt")),
                ),
            }
        )
    return pulls


def summarize(
    runs: list[dict[str, Any]],
    pulls: list[dict[str, Any]],
    jobs: list[dict[str, Any]] | None = None,
    delivery_records: list[dict[str, Any]] | None = None,
    cache_observations: list[dict[str, Any]] | None = None,
    observations: dict[str, Any] | None = None,
) -> dict[str, Any]:
    workflows = []
    for name in sorted({run["name"] for run in runs}):
        selected = [run for run in runs if run["name"] == name]
        durations = [run["duration_seconds"] for run in selected if run["duration_seconds"] is not None]
        workflows.append(
            {
                "name": name,
                "run_count": len(selected),
                "success_count": sum(run["conclusion"] == "success" for run in selected),
                "failure_count": sum(run["conclusion"] == "failure" for run in selected),
                "cancelled_count": sum(run["conclusion"] == "cancelled" for run in selected),
                "duration_seconds_median": median(durations),
                "duration_seconds_p95": percentile(durations, 0.95),
                "ci_minutes_total": round(sum(durations) / 60, 3),
                "rerun_count": sum(max(int(run.get("run_attempt", 1)) - 1, 0) for run in selected),
                "rerun_ci_minutes_total": round(
                    sum(
                        run["duration_seconds"]
                        for run in selected
                        if int(run.get("run_attempt", 1)) > 1 and run["duration_seconds"] is not None
                    )
                    / 60,
                    3,
                ),
            }
        )
    merged = [pull for pull in pulls if pull["merged_at"]]
    categories = []
    for category in ("topic", "dependabot", "release_integration"):
        selected = [pull for pull in pulls if pull["category"] == category]
        categories.append(
            {
                "category": category,
                "count": len(selected),
                "merged_count": sum(pull["merged_at"] is not None for pull in selected),
            }
        )
    result = {
        "workflow_count": len(workflows),
        "run_count": len(runs),
        "successful_run_count": sum(run["conclusion"] == "success" for run in runs),
        "failed_run_count": sum(run["conclusion"] == "failure" for run in runs),
        "workflows": workflows,
        "pull_request_count": len(pulls),
        "merged_pull_request_count": len(merged),
        "merged_without_review_count": sum(pull["review_count"] == 0 for pull in merged),
        "commits_per_pull_request_median": median([float(pull["commit_count"]) for pull in pulls]),
        "reviews_per_pull_request_median": median([float(pull["review_count"]) for pull in pulls]),
        "merged_lead_time_seconds_median": median(
            [pull["lead_time_seconds"] for pull in merged if pull["lead_time_seconds"] is not None]
        ),
        "pull_request_categories": categories,
    }
    from scripts.ci_observations import summarize_shadow
    from scripts.delivery_metrics import summarize_delivery
    from scripts.job_metrics import first_pass_summary, summarize_cache, summarize_jobs

    result.update(
        first_pass=first_pass_summary(runs),
        jobs=summarize_jobs(jobs or []),
        delivery=summarize_delivery(delivery_records or []),
        cache=summarize_cache(cache_observations or []),
        observations=observations
        if observations is not None
        else {
            "delivery_policy": {"measurement_status": "NOT_MEASURED"},
            "incremental_shadow": summarize_shadow(None),
        },
    )
    return result


def gh_json(arguments: list[str]) -> Any:
    result = subprocess.run(
        ["gh", *arguments], text=True, capture_output=True, check=False
    )
    if result.returncode:
        raise RuntimeError(f"gh {' '.join(arguments)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def policy_observation(repository: str) -> dict[str, Any]:
    from scripts.delivery_policy import collect_github, evaluate

    document = collect_github(ROOT, repository)
    return {
        "measurement_status": "MEASURED",
        "evaluation": evaluate(
            ROOT,
            document["pulls"],
            document["runs"],
            document["samples"],
            "github",
        ),
    }


def collect(repository: str, limit: int, delivery_dir: Path | None = None) -> dict[str, Any]:
    if not 1 <= limit <= 100:
        raise ValueError("sample limit must be between 1 and 100")
    run_document = gh_json(["api", f"repos/{repository}/actions/runs?per_page={limit}"])
    pull_document = gh_json(
        [
            "pr",
            "list",
            "--repo",
            repository,
            "--state",
            "all",
            "--limit",
            str(limit),
            "--json",
            "number,createdAt,closedAt,mergedAt,baseRefName,headRefName,mergeCommit,commits,reviews",
        ]
    )
    runs = normalize_runs(run_document)
    pulls = normalize_pulls(pull_document)
    from scripts.ci_observations import collect_shadow
    from scripts.delivery_metrics import collect_delivery
    from scripts.job_metrics import cache_step_observations, collect_jobs

    job_result = collect_jobs(repository, runs)
    delivery = collect_delivery(repository, pulls, delivery_dir)
    shadow = collect_shadow(repository, runs)
    issues = [*job_result["issues"], *delivery["issues"], *shadow["issues"]]
    try:
        policy = policy_observation(repository)
    except (OSError, ValueError, RuntimeError) as error:
        policy = {"measurement_status": "NOT_MEASURED", "evaluation": None}
        issues.append(f"delivery policy observation unavailable: {error}")
    cache_observations = cache_step_observations(job_result["jobs"])
    observations = {"delivery_policy": policy, "incremental_shadow": shadow}
    from scripts.flow_control import source_state

    collector_state = source_state(ROOT)
    return {
        "schema_version": 1,
        "source_revision": collector_state["source_revision"],
        "source_dirty": collector_state["source_dirty"],
        "tool_lock_sha256": collector_state["tool_lock_sha256"],
        "repository": repository,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "sample_limit": limit,
        "summary": summarize(
            runs,
            pulls,
            jobs=job_result["jobs"],
            delivery_records=delivery["records"],
            cache_observations=cache_observations,
            observations=observations,
        ),
        "runs": runs,
        "jobs": job_result["jobs"],
        "delivery_records": delivery["records"],
        "cache_observations": cache_observations,
        "observations": observations,
        "pull_requests": pulls,
        "issues": issues,
        "data_complete": not issues,
        "limitations": [
            "Workflow duration is measured from run start to update and includes queue-adjacent overhead.",
            "Pull-request creation time can omit earlier local/agent design and implementation time.",
            "Review counts come from GitHub review objects and do not measure all human discussion.",
            "Recent release and Dependabot samples must not be treated as representative agent-authored task success.",
            "Cache step timing does not prove a cache hit or reveal cache size.",
            "GitHub timelines do not contain local worktree cleanup time; local delivery evidence is optional and merge-commit-bound.",
            "Policy and incremental shadow records are read-only observations and never authorize a merge, gate, or skipped test.",
            "Metrics are for engineering improvement, not individual performance evaluation.",
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    collect_parser = subparsers.add_parser("collect")
    collect_parser.add_argument("--repository", default="retroSoC/retroSoC")
    collect_parser.add_argument("--limit", type=int, default=30)
    collect_parser.add_argument("--delivery-dir", type=Path)
    collect_parser.add_argument("--output", type=Path, required=True)
    summarize_parser = subparsers.add_parser("summarize")
    summarize_parser.add_argument("--runs", type=Path, required=True)
    summarize_parser.add_argument("--pull-requests", type=Path, required=True)
    summarize_parser.add_argument("--jobs", type=Path)
    summarize_parser.add_argument("--delivery", type=Path)
    summarize_parser.add_argument("--cache-observations", type=Path)
    summarize_parser.add_argument("--delivery-policy", type=Path)
    summarize_parser.add_argument("--shadow-evidence", type=Path, action="append")
    summarize_parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "collect":
            result = collect(args.repository, args.limit, args.delivery_dir)
        else:
            from scripts.ci_observations import shadow_record, summarize_shadow

            runs = normalize_runs(read_json(args.runs))
            pulls = normalize_pulls(read_json(args.pull_requests))
            jobs_document = read_json(args.jobs) if args.jobs else []
            delivery_document = read_json(args.delivery) if args.delivery else []
            cache_document = read_json(args.cache_observations) if args.cache_observations else []
            if isinstance(jobs_document, dict) and "jobs" not in jobs_document:
                raise ValueError("jobs evidence is missing its jobs list")
            if isinstance(delivery_document, dict) and "records" not in delivery_document:
                raise ValueError("delivery evidence is missing its records list")
            if isinstance(cache_document, dict) and not ({"observations", "caches"} & set(cache_document)):
                raise ValueError("cache evidence is missing observations or caches")
            jobs = jobs_document.get("jobs", []) if isinstance(jobs_document, dict) else jobs_document
            delivery = delivery_document.get("records", []) if isinstance(delivery_document, dict) else delivery_document
            cache = cache_document.get("observations", cache_document.get("caches", [])) if isinstance(cache_document, dict) else cache_document
            if not isinstance(jobs, list) or not isinstance(delivery, list) or not isinstance(cache, list):
                raise ValueError("jobs, delivery, and cache evidence must be lists")
            policy = {"measurement_status": "NOT_MEASURED", "evaluation": None}
            if args.delivery_policy:
                policy_document = read_json(args.delivery_policy)
                if not isinstance(policy_document, dict) or policy_document.get("evaluation_only") is not True:
                    raise ValueError("delivery policy evidence must be an evaluation-only object")
                policy = {"measurement_status": "MEASURED", "evaluation": policy_document}
            shadow = (
                [shadow_record(read_json(path)) for path in args.shadow_evidence]
                if args.shadow_evidence is not None
                else None
            )
            observations = {
                "delivery_policy": policy,
                "incremental_shadow": summarize_shadow(shadow),
            }
            result = {
                "schema_version": 1,
                "summary": summarize(
                    runs,
                    pulls,
                    jobs=jobs,
                    delivery_records=delivery,
                    cache_observations=cache,
                    observations=observations,
                ),
                "runs": runs,
                "jobs": jobs,
                "delivery_records": delivery,
                "cache_observations": cache,
                "observations": observations,
                "pull_requests": pulls,
                "data_complete": bool(
                    args.jobs
                    and args.delivery
                    and args.cache_observations
                    and args.delivery_policy
                    and args.shadow_evidence is not None
                ),
            }
        atomic_write(args.output, dump_json(result))
        print(f"engineering metrics: {args.output.resolve()}")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"engineering metrics: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
