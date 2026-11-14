#!/usr/bin/env python3
"""Classify CI failures, retain resource evidence, and bound explicit reruns."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.engineering_metrics import gh_json, seconds_between  # noqa: E402
from scripts.flow_control import file_digest, utc_now, write_json  # noqa: E402
from scripts.job_metrics import is_cache_step  # noqa: E402

INFRA_PATTERNS = (
    r"gnutls .*error",
    r"failed to connect",
    r"connection timed out",
    r"connection reset",
    r"early eof",
    r"rpc failed",
    r"temporary failure in name resolution",
    r"could not resolve",
    r"network is unreachable",
    r"failed to fetch",
    r"(?:could not get lock|waiting for cache lock|failed to lock|dpkg lock timeout)",
)
SOURCE_PATTERNS = (
    r"assertion failed",
    r"assertionerror",
    r"sim_test_fail",
    r"sim_test_timeout",
    r"%error",
    r"\b[1-9]\d* failed\b",
    r"\btest[^\n]*\bfailed\b",
    r"pytest.*(?:failed|error)",
)
TIMEOUT_PATTERN = r"(?:timed[ _-]out|deadline exceeded|timeout expired|flow exceeded its .*deadline)"
FLOW_TIMEOUT_PATTERN = r"(?:deadline exceeded|timeout expired|flow exceeded its .*deadline|sim_test_timeout)"


def classify_failure(conclusion: str | None, log_text: str) -> dict[str, Any]:
    normalized_conclusion = (conclusion or "").lower()
    normalized_log = log_text.lower()
    if normalized_conclusion in {"cancelled", "canceled"}:
        category = "cancelled"
    elif normalized_conclusion == "success":
        category = "success"
    elif re.search(FLOW_TIMEOUT_PATTERN, normalized_log):
        category = "timeout"
    elif any(re.search(pattern, normalized_log) for pattern in SOURCE_PATTERNS):
        category = "source_or_test_failure"
    elif re.search(r"(?:(?:does|do) not match the hashes|checksum mismatch|hash mismatch)", normalized_log):
        category = "dependency_integrity_failure"
    elif any(re.search(pattern, normalized_log) for pattern in INFRA_PATTERNS):
        category = "infrastructure_failure"
    elif re.search(TIMEOUT_PATTERN, normalized_log):
        category = "timeout"
    elif "traceback (most recent call last)" in normalized_log:
        category = "source_or_test_failure"
    else:
        category = "unknown_failure" if normalized_conclusion == "failure" else "not_a_failure"
    return {
        "category": category,
        "retryable": category == "infrastructure_failure",
        "evidence_sha256": file_digest_text(log_text),
    }


def file_digest_text(value: str) -> str:
    import hashlib

    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def rerun_decision(job: dict[str, Any], classification: dict[str, Any], expected_head: str | None = None) -> dict[str, Any]:
    decision = {"status": "NOT_ELIGIBLE", "action": "none"}
    if job.get("status") != "completed":
        decision["reason"] = "job is not complete"
    elif job.get("conclusion") in {"success", "skipped"}:
        decision["reason"] = "job did not fail"
    elif job.get("conclusion") in {"cancelled", "canceled"}:
        decision["reason"] = "cancelled jobs are not rerun automatically"
    elif int(job.get("run_attempt", 1)) > 1:
        decision["reason"] = "the one-rerun budget has already been consumed"
    elif expected_head and job.get("head_sha") != expected_head:
        decision["reason"] = "job head does not match the requested head"
    elif not job.get("head_sha"):
        decision["reason"] = "job has no source revision"
    elif not classification["retryable"]:
        decision["reason"] = f"{classification['category']} is not eligible for automatic rerun"
    else:
        decision.update(status="ELIGIBLE", action="rerun", reason="first attempt has a recognized infrastructure failure")
    return decision


def gh_text(arguments: list[str]) -> str:
    result = subprocess.run(["gh", *arguments], capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f"gh {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout


def resource_summary(log_text: str) -> dict[str, Any]:
    peak = re.findall(r"Maximum resident set size \(kbytes\):\s*(\d+)", log_text)
    user = re.findall(r"User time \(seconds\):\s*([0-9.]+)", log_text)
    system = re.findall(r"System time \(seconds\):\s*([0-9.]+)", log_text)
    elapsed = re.findall(r"Elapsed \(wall clock\) time.*?:\s*([0-9:.]+)", log_text)
    return {
        "peak_rss_kib": int(peak[-1]) if peak else None,
        "user_seconds": float(user[-1]) if user else None,
        "system_seconds": float(system[-1]) if system else None,
        "elapsed": elapsed[-1] if elapsed else None,
    }


def step_records(job: dict[str, Any]) -> list[dict[str, Any]]:
    records = []
    for step in job.get("steps", []):
        records.append(
            {
                "number": step.get("number"),
                "name": step.get("name"),
                "status": step.get("status"),
                "conclusion": step.get("conclusion"),
                "duration_seconds": seconds_between(step.get("started_at"), step.get("completed_at")),
            }
        )
    return records


def inspect_job(
    root: Path,
    repository: str,
    job_id: int,
    output: Path,
    *,
    execute: bool,
    expected_head: str | None,
) -> dict[str, Any]:
    job = gh_json(["api", f"repos/{repository}/actions/jobs/{job_id}"])
    log_text = gh_text(["api", f"repos/{repository}/actions/jobs/{job_id}/logs"])
    log_path = root / "build/engineering/ci-recovery" / f"job-{job_id}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(log_text, encoding="utf-8")
    classification = classify_failure(job.get("conclusion"), log_text)
    decision = rerun_decision(job, classification, expected_head)
    if execute and decision["status"] == "ELIGIBLE":
        gh_json(["api", "--method", "POST", f"repos/{repository}/actions/jobs/{job_id}/rerun"])
        decision["status"] = "RERUN_REQUESTED"
    steps = step_records(job)
    document = {
        "schema_version": 1,
        "repository": repository,
        "job_id": job_id,
        "run_id": job.get("run_id"),
        "run_attempt": job.get("run_attempt", 1),
        "head_sha": job.get("head_sha"),
        "name": job.get("name"),
        "status": job.get("status"),
        "conclusion": job.get("conclusion"),
        "created_at": utc_now(),
        "classification": classification,
        "rerun_decision": decision,
        "execution_mode": "execute" if execute else "dry-run",
        "log": str(log_path.resolve()),
        "log_sha256": file_digest(log_path),
        "resources": resource_summary(log_text),
        "duration_seconds": seconds_between(job.get("started_at"), job.get("completed_at")),
        "steps": steps,
        "cache_steps": [
            step for step in steps if is_cache_step(str(step.get("name", "")))
        ],
    }
    write_json(output, document)
    return document


def cache_metadata(values: list[str] | None, label: str) -> dict[str, Any]:
    result = {}
    for item in values or []:
        name, separator, value = item.partition("=")
        if not separator or not name:
            raise ValueError(f"invalid {label}: {item}")
        if label in {"cache-size", "cache-duration"}:
            number = float(value) if label == "cache-duration" else int(value)
            if number < 0:
                raise ValueError(f"{label} must not be negative")
            result[name] = number
        else:
            if re.fullmatch(r"[0-9a-f]{64}", value) is None:
                raise ValueError(f"{label} must contain a SHA-256 digest")
            result[name] = value
    return result


def cache_report(
    output: Path,
    values: list[str],
    sizes: list[str] | None = None,
    durations: list[str] | None = None,
    digests: list[str] | None = None,
    configs: list[str] | None = None,
) -> dict[str, Any]:
    caches = []
    size_values = cache_metadata(sizes, "cache-size")
    duration_values = cache_metadata(durations, "cache-duration")
    digest_values = cache_metadata(digests, "cache-digest")
    config_values = cache_metadata(configs, "cache-config-digest")
    for value in values:
        name, separator, state = value.partition("=")
        if not separator or not name:
            raise ValueError(f"invalid cache observation: {value}")
        normalized = state.lower()
        if normalized not in {"", "true", "false"}:
            raise ValueError(f"invalid cache hit state: {value}")
        caches.append(
            {
                "name": name,
                "status": "HIT" if normalized == "true" else "MISS" if normalized == "false" else "NOT_RUN",
                "bytes": size_values.get(name),
                "restore_seconds": duration_values.get(name),
                "sha256": digest_values.get(name),
                "config_sha256": config_values.get(name),
            }
        )
    names = {item["name"] for item in caches}
    for label, metadata in (
        ("cache-size", size_values),
        ("cache-duration", duration_values),
        ("cache-digest", digest_values),
        ("cache-config-digest", config_values),
    ):
        if set(metadata) - names:
            raise ValueError(f"{label} references a cache without a status observation")
    document = {"schema_version": 1, "created_at": utc_now(), "caches": caches}
    write_json(output, document)
    return document


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    inspect = subparsers.add_parser("inspect")
    inspect.add_argument("--root", type=Path, default=ROOT)
    inspect.add_argument("--repository", default="retroSoC/retroSoC")
    inspect.add_argument("--job", type=int, required=True)
    inspect.add_argument("--output", type=Path, required=True)
    inspect.add_argument("--execute", action="store_true")
    inspect.add_argument("--head-sha")
    cache = subparsers.add_parser("cache-report")
    cache.add_argument("--output", type=Path, required=True)
    cache.add_argument("--cache", action="append", default=[])
    cache.add_argument("--cache-size", action="append", default=[])
    cache.add_argument("--cache-duration", action="append", default=[])
    cache.add_argument("--cache-digest", action="append", default=[])
    cache.add_argument("--cache-config-digest", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "inspect":
            result = inspect_job(
                args.root.resolve(),
                args.repository,
                args.job,
                args.output,
                execute=args.execute,
                expected_head=args.head_sha,
            )
        else:
            result = cache_report(
                args.output,
                args.cache,
                sizes=args.cache_size,
                durations=args.cache_duration,
                digests=args.cache_digest,
                configs=args.cache_config_digest,
            )
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ci recovery: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
