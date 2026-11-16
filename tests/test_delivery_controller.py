from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.delivery_controller import coordinate, coordinate_once, record_path

ROOT = Path(__file__).resolve().parents[1]


def delivery_record(status: str = "AUTO_MERGE_ENABLED") -> dict:
    return {
        "schema_version": 1,
        "repository": "retroSoC/retroSoC",
        "pr": 1,
        "branch": "ci/example",
        "head_sha": "a" * 40,
        "required_contexts": ["quality-gate"],
        "auto_merge": True,
        "status": status,
        "cleanup": "PENDING",
        "warnings": [],
    }


def write_record(directory: Path, document: dict) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = record_path(directory, 1)
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def pull(state: str, head: str = "a" * 40) -> dict:
    return {
        "state": state,
        "headRefName": "ci/example",
        "headRefOid": head,
    }


def test_coordinator_resumes_pending_native_delivery_and_cleanup(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    directory = tmp_path / "delivery"
    path = write_record(directory, delivery_record())
    states = iter([pull("OPEN"), pull("OPEN"), pull("MERGED")])
    reports = iter(
        [
            {"status": "PENDING", "head_sha": "a" * 40},
            {"status": "PASS", "head_sha": "a" * 40},
        ]
    )
    reconciliations = []
    sleeps = []
    monkeypatch.setattr("scripts.delivery_controller.view_pr", lambda repository, number, root: next(states))
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: True)
    monkeypatch.setattr("scripts.delivery_controller.checks_report", lambda *args, **kwargs: next(reports))

    def reconcile(root, repository, number, cleanup, delete_remote):
        reconciliations.append(number)
        return {
            "status": "MERGED",
            "cleanup": "COMPLETE",
            "warnings": [],
            "merge_commit": "b" * 40,
            "reconciled_at": "2026-11-01T00:00:00Z",
        }

    monkeypatch.setattr("scripts.delivery_controller.reconcile_delivery", reconcile)
    monkeypatch.setattr("scripts.delivery_controller.time.sleep", sleeps.append)
    result = coordinate(ROOT, "retroSoC/retroSoC", [1], directory, 1, True, tmp_path / "summary.json")
    assert result["status"] == "COMPLETE"
    assert reconciliations == [1]
    assert sleeps == [1, 1]
    saved = json.loads(path.read_text(encoding="utf-8"))
    assert saved["status"] == "MERGED"
    assert saved["merge_commit"] == "b" * 40
    assert saved["controller_reconciliations"] == 1


def test_completed_record_is_a_read_only_noop(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    directory = tmp_path / "delivery"
    document = delivery_record("MERGED")
    document.update(cleanup="COMPLETE", merge_commit="b" * 40)
    path = write_record(directory, document)
    before = path.read_bytes()
    monkeypatch.setattr(
        "scripts.delivery_controller.view_pr",
        lambda *args: pytest.fail("completed record must not require a network call"),
    )
    result = coordinate_once(ROOT, "retroSoC/retroSoC", [1], directory)
    assert result["status"] == "COMPLETE"
    assert result["records"][0]["action"] == "ALREADY_RECONCILED"
    assert path.read_bytes() == before


def test_disabled_auto_merge_and_failed_checks_stop_without_cleanup(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    directory = tmp_path / "delivery"
    path = write_record(directory, delivery_record())
    monkeypatch.setattr("scripts.delivery_controller.view_pr", lambda *args: pull("OPEN"))
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: False)
    monkeypatch.setattr(
        "scripts.delivery_controller.checks_report",
        lambda *args, **kwargs: pytest.fail("must not poll when native auto-merge is disabled"),
    )
    monkeypatch.setattr(
        "scripts.delivery_controller.reconcile_delivery",
        lambda *args, **kwargs: pytest.fail("must not clean an open PR"),
    )
    result = coordinate_once(ROOT, "retroSoC/retroSoC", [1], directory)
    assert result["status"] == "ATTENTION"
    assert json.loads(path.read_text(encoding="utf-8"))["status"] == "ATTENTION"

    write_record(directory, delivery_record())
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: True)
    monkeypatch.setattr(
        "scripts.delivery_controller.checks_report",
        lambda *args, **kwargs: {"status": "FAIL", "head_sha": "a" * 40},
    )
    result = coordinate_once(ROOT, "retroSoC/retroSoC", [1], directory)
    assert result["status"] == "FAILED"
    assert json.loads(path.read_text(encoding="utf-8"))["status"] == "FAILED"


def test_head_change_and_missing_records_preserve_original_identity(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    directory = tmp_path / "delivery"
    path = write_record(directory, delivery_record())
    monkeypatch.setattr("scripts.delivery_controller.view_pr", lambda *args: pull("OPEN", "b" * 40))
    result = coordinate_once(ROOT, "retroSoC/retroSoC", [1], directory)
    assert result["status"] == "ATTENTION"
    saved = json.loads(path.read_text(encoding="utf-8"))
    assert saved["head_sha"] == "a" * 40
    assert "differs from its delivery record" in saved["controller_issues"][0]

    with pytest.raises(ValueError, match="unique positive"):
        coordinate(ROOT, "retroSoC/retroSoC", [1, 1], directory, 1, False, tmp_path / "invalid.json")


def test_make_forwards_only_explicit_prs() -> None:
    completed = subprocess.run(
        [
            "make",
            "--no-print-directory",
            "-n",
            "-C",
            str(ROOT),
            "agent-coordinate",
            "PRS=1 2",
            "WATCH=1",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0
    assert "--pr 1 --pr 2" in completed.stdout
    assert "--watch" in completed.stdout
