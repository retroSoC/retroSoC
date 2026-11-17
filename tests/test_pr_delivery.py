from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts.flow_control import file_digest
from scripts.pr_delivery import deliver, delivery_evidence, delivery_preflight, enable_delivery, reconcile_delivery

ROOT = Path(__file__).resolve().parents[1]


def pull(state: str = "OPEN") -> dict:
    return {
        "state": state,
        "baseRefName": "dev",
        "headRefName": "ci/example",
        "headRefOid": "a" * 40,
        "headRepository": {"name": "retroSoC"},
        "headRepositoryOwner": {"login": "retroSoC"},
        "mergeCommit": {"oid": "b" * 40},
        "isDraft": False,
    }


def preflight() -> dict:
    return {
        "schema_version": 1,
        "repository": "retroSoC/retroSoC",
        "pr": 248,
        "branch": "ci/example",
        "status": "READY",
        "head_sha": "a" * 40,
        "required_contexts": ["quality-gate"],
        "issues": [],
    }


def metadata() -> dict:
    return {
        "allow_auto_merge": True,
        "allow_merge_commit": True,
        "delete_branch_on_merge": True,
        "permissions": {"push": True},
    }


def test_delivery_preflight_checks_capabilities_before_writes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pr_delivery.gh_json", lambda arguments: metadata())
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull())
    monkeypatch.setattr("scripts.pr_delivery.required_check_contexts", lambda repository, base, root: ["quality-gate"])
    result = delivery_preflight(ROOT, "retroSoC/retroSoC", 248)
    assert result["status"] == "READY"
    assert result["push_capability"] is True
    assert result["required_contexts"] == ["quality-gate"]

    denied = metadata()
    denied["allow_auto_merge"] = False
    denied["permissions"]["push"] = False
    monkeypatch.setattr("scripts.pr_delivery.gh_json", lambda arguments: denied)
    blocked = delivery_preflight(ROOT, "retroSoC/retroSoC", 248)
    assert blocked["status"] == "BLOCKED"
    assert any("allow_auto_merge" in issue for issue in blocked["issues"])
    assert any("push capability" in issue for issue in blocked["issues"])


def test_enable_returns_without_polling_and_rejects_blocked_preflight(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda root, repository, number: preflight())
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: False)
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull())
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda repository, number, root, current: calls.append(number))
    monkeypatch.setattr(
        "scripts.delivery_controller.coordinate", lambda *args, **kwargs: pytest.fail("must not poll")
    )
    result = deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=False)
    assert result["status"] == "AUTO_MERGE_ENABLED"
    assert result["cleanup"] == "PENDING"
    assert calls == [248]

    blocked = enable_delivery(ROOT, "retroSoC/retroSoC", 248, {**preflight(), "status": "BLOCKED"})
    assert blocked["status"] == "BLOCKED"
    assert calls == [248]


def test_watch_enables_auto_merge_before_pending_checks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    open_pull = pull()
    states = iter([open_pull, open_pull, open_pull, pull("MERGED")])
    native = iter([False, True, True])
    reports = iter(
        [
            {"status": "PENDING", "head_sha": "a" * 40, "checks_pending": True},
            {"status": "PASS", "head_sha": "a" * 40},
        ]
    )
    calls = []
    sleeps = []
    checkpoints = []
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda root, repository, number: preflight())
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: next(native))
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: next(native))
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: next(states))
    monkeypatch.setattr("scripts.delivery_controller.view_pr", lambda *args: next(states))
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda repository, number, root, current: calls.append(number))

    def report(*args, **kwargs):
        assert kwargs["allow_empty"] is True
        return next(reports)

    monkeypatch.setattr("scripts.delivery_controller.checks_report", report)
    monkeypatch.setattr(
        "scripts.delivery_controller.reconcile_delivery",
        lambda *args, **kwargs: {"status": "MERGED", "cleanup": "COMPLETE", "warnings": []},
    )
    monkeypatch.setattr("scripts.delivery_controller.time.sleep", sleeps.append)
    from types import SimpleNamespace

    clock = iter([100.0, 123.0])
    monkeypatch.setattr("scripts.pr_delivery.time", SimpleNamespace(monotonic=lambda: next(clock)))
    result = deliver(
        ROOT,
        "retroSoC/retroSoC",
        248,
        60,
        watch=True,
        checkpoint=checkpoints.append,
        delivery_dir=tmp_path,
    )
    assert result["status"] == "MERGED"
    assert result["cleanup"] == "COMPLETE"
    assert result["coordinator_summary"] == str(tmp_path / "pr-248-controller.json")
    assert result["watch_seconds"] == 23.0
    assert (tmp_path / "pr-248-controller.json").is_file()
    assert calls == [248]
    assert sleeps == [60, 60]
    assert [item["status"] for item in checkpoints] == ["AUTO_MERGE_ENABLED", "MERGED"]


