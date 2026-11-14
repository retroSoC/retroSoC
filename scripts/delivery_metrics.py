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
