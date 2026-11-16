#!/usr/bin/env python3
"""Read run-bound cache evidence without inferring unavailable measurements."""

from __future__ import annotations

import argparse
import io
import json
import math
import re
import stat
import sys
import urllib.parse
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.ci_observations import MAX_ARTIFACT_BYTES, artifact_zip  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402
from scripts.flow_control import utc_now, write_json  # noqa: E402
from scripts.job_metrics import summarize_cache  # noqa: E402

CACHE_ARTIFACT_PREFIXES = (
    "pr-regression-",
    "nightly-regression-",
    "quality-fixture-shard-",
    "full-flow-",
)
CACHE_STATUSES = {"HIT", "MISS", "NOT_RUN"}


def optional_number(value: Any, field: str) -> int | float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError(f"cache {field} must be non-negative or null")
    return value


def optional_digest(value: Any, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise ValueError(f"cache {field} must be a SHA-256 digest or null")
    return value


def cache_metadata(repository: str, key: str | None) -> dict[str, Any]:
    if key is None:
        return {"cache_id": None, "bytes": None, "metadata_status": "NOT_MEASURED"}
    if not isinstance(key, str) or not key:
        raise ValueError("cache key must be non-empty or null")
    document = gh_json(
        ["api", f"repos/{repository}/actions/caches?key={urllib.parse.quote(key, safe='')}"]
    )
    entries = document.get("caches") if isinstance(document, dict) else None
    if not isinstance(entries, list) or any(not isinstance(entry, dict) for entry in entries):
        raise RuntimeError("cache metadata response is incomplete")
    matching = [entry for entry in entries if entry.get("key") == key]
    if len(matching) != 1:
        return {"cache_id": None, "bytes": None, "metadata_status": "AMBIGUOUS" if matching else "NOT_FOUND"}
    entry = matching[0]
    size = entry.get("size_in_bytes")
    if isinstance(size, bool) or not isinstance(size, int) or size < 0:
        raise ValueError("GitHub cache size must be a non-negative integer")
    return {"cache_id": entry.get("id"), "bytes": size, "metadata_status": "MEASURED"}


def cache_records(
    repository: str,
    run: dict[str, Any],
    artifact: dict[str, Any],
    payload: bytes,
    payload_sha256: str,
) -> list[dict[str, Any]]:
    records = []
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            if path.name != "cache.json":
                continue
            if path.is_absolute() or ".." in path.parts or info.is_dir():
                raise ValueError("cache report path is unsafe")
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("cache report must not be a symlink")
            if info.file_size > MAX_ARTIFACT_BYTES:
                raise ValueError("cache report exceeds the observation limit")
            document = json.loads(archive.read(info))
            if not isinstance(document, dict) or document.get("schema_version") != 1 or not isinstance(document.get("caches"), list):
                raise ValueError("cache report requires schema_version=1 and a caches list")
            names = set()
            for entry in document["caches"]:
                if not isinstance(entry, dict):
                    raise ValueError("cache report entries must be objects")
                name = entry.get("name")
                status = entry.get("status")
                if not isinstance(name, str) or not name or name in names or status not in CACHE_STATUSES:
                    raise ValueError("cache report contains invalid or duplicate cache identities")
                names.add(name)
                key = entry.get("key")
                metadata = cache_metadata(repository, key)
                records.append(
                    {
                        "run_id": run["id"],
                        "run_attempt": run.get("run_attempt", 1),
                        "workflow": run.get("name"),
                        "head_sha": run.get("head_sha"),
                        "artifact_id": artifact["id"],
                        "artifact_name": artifact["name"],
                        "artifact_sha256": payload_sha256,
                        "artifact_bytes": artifact.get("size_in_bytes"),
                        "report_path": info.filename,
                        "cache_name": name,
                        "key": key,
                        "hit_status": status,
                        "bytes": metadata["bytes"],
                        "cache_id": metadata["cache_id"],
                        "metadata_status": metadata["metadata_status"],
                        "restore_seconds": optional_number(entry.get("restore_seconds"), "restore_seconds"),
                        "sha256": optional_digest(entry.get("sha256"), "sha256"),
                        "config_sha256": optional_digest(entry.get("config_sha256"), "config_sha256"),
                    }
                )
    return records


def collect_cache_artifacts(repository: str, runs: list[dict[str, Any]]) -> dict[str, Any]:
    observations = []
    issues = []
    unavailable_run_ids = []
    artifact_count = 0
    for run in runs:
        if run.get("status") != "completed":
            continue
        try:
            inventory = gh_json(["api", f"repos/{repository}/actions/runs/{run['id']}/artifacts?per_page=100"])
            artifacts = inventory.get("artifacts", [])
            if inventory.get("total_count") != len(artifacts):
                raise RuntimeError("cache artifact inventory is incomplete")
            candidates = [
                artifact
                for artifact in artifacts
                if not artifact.get("expired")
                and isinstance(artifact.get("name"), str)
                and artifact["name"].startswith(CACHE_ARTIFACT_PREFIXES)
            ]
            for artifact in candidates:
                payload, digest = artifact_zip(repository, artifact["id"])
                observations.extend(cache_records(repository, run, artifact, payload, digest))
                artifact_count += 1
        except (OSError, RuntimeError, ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
            unavailable_run_ids.append(run["id"])
            issues.append(f"run {run['id']} cache observation unavailable: {error}")
    result = {
        "schema_version": 1,
        "created_at": utc_now(),
        "measurement_status": "PARTIAL" if issues else "MEASURED" if observations else "NOT_MEASURED",
        "artifact_count": artifact_count,
        "observation_count": len(observations),
        "summary": summarize_cache(observations),
        "issues": issues,
        "unavailable_run_ids": sorted(set(unavailable_run_ids)),
        "observations": observations,
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--run", type=int, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        runs = [gh_json(["api", f"repos/{args.repository}/actions/runs/{number}"]) for number in args.run]
        result = collect_cache_artifacts(args.repository, runs)
        write_json(args.output, result)
        print(json.dumps({key: value for key, value in result.items() if key != "observations"}, indent=2, sort_keys=True))
        return int(result["measurement_status"] == "PARTIAL")
    except (OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"cache artifacts: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
