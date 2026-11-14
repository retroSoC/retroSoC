#!/usr/bin/env python3
"""Collect per-job timing and cache observations without inferring missing data."""

from __future__ import annotations

import statistics
from typing import Any

from scripts.engineering_metrics import gh_json, seconds_between


def median(values: list[float]) -> float | None:
    return round(statistics.median(values), 3) if values else None


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, int(fraction * len(ordered) + 0.999999) - 1)
    return round(ordered[index], 3)


def step_record(step: dict[str, Any]) -> dict[str, Any]:
    return {
        "number": step.get("number"),
        "name": step.get("name"),
        "status": step.get("status"),
        "conclusion": step.get("conclusion"),
        "started_at": step.get("started_at"),
        "completed_at": step.get("completed_at"),
        "duration_seconds": seconds_between(step.get("started_at"), step.get("completed_at")),
    }


def normalize_jobs(run: dict[str, Any], document: dict[str, Any]) -> list[dict[str, Any]]:
    jobs = []
    for job in document.get("jobs", []):
        jobs.append(
            {
                "id": job.get("id"),
                "run_id": run["id"],
                "run_attempt": run.get("run_attempt", 1),
                "workflow": run["name"],
                "event": run.get("event"),
                "head_sha": run.get("head_sha"),
                "name": job.get("name"),
                "status": job.get("status"),
                "conclusion": job.get("conclusion"),
                "created_at": job.get("created_at"),
                "started_at": job.get("started_at"),
                "completed_at": job.get("completed_at"),
                "duration_seconds": seconds_between(job.get("started_at"), job.get("completed_at")),
                "queue_seconds": seconds_between(job.get("created_at"), job.get("started_at")),
                "steps": [step_record(step) for step in job.get("steps", [])],
            }
        )
    return jobs


def summarize_jobs(jobs: list[dict[str, Any]]) -> dict[str, Any]:
    groups = []
    for workflow, name in sorted({(job["workflow"], job["name"]) for job in jobs}):
        selected = [job for job in jobs if job["workflow"] == workflow and job["name"] == name]
        durations = [job["duration_seconds"] for job in selected if job["duration_seconds"] is not None]
        queue = [job["queue_seconds"] for job in selected if job["queue_seconds"] is not None]
        groups.append(
            {
                "workflow": workflow,
                "name": name,
                "run_count": len(selected),
                "success_count": sum(job["conclusion"] == "success" for job in selected),
                "failure_count": sum(job["conclusion"] == "failure" for job in selected),
                "cancelled_count": sum(job["conclusion"] == "cancelled" for job in selected),
                "duration_seconds_median": median(durations),
                "duration_seconds_p95": percentile(durations, 0.95),
                "queue_seconds_median": median(queue),
                "queue_seconds_p95": percentile(queue, 0.95),
                "ci_minutes_total": round(sum(durations) / 60, 3),
                "unknown_duration_count": len(selected) - len(durations),
                "step_count": sum(len(job["steps"]) for job in selected),
            }
        )
    return {
        "job_count": len(jobs),
        "jobs": groups,
        "measurement_status": "MEASURED" if jobs else "NOT_MEASURED",
    }


def first_pass_summary(runs: list[dict[str, Any]]) -> dict[str, Any]:
    by_identity: dict[tuple[Any, Any, Any], list[dict[str, Any]]] = {}
    for run in runs:
        if run.get("status") != "completed":
            continue
        key = (run.get("head_sha"), run.get("name"), run.get("event"))
        by_identity.setdefault(key, []).append(run)
    first_attempts = []
    duplicate_count = 0
    duplicate_seconds = 0.0
    unknown_first_attempts = 0
    for attempts in by_identity.values():
        ordered = sorted(attempts, key=lambda run: (int(run.get("run_attempt", 1)), int(run["id"])))
        duplicate_count += max(len(ordered) - 1, 0)
        duplicate_seconds += sum(run.get("duration_seconds") or 0 for run in ordered[1:])
        first = ordered[0]
        if first.get("run_attempt", 1) == 1:
            first_attempts.append(first)
        else:
            unknown_first_attempts += 1
    return {
        "eligible_head_workflow_count": len(by_identity),
        "first_attempt_count": len(first_attempts),
        "first_attempt_success_count": sum(run.get("conclusion") == "success" for run in first_attempts),
        "first_attempt_pass_rate": round(
            sum(run.get("conclusion") == "success" for run in first_attempts) / len(first_attempts), 6
        ) if first_attempts else None,
        "unknown_first_attempt_count": unknown_first_attempts,
        "same_head_duplicate_run_count": duplicate_count,
        "same_head_duplicate_ci_minutes": round(duplicate_seconds / 60, 3),
    }


