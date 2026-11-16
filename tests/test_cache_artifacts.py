from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import pytest

from scripts.cache_artifacts import cache_metadata, cache_records, collect_cache_artifacts

ROOT = Path(__file__).resolve().parents[1]


def run_document() -> dict:
    return {
        "id": 1,
        "name": "regression-ics55",
        "event": "pull_request",
        "status": "completed",
        "conclusion": "success",
        "head_sha": "a" * 40,
        "run_attempt": 1,
    }


def payload(entries: list[dict], path: str = "ci-summary/cache.json") -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr(path, json.dumps({"schema_version": 1, "caches": entries}))
    return output.getvalue()


def artifact() -> dict:
    return {
        "id": 20,
        "name": "pr-regression-1-1-MINI",
        "expired": False,
        "size_in_bytes": 1234,
    }


def test_collect_reads_real_zip_structure_and_preserves_unknown_sizes(monkeypatch: pytest.MonkeyPatch) -> None:
    entries = [
        {"name": "sources", "status": "HIT"},
        {"name": "toolchains", "status": "HIT", "restore_seconds": 2.5},
        {"name": "ccache", "status": "NOT_RUN"},
    ]
    content = payload(entries)
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: {"total_count": 1, "artifacts": [artifact()]},
    )
    monkeypatch.setattr("scripts.cache_artifacts.artifact_zip", lambda repository, artifact_id: (content, "d" * 64))
    result = collect_cache_artifacts("retroSoC/retroSoC", [run_document()])
    assert result["measurement_status"] == "MEASURED"
    assert result["issues"] == []
    assert result["artifact_count"] == 1
    assert result["observation_count"] == 3
    assert result["summary"]["hit_count"] == 2
    assert result["summary"]["not_run_count"] == 1
    assert result["summary"]["hit_rate"] == 1.0
    assert result["summary"]["cache_bytes_total"] is None
    record = result["observations"][0]
    assert record["run_id"] == 1
    assert record["head_sha"] == "a" * 40
    assert record["artifact_id"] == 20
    assert record["artifact_sha256"] == "d" * 64
    assert record["artifact_bytes"] == 1234
    assert record["bytes"] is None
    assert result["observations"][1]["restore_seconds"] == 2.5


def test_unique_cache_key_supplies_actual_github_cache_size(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: {"caches": [{"id": 99, "key": "sources-key", "size_in_bytes": 4096}]},
    )
    records = cache_records(
        "retroSoC/retroSoC",
        run_document(),
        artifact(),
        payload([{"name": "sources", "status": "HIT", "key": "sources-key"}]),
        "d" * 64,
    )
    assert records[0]["bytes"] == 4096
    assert records[0]["cache_id"] == 99
    assert records[0]["metadata_status"] == "MEASURED"


def test_missing_or_ambiguous_cache_metadata_stays_unknown(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: {"caches": [{"id": 1, "key": "key", "size_in_bytes": 10}, {"id": 2, "key": "key", "size_in_bytes": 20}]},
    )
    result = cache_metadata("retroSoC/retroSoC", "key")
    assert result["bytes"] is None
    assert result["metadata_status"] == "AMBIGUOUS"
    assert cache_metadata("retroSoC/retroSoC", None)["bytes"] is None


def test_invalid_or_duplicate_cache_entries_fail_the_run(monkeypatch: pytest.MonkeyPatch) -> None:
    content = payload([{"name": "sources", "status": "HIT"}, {"name": "sources", "status": "MISS"}])
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: {"total_count": 1, "artifacts": [artifact()]},
    )
    monkeypatch.setattr("scripts.cache_artifacts.artifact_zip", lambda repository, artifact_id: (content, "d" * 64))
    result = collect_cache_artifacts("retroSoC/retroSoC", [run_document()])
    assert result["measurement_status"] == "PARTIAL"
    assert result["unavailable_run_ids"] == [1]
    assert result["observations"] == []
    assert "duplicate" in result["issues"][0]


def test_cache_report_rejects_unsafe_zip_path() -> None:
    with pytest.raises(ValueError, match="unsafe"):
        cache_records(
            "retroSoC/retroSoC",
            run_document(),
            artifact(),
            payload([{"name": "sources", "status": "HIT"}], "../cache.json"),
            "d" * 64,
        )


def test_unrelated_artifacts_do_not_create_cache_observations(monkeypatch: pytest.MonkeyPatch) -> None:
    unrelated = {**artifact(), "name": "quality-incremental-shadow-1-1"}
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: {"total_count": 1, "artifacts": [unrelated]},
    )
    result = collect_cache_artifacts("retroSoC/retroSoC", [run_document()])
    assert result["measurement_status"] == "NOT_MEASURED"
    assert result["observations"] == []
    assert result["issues"] == []


def test_fallback_restore_measures_the_matched_key_not_the_primary_key(monkeypatch: pytest.MonkeyPatch) -> None:
    queries = []

    def metadata(arguments):
        queries.append(arguments[-1])
        return {"caches": [{"id": 100, "key": "fallback-key", "size_in_bytes": 8192}]}

    monkeypatch.setattr("scripts.cache_artifacts.gh_json", metadata)
    records = cache_records(
        "retroSoC/retroSoC",
        run_document(),
        artifact(),
        payload([{"name": "ccache", "status": "MISS", "key": "primary-key", "matched_key": "fallback-key"}]),
        "d" * 64,
    )

    assert queries == ["repos/retroSoC/retroSoC/actions/caches?key=fallback-key"]
    assert records[0]["key"] == "primary-key"
    assert records[0]["matched_key"] == "fallback-key"
    assert records[0]["metadata_key"] == "fallback-key"
    assert records[0]["cache_id"] == 100
    assert records[0]["bytes"] == 8192
    assert records[0]["metadata_status"] == "MEASURED"


def test_primary_miss_without_a_match_has_no_size_or_invented_lookup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "scripts.cache_artifacts.gh_json",
        lambda arguments: pytest.fail("a miss without a restored key must not query primary-key size"),
    )
    records = cache_records(
        "retroSoC/retroSoC",
        run_document(),
        artifact(),
        payload([{"name": "ccache", "status": "MISS", "key": "primary-key"}]),
        "d" * 64,
    )

    assert records[0]["key"] == "primary-key"
    assert records[0]["matched_key"] is None
    assert records[0]["metadata_key"] is None
    assert records[0]["bytes"] is None
    assert records[0]["metadata_status"] == "NOT_MEASURED"


def test_cache_summary_separates_restored_and_unique_cache_bytes() -> None:
    from scripts.job_metrics import summarize_cache

    observations = [
        {"hit_status": "HIT", "cache_id": 1, "bytes": 100},
        {"hit_status": "HIT", "cache_id": 1, "bytes": 100},
        {"hit_status": "MISS", "cache_id": 2, "bytes": 50},
        {"hit_status": "MISS", "cache_id": None, "bytes": None},
    ]
    result = summarize_cache(observations)
    assert result["cache_bytes_total"] == 250
    assert result["restored_bytes_total"] == 250
    assert result["unique_cache_entry_count"] == 2
    assert result["unique_cache_bytes_total"] == 150

    with pytest.raises(ValueError, match="size differs"):
        summarize_cache(
            [
                {"hit_status": "HIT", "cache_id": 1, "bytes": 100},
                {"hit_status": "HIT", "cache_id": 1, "bytes": 101},
            ]
        )
