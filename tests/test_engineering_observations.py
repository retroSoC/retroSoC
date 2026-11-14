from __future__ import annotations

import io
import json
import subprocess
import zipfile
from pathlib import Path

import pytest

from scripts.ci_observations import collect_shadow, shadow_record, summarize_shadow
from scripts.ci_recovery import cache_report, inspect_job
from scripts.delivery_metrics import collect_delivery, delivery_record, summarize_delivery
from scripts.engineering_metrics import collect, summarize
from scripts.job_metrics import (
    cache_step_observations,
    collect_jobs,
    first_pass_summary,
    normalize_jobs,
    summarize_cache,
    summarize_jobs,
)

ROOT = Path(__file__).resolve().parents[1]


def run_document() -> dict:
    return {
        "id": 1,
        "name": "quality",
        "event": "pull_request",
        "status": "completed",
        "conclusion": "success",
        "head_sha": "a" * 40,
        "run_attempt": 1,
        "created_at": "2026-11-01T00:00:00Z",
        "updated_at": "2026-11-01T00:10:00Z",
        "duration_seconds": 600,
    }


def job_document() -> dict:
    return {
        "jobs": [
            {
                "id": 10,
                "name": "fixtures (0)",
                "status": "completed",
                "conclusion": "success",
                "created_at": "2026-11-01T00:00:00Z",
                "started_at": "2026-11-01T00:01:00Z",
                "completed_at": "2026-11-01T00:06:00Z",
                "steps": [
                    {
                        "number": 1,
                        "name": "Restore locked source dependencies",
                        "status": "completed",
                        "conclusion": "success",
                        "started_at": "2026-11-01T00:01:00Z",
                        "completed_at": "2026-11-01T00:01:10Z",
                    }
                ],
            }
        ]
    }


def pull_document() -> dict:
    return {
        "number": 1,
        "created_at": "2026-11-01T00:00:00Z",
        "merged_at": "2026-11-01T00:20:00Z",
        "merge_commit": "b" * 40,
    }


def test_job_step_queue_and_duration_metrics() -> None:
    jobs = normalize_jobs(run_document(), job_document())
    assert jobs[0]["duration_seconds"] == 300
    assert jobs[0]["queue_seconds"] == 60
    summary = summarize_jobs(jobs)
    assert summary["jobs"][0]["duration_seconds_median"] == 300
    assert summary["jobs"][0]["queue_seconds_median"] == 60
    assert summary["jobs"][0]["step_count"] == 1
    cache = cache_step_observations(jobs)
    assert cache[0]["hit_status"] == "NOT_MEASURED"
    assert cache[0]["bytes"] is None
    assert summarize_cache(cache)["hit_rate"] is None
    assert summarize_cache(cache)["restore_seconds_median"] == 10


def test_first_pass_and_duplicate_execution_are_separate() -> None:
    first = run_document()
    second = {**first, "id": 2, "run_attempt": 2, "conclusion": "failure"}
    summary = first_pass_summary([first, second])
    assert summary["first_attempt_pass_rate"] == 1.0
    assert summary["same_head_duplicate_run_count"] == 1
    assert summary["same_head_duplicate_ci_minutes"] == 10
    pending = first_pass_summary([{**first, "status": "in_progress"}])
    assert pending["first_attempt_pass_rate"] is None


def test_delivery_uses_timeline_and_matching_local_cleanup_evidence(tmp_path: Path) -> None:
    pull = pull_document()
    events = [
        {"event": "auto_merge_enabled", "created_at": "2026-11-01T00:02:00Z"},
        {"event": "merged", "created_at": "2026-11-01T00:20:00Z", "commit_id": "b" * 40},
    ]
    local = {
        "pr": 1,
        "merge_commit": "b" * 40,
        "status": "MERGED",
        "cleanup": "COMPLETE",
        "warnings": [],
        "watch_seconds": 12.0,
        "reconciled_at": "2026-11-01T00:20:30Z",
    }
    record = delivery_record(pull, events, local)
    assert record["auto_merge_enabled_at"] == "2026-11-01T00:02:00Z"
    assert record["enable_delay_seconds"] == 120
    assert record["cleanup_lag_seconds"] == 30
    assert record["agent_watch_seconds"] == 12
    summary = summarize_delivery([record])
    assert summary["auto_merge_coverage"] == 1.0
    assert summary["known_agent_watch_count"] == 1
    assert summary["known_cleanup_count"] == 1
    wrong = delivery_record(pull, events, {**local, "merge_commit": "c" * 40})
    assert wrong["local_evidence"] is False
    assert wrong["cleanup_completed_at"] is None