def is_cache_step(name: str) -> bool:
    normalized = name.lower()
    return "cache" in normalized or normalized.startswith(("restore ", "save ", "post restore ", "post save "))


def cache_step_observations(jobs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    observations = []
    for job in jobs:
        for step in job["steps"]:
            if not is_cache_step(str(step.get("name", ""))):
                continue
            observations.append(
                {
                    "run_id": job["run_id"],
                    "run_attempt": job["run_attempt"],
                    "workflow": job["workflow"],
                    "head_sha": job["head_sha"],
                    "job_id": job["id"],
                    "job_name": job["name"],
                    "step_name": step["name"],
                    "conclusion": step["conclusion"],
                    "duration_seconds": step["duration_seconds"],
                    "hit_status": "NOT_MEASURED",
                    "bytes": None,
                }
            )
    return observations


def summarize_cache(observations: list[dict[str, Any]]) -> dict[str, Any]:
    statuses = []
    durations = []
    byte_values = []
    for item in observations:
        supplied = item.get("hit_status", item.get("status", "NOT_MEASURED"))
        status = supplied if supplied in {"HIT", "MISS", "NOT_RUN"} else "NOT_MEASURED"
        statuses.append(status)
        duration = item.get("duration_seconds", item.get("restore_seconds"))
        if isinstance(duration, (int, float)) and not isinstance(duration, bool) and duration >= 0:
            durations.append(duration)
        size = item.get("bytes")
        if isinstance(size, int) and not isinstance(size, bool) and size >= 0:
            byte_values.append(size)
    measured = [status for status in statuses if status in {"HIT", "MISS"}]
    complete = bool(observations) and all(
        status in {"HIT", "MISS", "NOT_RUN"} for status in statuses
    ) and len(byte_values) == len(observations)
    return {
        "observation_count": len(observations),
        "hit_count": statuses.count("HIT"),
        "miss_count": statuses.count("MISS"),
        "not_run_count": statuses.count("NOT_RUN"),
        "not_measured_count": statuses.count("NOT_MEASURED"),
        "hit_rate": round(statuses.count("HIT") / len(measured), 6) if measured else None,
        "restore_seconds_median": median(durations),
        "cache_bytes_total": sum(byte_values) if byte_values else None,
        "cache_digest_recorded_count": sum(
            isinstance(item.get("sha256"), str) for item in observations
        ),
        "config_digest_recorded_count": sum(
            isinstance(item.get("config_sha256"), str) for item in observations
        ),
        "measurement_status": "MEASURED" if complete else "PARTIAL" if observations else "NOT_MEASURED",
    }


def collect_jobs(repository: str, runs: list[dict[str, Any]]) -> dict[str, Any]:
    jobs = []
    issues = []
    incomplete = []
    for run in runs:
        if run.get("status") != "completed":
            continue
        try:
            attempt = int(run.get("run_attempt", 1))
            if attempt < 1:
                raise ValueError("run attempt must be positive")
            identifiers = set()
            for page in range(1, 11):
                document = gh_json(
                    [
                        "api",
                        f"repos/{repository}/actions/runs/{run['id']}/attempts/{attempt}/jobs?per_page=100&page={page}",
                    ]
                )
                page_jobs = document.get("jobs", [])
                if any(job.get("id") in identifiers for job in page_jobs):
                    raise RuntimeError("job pagination returned a duplicate job")
                identifiers.update(job.get("id") for job in page_jobs)
                jobs.extend(normalize_jobs(run, document))
                if len(page_jobs) < 100:
                    break
            else:
                raise RuntimeError("job pagination exceeded the bounded ten-page limit")
            if document.get("total_count") != len(identifiers):
                raise RuntimeError("job pagination is incomplete")
        except (OSError, RuntimeError, ValueError) as error:
            incomplete.append(run["id"])
            issues.append(f"run {run['id']} jobs unavailable: {error}")
    return {"jobs": jobs, "issues": issues, "incomplete_run_ids": incomplete}