def test_failed_checks_and_disabled_native_auto_merge_stop_watch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda root, repository, number: preflight())
    native = iter([False, True])
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: next(native))
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: next(native))
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull())
    monkeypatch.setattr("scripts.delivery_controller.view_pr", lambda *args: pull())
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda repository, number, root, current: None)
    monkeypatch.setattr(
        "scripts.delivery_controller.checks_report",
        lambda *args, **kwargs: {"status": "FAIL", "head_sha": "a" * 40},
    )
    with pytest.raises(RuntimeError, match="checks failed"):
        deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True, delivery_dir=tmp_path)
    assert '"status": "FAILED"' in (tmp_path / "pr-248-delivery.json").read_text(encoding="utf-8")

    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: True)
    monkeypatch.setattr("scripts.delivery_controller.native_auto_merge_enabled", lambda *args: False)
    monkeypatch.setattr(
        "scripts.delivery_controller.checks_report",
        lambda *args, **kwargs: pytest.fail("must not poll when native auto-merge is disabled"),
    )
    with pytest.raises(RuntimeError, match="auto-merge was disabled"):
        deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True, delivery_dir=tmp_path)


def test_watch_requires_a_checkpoint_directory_before_enabling(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "scripts.pr_delivery.delivery_preflight",
        lambda *args: pytest.fail("invalid watcher configuration must not enable auto-merge"),
    )
    with pytest.raises(ValueError, match="checkpoint directory"):
        deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True)


def test_head_change_between_preflight_and_enable_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: False)
    changed = pull()
    changed["headRefOid"] = "c" * 40
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: changed)
    with pytest.raises(RuntimeError, match="head changed"):
        enable_delivery(ROOT, "retroSoC/retroSoC", 248, preflight())


def test_main_preserves_canonical_checkpoint_with_custom_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from scripts import pr_delivery

    output = tmp_path / "custom-result.json"
    calls = []
    monkeypatch.setattr(
        pr_delivery.sys,
        "argv",
        ["pr_delivery.py", "--root", str(ROOT), "--pr", "248", "--watch", "--output", str(output)],
    )

    def start(*args, **kwargs):
        calls.append(kwargs)
        document = {"schema_version": 1, "pr": 248, "status": "AUTO_MERGE_ENABLED"}
        kwargs["checkpoint"](document)
        return document

    monkeypatch.setattr(pr_delivery, "deliver", start)

    assert pr_delivery.main() == 0
    assert calls[0]["delivery_dir"] == tmp_path
    assert calls[0]["coordinator_output"] == tmp_path / "pr-248-controller.json"
    assert (tmp_path / "pr-248-delivery.json").is_file()
    assert output.is_file()