def test_delivery_unknown_timeline_is_not_a_zero_result(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.delivery_metrics.timeline_events", lambda repository, number: (_ for _ in ()).throw(RuntimeError("403")))
    result = collect_delivery("retroSoC/retroSoC", [pull_document()])
    assert result["summary"]["status"] == "INCOMPLETE"
    assert result["summary"]["auto_merge_coverage"] is None
    assert result["issues"]


def test_cache_metadata_is_optional_but_never_invented(tmp_path: Path) -> None:
    output = tmp_path / "cache.json"
    result = cache_report(
        output,
        ["sources=true"],
        sizes=["sources=1024"],
        durations=["sources=2.5"],
        digests=["sources=" + "a" * 64],
        configs=["sources=" + "b" * 64],
    )
    cache = result["caches"][0]
    assert cache["status"] == "HIT"
    assert cache["bytes"] == 1024
    assert cache["restore_seconds"] == 2.5
    with pytest.raises(ValueError, match="must not be negative"):
        cache_report(output, ["sources=true"], sizes=["sources=-1"])
    with pytest.raises(ValueError, match="without a status observation"):
        cache_report(output, ["sources=true"], durations=["other=1"])


def test_cache_steps_are_exposed_without_inferring_hits(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    job = {
        "id": 10,
        "run_id": 1,
        "run_attempt": 1,
        "head_sha": "a" * 40,
        "status": "completed",
        "conclusion": "success",
        "started_at": "2026-11-01T00:00:00Z",
        "completed_at": "2026-11-01T00:01:00Z",
        "steps": job_document()["jobs"][0]["steps"],
    }
    monkeypatch.setattr("scripts.ci_recovery.gh_json", lambda arguments: job)
    monkeypatch.setattr("scripts.ci_recovery.gh_text", lambda arguments: "successful test\n")
    result = inspect_job(tmp_path, "retroSoC/retroSoC", 10, tmp_path / "inspection.json", execute=False, expected_head="a" * 40)
    assert len(result["cache_steps"]) == 1
    assert result["cache_steps"][0]["duration_seconds"] == 10
    assert result["rerun_decision"]["status"] == "NOT_ELIGIBLE"


def shadow_document() -> dict:
    return {
        "schema_version": 1,
        "base_revision": "a" * 40,
        "source_revision": "a" * 40,
        "event": "pull_request",
        "job_id": "quality-fixtures",
        "decision": "RUN_FULL",
        "mode": "shadow",
        "enabled": False,
        "reason": "no historical evidence was supplied",
        "issues": [],
        "changed_inputs": [],
        "current": {"input_files": ["Makefile"], "fingerprint": "c" * 64},
        "previous": None,
    }


def test_collect_combines_jobs_delivery_and_cache(monkeypatch: pytest.MonkeyPatch) -> None:
    def api(arguments):
        if arguments[0] == "pr":
            if "open" in arguments:
                return []
            return [pull_document()]
        endpoint = arguments[1]
        if endpoint.endswith("actions/runs?per_page=2"):
            return {"workflow_runs": [run_document()]}
        if "actions/runs?branch=main" in endpoint:
            return {"workflow_runs": [run_document()]}
        if endpoint.endswith("actions/runs/1/attempts/1/jobs?per_page=100&page=1"):
            return {**job_document(), "total_count": 1}
        if "issues/1/timeline" in endpoint:
            return [{"event": "auto_merge_enabled", "created_at": "2026-11-01T00:02:00Z"}]
        if endpoint.endswith("actions/runs/1/artifacts?per_page=100"):
            return {
                "total_count": 1,
                "artifacts": [{"id": 20, "name": "quality-incremental-shadow-1-1", "expired": False}],
            }
        raise AssertionError(endpoint)

    monkeypatch.setattr("scripts.engineering_metrics.gh_json", api)
    monkeypatch.setattr("scripts.job_metrics.gh_json", api)
    monkeypatch.setattr("scripts.delivery_metrics.gh_json", api)
    monkeypatch.setattr("scripts.ci_observations.gh_json", api)
    monkeypatch.setattr(
        "scripts.engineering_metrics.policy_observation",
        lambda repository: {"measurement_status": "MEASURED", "evaluation": {"evaluation_only": True}},
    )
    payload = io.BytesIO()
    with zipfile.ZipFile(payload, "w") as archive:
        archive.writestr("shadow.json", json.dumps(shadow_document()))
    monkeypatch.setattr(
        "scripts.ci_observations.artifact_zip",
        lambda repository, artifact_id: (payload.getvalue(), "d" * 64),
    )
    result = collect("retroSoC/retroSoC", 2)
    assert result["data_complete"] is True
    assert result["issues"] == []
    assert result["summary"]["jobs"]["job_count"] == 1
    assert result["summary"]["delivery"]["auto_merge_enabled_count"] == 1
    assert result["summary"]["cache"]["observation_count"] == 1


def test_offline_summary_preserves_all_observation_classes(tmp_path: Path) -> None:
    paths = {
        "runs": {"workflow_runs": [run_document()]},
        "pulls": [pull_document()],
        "jobs": normalize_jobs(run_document(), job_document()),
        "delivery": [delivery_record(pull_document(), [], None)],
        "cache": cache_step_observations(normalize_jobs(run_document(), job_document())),
        "policy": {"schema_version": 1, "evaluation_only": True, "policy_changes": []},
        "shadow": shadow_document(),
    }
    for name, value in paths.items():
        (tmp_path / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    output = tmp_path / "metrics.json"
    completed = subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/engineering_metrics.py"),
            "summarize",
            "--runs",
            str(tmp_path / "runs.json"),
            "--pull-requests",
            str(tmp_path / "pulls.json"),
            "--jobs",
            str(tmp_path / "jobs.json"),
            "--delivery",
            str(tmp_path / "delivery.json"),
            "--cache-observations",
            str(tmp_path / "cache.json"),
            "--delivery-policy",
            str(tmp_path / "policy.json"),
            "--shadow-evidence",
            str(tmp_path / "shadow.json"),
            "--output",
            str(output),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    result = json.loads(output.read_text(encoding="utf-8"))
    assert result["data_complete"] is True
    assert result["summary"]["jobs"]["job_count"] == 1
    assert result["summary"]["delivery"]["record_count"] == 1
    assert result["summary"]["cache"]["observation_count"] == 1
    assert result["observations"]["incremental_shadow"]["decision_counts"] == {"RUN_FULL": 1}


def test_empty_observations_remain_unknown() -> None:
    result = summarize([], [])
    assert result["jobs"]["measurement_status"] == "NOT_MEASURED"
    assert result["delivery"]["auto_merge_coverage"] is None
    assert result["cache"]["hit_rate"] is None
    assert result["first_pass"]["first_attempt_pass_rate"] is None


def test_cache_report_feeds_normalized_summary(tmp_path: Path) -> None:
    report = cache_report(
        tmp_path / "cache.json",
        ["sources=true", "tools=false"],
        sizes=["sources=1024", "tools=2048"],
        durations=["sources=2.5", "tools=3.5"],
        digests=["sources=" + "a" * 64, "tools=" + "a" * 64],
        configs=["sources=" + "b" * 64, "tools=" + "b" * 64],
    )
    result = summarize_cache(report["caches"])
    assert result["hit_rate"] == 0.5
    assert result["restore_seconds_median"] == 3
    assert result["cache_bytes_total"] == 3072
    assert result["cache_digest_recorded_count"] == 2
    assert result["config_digest_recorded_count"] == 2
    assert result["measurement_status"] == "MEASURED"


def test_job_collection_paginates_and_rejects_incomplete_results(monkeypatch: pytest.MonkeyPatch) -> None:
    total_count = 101

    def api(arguments):
        endpoint = arguments[1]
        page = 2 if endpoint.endswith("page=2") else 1
        count = 1 if page == 2 else 100
        return {
            "total_count": total_count,
            "jobs": [
                {"id": page * 1000 + index, "name": f"job-{page}-{index}", "steps": []}
                for index in range(count)
            ],
        }

    monkeypatch.setattr("scripts.job_metrics.gh_json", api)
    result = collect_jobs("retroSoC/retroSoC", [run_document()])
    assert result["issues"] == []
    assert len(result["jobs"]) == 101
    total_count = 102
    result = collect_jobs("retroSoC/retroSoC", [run_document()])
    assert result["incomplete_run_ids"] == [1]
    assert "incomplete" in result["issues"][0]


def test_shadow_observations_bind_identity_and_stay_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    record = shadow_record(shadow_document(), run_document())
    assert record["current"] == {"fingerprint": "c" * 64}
    assert summarize_shadow([record])["decision_counts"] == {"RUN_FULL": 1}
    with pytest.raises(ValueError, match="disabled shadow"):
        shadow_record({**shadow_document(), "enabled": True}, run_document())
    with pytest.raises(ValueError, match="identity differs"):
        shadow_record({**shadow_document(), "source_revision": "b" * 40}, run_document())
    monkeypatch.setattr(
        "scripts.ci_observations.gh_json",
        lambda arguments: {"total_count": 1, "artifacts": [{"id": 20, "name": "other", "expired": False}]},
    )
    result = collect_shadow("retroSoC/retroSoC", [run_document()])
    assert result["measurement_status"] == "PARTIAL"
    assert result["unavailable_run_ids"] == [1]
    assert result["issues"]
