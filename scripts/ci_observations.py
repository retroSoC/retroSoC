#!/usr/bin/env python3
"""Collect read-only CI policy and shadow observations without enabling reuse."""

from __future__ import annotations

import hashlib
import io
import json
import subprocess
import zipfile
from typing import Any

from scripts.engineering_metrics import gh_json

MAX_ARTIFACT_BYTES = 16 * 1024 * 1024


def shadow_record(document: dict[str, Any], run: dict[str, Any] | None = None) -> dict[str, Any]:
    if document.get("schema_version") != 1:
        raise ValueError("incremental shadow evidence must use schema_version=1")
    if document.get("mode") != "shadow" or document.get("enabled") is not False:
        raise ValueError("engineering metrics accept only disabled shadow observations")
    if not isinstance(document.get("decision"), str) or not isinstance(document.get("issues"), list):
        raise ValueError("incremental shadow decision or issue list is missing")
    if run is not None:
        if document.get("source_revision") != run.get("head_sha") or document.get("event") != run.get("event"):
            raise ValueError("incremental shadow identity differs from its workflow run")
    current = document.get("current")
    if current is not None:
        if not isinstance(current, dict):
            raise ValueError("incremental shadow current identity must be an object")
        current = {key: value for key, value in current.items() if key != "input_files"}
    previous = document.get("previous")
    if previous is not None:
        if not isinstance(previous, dict):
            raise ValueError("incremental shadow previous identity must be an object")
        previous = {key: value for key, value in previous.items() if key != "input_files"}
    changed = document.get("changed_inputs")
    if not isinstance(changed, list):
        raise ValueError("incremental shadow changed_inputs must be a list")
    return {
        "workflow_run_id": run.get("id") if run else document.get("workflow_run_id"),
        "run_attempt": run.get("run_attempt", 1) if run else document.get("run_attempt"),
        "base_revision": document.get("base_revision"),
        "source_revision": document.get("source_revision"),
        "event": document.get("event"),
        "job_id": document.get("job_id"),
        "decision": document["decision"],
        "mode": document["mode"],
        "enabled": document["enabled"],
        "reason": document.get("reason"),
        "issues": document["issues"],
        "changed_input_count": len(changed),
        "current": current,
        "previous": previous,
    }


def summarize_shadow(records: list[dict[str, Any]] | None) -> dict[str, Any]:
    if records is None:
        return {"measurement_status": "NOT_MEASURED", "observation_count": 0, "records": []}
    decisions = sorted({record["decision"] for record in records})
    return {
        "measurement_status": "MEASURED",
        "observation_count": len(records),
        "decision_counts": {
            decision: sum(record["decision"] == decision for record in records) for decision in decisions
        },
        "invalid_count": sum(record["decision"] == "INVALID" or bool(record["issues"]) for record in records),
        "records": records,
    }


def artifact_zip(repository: str, artifact_id: int) -> tuple[bytes, str]:
    result = subprocess.run(
        ["gh", "api", f"repos/{repository}/actions/artifacts/{artifact_id}/zip"],
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"shadow artifact download failed: {result.stderr.decode(errors='replace').strip()}")
    if len(result.stdout) > MAX_ARTIFACT_BYTES:
        raise ValueError("shadow artifact exceeds the 16 MiB observation limit")
    return result.stdout, hashlib.sha256(result.stdout).hexdigest()


def collect_shadow(repository: str, runs: list[dict[str, Any]]) -> dict[str, Any]:
    records = []
    issues = []
    unavailable_run_ids = []
    for run in runs:
        if run.get("name") != "quality" or run.get("status") != "completed":
            continue
        name = f"quality-incremental-shadow-{run['id']}-{run.get('run_attempt', 1)}"
        try:
            document = gh_json(["api", f"repos/{repository}/actions/runs/{run['id']}/artifacts?per_page=100"])
            artifacts = document.get("artifacts", [])
            if document.get("total_count") != len(artifacts):
                raise RuntimeError("shadow artifact inventory is incomplete")
            matching = [item for item in artifacts if item.get("name") == name and not item.get("expired")]
            if len(matching) != 1:
                raise RuntimeError("one unexpired shadow artifact is required")
            payload, artifact_sha256 = artifact_zip(repository, matching[0]["id"])
            with zipfile.ZipFile(io.BytesIO(payload)) as archive:
                info = archive.getinfo("shadow.json")
                if info.file_size > MAX_ARTIFACT_BYTES:
                    raise ValueError("shadow JSON exceeds the 16 MiB observation limit")
                shadow = json.loads(archive.read(info))
            record = shadow_record(shadow, run)
            record.update(artifact_id=matching[0]["id"], artifact_sha256=artifact_sha256)
            records.append(record)
        except (OSError, RuntimeError, ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
            unavailable_run_ids.append(run["id"])
            issues.append(f"run {run['id']} shadow observation unavailable: {error}")
    result = summarize_shadow(records)
    result.update(issues=issues, unavailable_run_ids=unavailable_run_ids)
    if issues:
        result["measurement_status"] = "PARTIAL"
    return result