def write_evidence(root: Path, preserved: bool = True) -> Path:
    branch = "ci/example"
    artifact_dir = root / "build/agent-artifacts/example"
    retained = []
    if preserved:
        result = artifact_dir / "tasks/example/result.json"
        result.parent.mkdir(parents=True, exist_ok=True)
        result.write_text('{"status":"passed"}\n', encoding="utf-8")
        retained.append({"path": "tasks/example/result.json", "sha256": file_digest(result)})
        manifest = {
            "schema_version": 1,
            "status": "PRESERVED",
            "artifact_identity": {"task_id": "example", "branch": branch, "source_revision": "a" * 40},
            "destination": str(artifact_dir),
            "retained_files": retained,
        }
        (artifact_dir / "artifact-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    action = {
        "path": str(root / "build/agent-worktrees/example"),
        "branch": branch,
        "status": "CLEANED",
    }
    if preserved:
        action["preserved_artifacts"] = str(artifact_dir)
    registry = root / "build/agent-worktrees/ci-example-cleanup.json"
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry.write_text(json.dumps({"schema_version": 1, "actions": [action]}), encoding="utf-8")
    return registry


def mock_merged_environment(monkeypatch: pytest.MonkeyPatch, root: Path) -> None:
    monkeypatch.setattr("scripts.pr_delivery.auto_merge_policy", lambda root: None)
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull("MERGED"))
    monkeypatch.setattr("scripts.pr_delivery.cleanup_merged_branch", lambda *args, **kwargs: [])
    monkeypatch.setattr("scripts.pr_delivery.worktree_main_root", lambda root: root)


def test_reconcile_links_verified_cleanup_and_artifact_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    mock_merged_environment(monkeypatch, tmp_path)

    result = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)

    assert result["status"] == "MERGED"
    assert result["evidence_status"] == "READY"
    assert result["cleanup_registry"] == "build/agent-worktrees/ci-example-cleanup.json"
    assert result["evidence_manifest"] == "build/agent-artifacts/example/artifact-manifest.json"
    assert result["merge_commit"] == "b" * 40


def test_reconcile_distinguishes_missing_registry_and_empty_artifact_inventory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    mock_merged_environment(monkeypatch, tmp_path)
    missing = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)
    assert missing["evidence_status"] == "NOT_AVAILABLE"
    assert missing["evidence_manifest"] is None
    assert missing["cleanup_registry"] is None

    write_evidence(tmp_path, preserved=False)
    empty = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)
    assert empty["evidence_status"] == "NOT_AVAILABLE"
    assert empty["evidence_manifest"] is None
    assert empty["cleanup_registry"] == "build/agent-worktrees/ci-example-cleanup.json"


def test_delivery_evidence_rejects_identity_mismatch_and_tampered_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    monkeypatch.setattr("scripts.pr_delivery.worktree_main_root", lambda root: root)
    manifest_path = tmp_path / "build/agent-artifacts/example/artifact-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["artifact_identity"]["source_revision"] = "c" * 40
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="identity"):
        delivery_evidence(tmp_path, pull("MERGED"))

    manifest["artifact_identity"]["source_revision"] = "a" * 40
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    retained = tmp_path / "build/agent-artifacts/example/tasks/example/result.json"
    retained.write_text("tampered\n", encoding="utf-8")
    with pytest.raises(ValueError, match="digest mismatch"):
        delivery_evidence(tmp_path, pull("MERGED"))


def test_cleanup_opt_out_and_warnings_do_not_claim_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    monkeypatch.setattr("scripts.pr_delivery.auto_merge_policy", lambda root: None)
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull("MERGED"))
    monkeypatch.setattr("scripts.pr_delivery.delivery_evidence", lambda *args: pytest.fail("must not claim evidence"))

    skipped = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=False, delete_remote=True)
    assert skipped["evidence_status"] == "NOT_REQUESTED"
    assert skipped["evidence_manifest"] is None

    monkeypatch.setattr("scripts.pr_delivery.cleanup_merged_branch", lambda *args, **kwargs: ["dirty worktree"])
    warning = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)
    assert warning["status"] == "MERGED_WITH_WARNINGS"
    assert warning["evidence_status"] == "NOT_AVAILABLE"
    assert warning["evidence_manifest"] is None
