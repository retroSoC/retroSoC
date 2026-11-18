#!/usr/bin/env python3
"""Summarize native delivery timing from GitHub and optional local evidence."""

from __future__ import annotations

import statistics
from pathlib import Path
from typing import Any

from scripts.engineering_metrics import gh_json, seconds_between


def timeline_events(repository: str, number: int) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for page in range(1, 11):
        document = gh_json(
            ["api", f"repos/{repository}/issues/{number}/timeline?per_page=100&page={page}"]
        )
        if not isinstance(document, list):
            raise RuntimeError("issue timeline response is not a list")
        events.extend(document)
        if len(document) < 100:
            return events
    raise RuntimeError("issue timeline exceeded the bounded ten-page limit")


def load_local_records(directory: Path | None) -> dict[int, dict[str, Any]]:
    if directory is None or not directory.is_dir():
        return {}
    records = {}
    for path in sorted(directory.glob("pr-*-delivery.json")):
        from scripts.agent_control import read_json

        document = read_json(path)
        if isinstance(document.get("pr"), int):
            records[document["pr"]] = document
    return records


def friction_observation(local: dict[str, Any] | None) -> dict[str, Any] | None:
    if local is None:
        return None
    warnings = local.get("warnings")
    recovery = local.get("recovery")
    history = local.get("recovery_history")
    recovery_transitions = (
        len(history)
        if isinstance(history, list) and history
        else 1 if isinstance(recovery, dict) and recovery else 0
    )
    final_checks = local.get("final_checks")
    return {
        "last_check_status": local.get("last_check_status") or "NOT_RECORDED",
        "final_check_status": final_checks.get("status") or "NOT_RECORDED" if isinstance(final_checks, dict) else "NOT_RECORDED",
        "evidence_status": local.get("evidence_status") or "NOT_RECORDED",
        "cleanup_warning_count": len(warnings) if isinstance(warnings, list) else None,
        "recovery_recorded": recovery_transitions > 0,
        "recovery_from_status": recovery.get("from_status") if isinstance(recovery, dict) else None,
        "recovery_transition_count": recovery_transitions,
        "recovery_history_dropped_count": local.get("recovery_history_dropped_count")
        if type(local.get("recovery_history_dropped_count")) is int
        else None,
    }


def delivery_record(
    pull: dict[str, Any],
    events: list[dict[str, Any]],
    local: dict[str, Any] | None,
) -> dict[str, Any]:
    auto_events = [event for event in events if event.get("event") == "auto_merge_enabled"]
    auto = auto_events[-1] if auto_events else {}
    local_matches = bool(
        local
        and local.get("merge_commit")
        and local.get("merge_commit") == pull.get("merge_commit")
        and local.get("status") in {"MERGED", "MERGED_WITH_WARNINGS"}
    )
    local = local if local_matches else None
    cleanup_complete = bool(
        local and local.get("cleanup") == "COMPLETE" and not local.get("warnings")
    )
    return {
        "pr": pull["number"],
        "created_at": pull.get("created_at"),
        "merged_at": pull.get("merged_at"),
        "merge_commit": pull.get("merge_commit"),
        "auto_merge_enabled_at": auto.get("created_at"),
        "auto_merge_head": auto.get("commit_id"),
        "auto_merge_method": local.get("merge_method") if local else None,
        "local_evidence": local is not None,
        "friction": friction_observation(local),
        "agent_watch_seconds": local.get("watch_seconds") if local else None,
        "cleanup_status": local.get("cleanup") if local else "NOT_MEASURED",
        "cleanup_completed_at": local.get("reconciled_at") if cleanup_complete else None,
        "enable_delay_seconds": seconds_between(pull.get("created_at"), auto.get("created_at")),
        "merge_lead_seconds": seconds_between(pull.get("created_at"), pull.get("merged_at")),
        "cleanup_lag_seconds": seconds_between(
            pull.get("merged_at"), local.get("reconciled_at") if cleanup_complete else None
        ),
    }


def median(values: list[float]) -> float | None:
    return round(statistics.median(values), 3) if values else None


def observation_counts(observations: list[dict[str, Any]], field: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for observation in observations:
        value = observation[field]
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items()))


def summarize_friction(records: list[dict[str, Any]]) -> dict[str, Any]:
    observations = [record["friction"] for record in records if isinstance(record.get("friction"), dict)]
    return {
        "record_count": len(observations),
        "records_with_recovery": sum(item["recovery_recorded"] for item in observations),
        "recovery_transition_count": sum(item["recovery_transition_count"] for item in observations),
        "cleanup_warning_record_count": sum(
            isinstance(item["cleanup_warning_count"], int) and item["cleanup_warning_count"] > 0
            for item in observations
        ),
        "cleanup_warning_unknown_record_count": sum(
            item["cleanup_warning_count"] is None for item in observations
        ),
        "last_check_status_counts": observation_counts(observations, "last_check_status"),
        "final_check_status_counts": observation_counts(observations, "final_check_status"),
        "evidence_status_counts": observation_counts(observations, "evidence_status"),
        "scope": "Matched local delivery records only; no CI retry, human-action, or hardware-performance inference",
    }


def summarize_delivery(records: list[dict[str, Any]]) -> dict[str, Any]:
    enabled = [record for record in records if record.get("auto_merge_enabled_at")]
    unknown = [record for record in records if record.get("timeline_status") == "UNKNOWN"]
    watch = [record["agent_watch_seconds"] for record in records if isinstance(record.get("agent_watch_seconds"), (int, float))]
    cleanup = [record["cleanup_lag_seconds"] for record in records if isinstance(record.get("cleanup_lag_seconds"), (int, float))]
    return {
        "record_count": len(records),
        "auto_merge_enabled_count": len(enabled),
        "auto_merge_coverage": round(len(enabled) / len(records), 6) if records and not unknown else None,
        "unknown_timeline_count": len(unknown),
        "enable_delay_seconds_median": median([record["enable_delay_seconds"] for record in enabled if record["enable_delay_seconds"] is not None]),
        "merge_lead_seconds_median": median([record["merge_lead_seconds"] for record in records if record["merge_lead_seconds"] is not None]),
        "known_agent_watch_count": len(watch),
        "agent_watch_seconds_median": median(watch),
        "known_cleanup_count": len(cleanup),
        "cleanup_lag_seconds_median": median(cleanup),
        "local_friction": summarize_friction(records),
        "status": "INCOMPLETE" if unknown else "MEASURED",
    }


def collect_delivery(
    repository: str,
    pulls: list[dict[str, Any]],
    local_dir: Path | None = None,
) -> dict[str, Any]:
    local_records = load_local_records(local_dir)
    records = []
    issues = []
    for pull in pulls:
        try:
            events = timeline_events(repository, pull["number"])
            record = delivery_record(pull, events, local_records.get(pull["number"]))
            record["timeline_status"] = "COMPLETE"
        except (OSError, RuntimeError, ValueError) as error:
            issues.append(f"PR #{pull['number']} timeline unavailable: {error}")
            record = delivery_record(pull, [], local_records.get(pull["number"]))
            record["timeline_status"] = "UNKNOWN"
        records.append(record)
    return {
        "summary": summarize_delivery(records),
        "records": records,
        "issues": issues,
    }
