from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.ci_recovery import (
    cache_report,
    classify_failure,
    gh_text,
    inspect_job,
    normalize_log_text,
    rerun_decision,
)


@pytest.mark.parametrize(
    ("conclusion", "text", "category", "retryable"),
    [
        ("failure", "Failed to connect to github.com", "infrastructure_failure", True),
        ("failure", "Traceback (most recent call last)\nGnuTLS recv error", "infrastructure_failure", True),
        ("failure", "Traceback (most recent call last)\nsudo apt-get -o DPkg::Lock::Timeout=120 update", "source_or_test_failure", False),
        ("failure", "Could not get lock /var/lib/dpkg/lock", "infrastructure_failure", True),
        ("failure", "1 failed, 2 passed", "source_or_test_failure", False),
        ("failure", "AssertionError: mismatch", "source_or_test_failure", False),
        ("failure", "THESE PACKAGES DO NOT MATCH THE HASHES", "dependency_integrity_failure", False),
        ("failure", "flow exceeded its 600-second deadline", "timeout", False),
        ("cancelled", "Failed to connect", "cancelled", False),
        ("failure", "unrecognized diagnostic", "unknown_failure", False),
        ("success", "no failures", "success", False),
    ],
)
def test_failure_classification_controls_retry(conclusion: str, text: str, category: str, retryable: bool) -> None:
    result = classify_failure(conclusion, text)
    assert result["category"] == category
    assert result["retryable"] is retryable
    assert len(result["evidence_sha256"]) == 64


def job() -> dict:
    return {
        "id": 10,
        "run_id": 20,
        "head_sha": "a" * 40,
        "status": "completed",
        "conclusion": "failure",
        "run_attempt": 1,
        "name": "regression",
        "started_at": "2026-11-01T00:00:00Z",
        "completed_at": "2026-11-01T00:01:00Z",
        "steps": [
            {
                "number": 1,
                "name": "Run regression",
                "status": "completed",
                "conclusion": "failure",
                "started_at": "2026-11-01T00:00:00Z",
                "completed_at": "2026-11-01T00:01:00Z",
            }
        ],
    }


def test_only_first_matching_infrastructure_failure_is_eligible() -> None:
    classification = classify_failure("failure", "Connection timed out")
    eligible = rerun_decision(job(), classification, "a" * 40)
    assert eligible["status"] == "ELIGIBLE"
    assert eligible["action"] == "rerun"

    repeated = job()
    repeated["run_attempt"] = 2
    assert rerun_decision(repeated, classification)["status"] == "NOT_ELIGIBLE"
    assert rerun_decision(job(), classification, "b" * 40)["status"] == "NOT_ELIGIBLE"
    source = classify_failure("failure", "1 failed")
    assert rerun_decision(job(), source)["status"] == "NOT_ELIGIBLE"
    pending = job()
    pending["status"] = "in_progress"
    assert rerun_decision(pending, classification)["reason"] == "job is not complete"


def test_inspect_is_dry_run_by_default_and_execute_is_bounded(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []
    monkeypatch.setattr("scripts.ci_recovery.gh_json", lambda arguments: job())
    monkeypatch.setattr(
        "scripts.ci_recovery.gh_text",
        lambda arguments: "Failed to connect\nMaximum resident set size (kbytes): 1024\nUser time (seconds): 2.5\n",
    )
    monkeypatch.setattr(
        "scripts.ci_recovery.gh_json",
        lambda arguments: calls.append(arguments) if "--method" in arguments else job(),
    )
    output = tmp_path / "inspection.json"
    report = inspect_job(tmp_path, "retroSoC/retroSoC", 10, output, execute=False, expected_head="a" * 40)
    assert report["execution_mode"] == "dry-run"
    assert report["rerun_decision"]["status"] == "ELIGIBLE"
    assert report["resources"]["peak_rss_kib"] == 1024
    assert report["duration_seconds"] == 60
    assert report["steps"][0]["duration_seconds"] == 60
    assert calls == []
    assert Path(report["log"]).is_file()

    report = inspect_job(tmp_path, "retroSoC/retroSoC", 10, output, execute=True, expected_head="a" * 40)
    assert report["rerun_decision"]["status"] == "RERUN_REQUESTED"
    assert len(calls) == 1
    assert calls[0][-1] == "repos/retroSoC/retroSoC/actions/jobs/10/rerun"


def test_cache_report_preserves_missing_and_invalid_states(tmp_path: Path) -> None:
    output = tmp_path / "cache.json"
    report = cache_report(output, ["sources=true", "tools=false", "ccache="])
    assert [item["status"] for item in report["caches"]] == ["HIT", "MISS", "NOT_RUN"]
    assert json.loads(output.read_text(encoding="utf-8"))["schema_version"] == 1
    with pytest.raises(ValueError, match="invalid cache hit state"):
        cache_report(output, ["tools=unknown"])
    with pytest.raises(ValueError, match="invalid cache observation"):
        cache_report(output, ["tools"])


def test_cache_report_binds_optional_keys_without_inventing_values(tmp_path: Path) -> None:
    report = cache_report(
        tmp_path / "cache.json",
        ["sources=true", "tools=false", "ccache="],
        keys=["sources=sources-key", "tools=", "ccache="],
    )
    assert report["caches"][0]["key"] == "sources-key"
    assert report["caches"][1]["key"] is None
    assert report["caches"][2]["key"] is None
    with pytest.raises(ValueError, match="without a status observation"):
        cache_report(tmp_path / "cache.json", ["sources=true"], keys=["other=key"])


def test_log_normalization_removes_ansi_and_replaces_other_controls() -> None:
    raw = "\x1b[36;1mFailed to connect\x1b[0m\x00\n"
    normalized = normalize_log_text(raw)
    assert normalized == "Failed to connect\ufffd\n"
    assert classify_failure("failure", normalized)["category"] == "infrastructure_failure"


def test_gh_log_download_allows_terminal_escape_sequences(monkeypatch: pytest.MonkeyPatch) -> None:
    commands = []

    def execute(command, **kwargs):
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="log\n", stderr="")

    monkeypatch.setattr(subprocess, "run", execute)
    assert gh_text(["api", "repos/retroSoC/retroSoC/actions/jobs/10/logs"]) == "log\n"
    assert commands[0][2] == "--allow-escape-sequences"


def test_inspect_preserves_raw_and_normalized_logs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    raw = "\x1b[31mFailed to connect\x1b[0m\x00\nMaximum resident set size (kbytes): 1024\n"
    monkeypatch.setattr("scripts.ci_recovery.gh_json", lambda arguments: job())
    monkeypatch.setattr("scripts.ci_recovery.gh_text", lambda arguments: raw)
    report = inspect_job(
        tmp_path,
        "retroSoC/retroSoC",
        10,
        tmp_path / "inspection.json",
        execute=False,
        expected_head="a" * 40,
    )
    assert Path(report["raw_log"]).read_text(encoding="utf-8") == raw
    normalized = Path(report["log"]).read_text(encoding="utf-8")
    assert "\x1b" not in normalized and "\x00" not in normalized
    assert "Failed to connect\ufffd" in normalized
    assert len(report["raw_log_sha256"]) == 64
    assert len(report["log_sha256"]) == 64
    assert report["classification"]["category"] == "infrastructure_failure"
    assert report["rerun_decision"]["status"] == "ELIGIBLE"
