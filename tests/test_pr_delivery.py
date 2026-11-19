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
    monkeypatch.setattr(
        "scripts.pr_delivery.merged_check_evidence",
        lambda root, repository, number, expected_head: {
            "status": "PASS",
            "head_sha": expected_head,
            "issues": [],
        },
    )


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


def test_reconcile_emits_merge_matched_friction_observation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    mock_merged_environment(monkeypatch, tmp_path)

    result = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)

    assert result["friction_observation"] == "build/engineering/pr-248-friction.json"
    output = tmp_path / result["friction_observation"]
    document = json.loads(output.read_text(encoding="utf-8"))
    assert document["status"] == "OBSERVED"
    assert document["pr"] == 248
    assert document["merge_commit"] == "b" * 40
    assert document["source_revision"] == "a" * 40
    assert document["timeline_status"] == "NOT_REQUESTED"
    assert document["hardware_execution"] == "NOT_RUN"
    assert document["friction"]["final_check_status"] == "PASS"
    assert document["friction"]["recovery_transition_count"] == 0
    assert document["local_friction"]["record_count"] == 1
    assert document["local_friction"]["final_check_status_counts"] == {"PASS": 1}
    assert document["local_friction"]["evidence_status_counts"] == {"READY": 1}


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
    monkeypatch.setattr("scripts.pr_delivery.worktree_main_root", lambda root: root)
    monkeypatch.setattr("scripts.pr_delivery.delivery_evidence", lambda *args: pytest.fail("must not claim evidence"))
    monkeypatch.setattr(
        "scripts.pr_delivery.merged_check_evidence",
        lambda root, repository, number, expected_head: {
            "status": "PASS",
            "head_sha": expected_head,
            "issues": [],
        },
    )

    skipped = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=False, delete_remote=True)
    assert skipped["evidence_status"] == "NOT_REQUESTED"
    assert skipped["evidence_manifest"] is None

    monkeypatch.setattr("scripts.pr_delivery.cleanup_merged_branch", lambda *args, **kwargs: ["dirty worktree"])
    warning = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)
    assert warning["status"] == "MERGED_WITH_WARNINGS"
    assert warning["evidence_status"] == "NOT_AVAILABLE"
    assert warning["evidence_manifest"] is None


def test_resume_requires_changed_head_and_audited_reason() -> None:
    from scripts.pr_delivery import resume_recovery

    previous = {
        **preflight(),
        "base": "dev",
        "auto_merge": True,
        "status": "FAILED",
        "checked_at": "2026-11-17T00:00:00Z",
        "last_check_status": "FAIL",
    }
    current = {**preflight(), "base": "dev", "head_sha": "c" * 40}
    with pytest.raises(ValueError, match="non-empty recovery reason"):
        resume_recovery(previous, current, " ")
    with pytest.raises(ValueError, match="changed HEAD"):
        resume_recovery(previous, {**current, "head_sha": "a" * 40}, "Same-head retry")
    with pytest.raises(ValueError, match="branch differs"):
        resume_recovery({**previous, "branch": "ci/other"}, current, "Unexpected branch change")
    with pytest.raises(ValueError, match="FAILED or ATTENTION"):
        resume_recovery({**previous, "status": "MERGED"}, current, "Already merged")
    with pytest.raises(ValueError, match="originally enabled"):
        resume_recovery({**previous, "auto_merge": False}, current, "Missing original delivery")

    recovery = resume_recovery(previous, current, "Merged dev after correcting reviewed control evidence")
    assert recovery["from_status"] == "FAILED"
    assert recovery["to_status"] == "READY"
    assert recovery["previous_head_sha"] == "a" * 40
    assert recovery["previous_checked_at"] == "2026-11-17T00:00:00Z"
    assert recovery["previous_last_check_status"] == "FAIL"
    assert recovery["reason"] == "Merged dev after correcting reviewed control evidence"


def test_resume_never_reenables_external_auto_merge_disable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda *args: False)
    monkeypatch.setattr(
        "scripts.pr_delivery.merge_pr",
        lambda *args: pytest.fail("resume must not re-enable externally disabled auto-merge"),
    )
    with pytest.raises(RuntimeError, match="remain enabled"):
        enable_delivery(ROOT, "retroSoC/retroSoC", 248, preflight(), require_existing_auto_merge=True)


def test_resume_delivery_retains_previous_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    previous = {
        **preflight(),
        "base": "dev",
        "auto_merge": True,
        "status": "FAILED",
        "last_check_status": "FAIL",
    }
    (tmp_path / "pr-248-delivery.json").write_text(json.dumps(previous), encoding="utf-8")
    current = {**preflight(), "base": "dev", "head_sha": "c" * 40}
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda *args: current)
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda *args: True)
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda *args: pytest.fail("must not merge during resume"))

    result = deliver(
        ROOT,
        "retroSoC/retroSoC",
        248,
        60,
        watch=False,
        delivery_dir=tmp_path,
        resume=True,
        resume_reason="Base synchronization created a new reviewed HEAD",
    )

    assert result["status"] == "AUTO_MERGE_ALREADY_ENABLED"
    assert result["recovery"]["from_status"] == "FAILED"
    assert result["recovery"]["previous_head_sha"] == "a" * 40
    assert result["recovery"]["previous_last_check_status"] == "FAIL"
    assert result["recovery_history"] == [result["recovery"]]
    assert result["recovery_history_dropped_count"] == 0


def test_recovery_history_preserves_legacy_and_caps_retention() -> None:
    from scripts.pr_delivery import extend_recovery_history

    legacy = {"from_status": "ATTENTION", "previous_head_sha": "c" * 40}
    current = {"from_status": "FAILED", "previous_head_sha": "a" * 40}
    history, dropped = extend_recovery_history({"recovery": legacy}, current)
    assert history == [legacy, current]
    assert dropped == 0

    existing = [{"sequence": index} for index in range(20)]
    history, dropped = extend_recovery_history(
        {"recovery_history": existing, "recovery_history_dropped_count": 3},
        current,
    )
    assert len(history) == 20
    assert history[0]["sequence"] == 1
    assert history[-1] == current
    assert dropped == 4


def test_merged_check_evidence_binds_exact_head_and_preserves_pending(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.pr_delivery import merged_check_evidence

    report = {"status": "PASS", "head_sha": "a" * 40, "contexts": [{"name": "quality-gate"}]}
    monkeypatch.setattr("scripts.pr_delivery.required_check_contexts", lambda *args: ["quality-gate"])
    monkeypatch.setattr("scripts.pr_delivery.checks_report", lambda *args, **kwargs: report)

    passed = merged_check_evidence(ROOT, "retroSoC/retroSoC", 248, "a" * 40)
    assert passed["status"] == "PASS"
    assert passed["required_contexts"] == ["quality-gate"]
    assert passed["report"] == report

    report["status"] = "PENDING"
    pending = merged_check_evidence(ROOT, "retroSoC/retroSoC", 248, "a" * 40)
    assert pending["status"] == "PENDING"
    assert pending["issues"] == []

    report["head_sha"] = "b" * 40
    mismatch = merged_check_evidence(ROOT, "retroSoC/retroSoC", 248, "a" * 40)
    assert mismatch["status"] == "NOT_AVAILABLE"
    assert mismatch["issues"] == ["merged-head check report differs from the merged PR HEAD"]


def test_reconcile_separates_final_check_warning_from_cleanup(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    mock_merged_environment(monkeypatch, tmp_path)
    monkeypatch.setattr(
        "scripts.pr_delivery.merged_check_evidence",
        lambda root, repository, number, expected_head: {
            "status": "FAIL",
            "head_sha": expected_head,
            "issues": [],
        },
    )

    result = reconcile_delivery(tmp_path, "retroSoC/retroSoC", 248, cleanup=True, delete_remote=True)

    assert result["status"] == "MERGED_WITH_WARNINGS"
    assert result["cleanup"] == "COMPLETE"
    assert result["evidence_status"] == "READY"
    assert result["final_checks"]["status"] == "FAIL"
    assert result["warnings"] == ["merged-head final checks are FAIL"]


def test_resume_cli_rejects_missing_reason_and_incompatible_modes(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts import pr_delivery as cli

    monkeypatch.setattr(cli.sys, "argv", ["pr_delivery.py", "--pr", "248", "--resume"])
    assert cli.main() == 2
    monkeypatch.setattr(
        cli.sys,
        "argv",
        ["pr_delivery.py", "--pr", "248", "--resume", "--resume-reason", "diagnosed", "--preflight-only"],
    )
    assert cli.main() == 2
    monkeypatch.setattr(cli.sys, "argv", ["pr_delivery.py", "--pr", "248", "--resume-reason", "diagnosed"])
    assert cli.main() == 2


def test_reconcile_preserves_recovery_context_before_friction_emission(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_evidence(tmp_path)
    mock_merged_environment(monkeypatch, tmp_path)
    recovery = {"from_status": "ATTENTION", "previous_head_sha": "c" * 40}
    local = {
        "schema_version": 1,
        "repository": "retroSoC/retroSoC",
        "pr": 248,
        "branch": "ci/example",
        "head_sha": "a" * 40,
        "recovery": recovery,
        "recovery_history": [recovery],
        "recovery_history_dropped_count": 0,
    }

    result = reconcile_delivery(
        tmp_path,
        "retroSoC/retroSoC",
        248,
        cleanup=True,
        delete_remote=True,
        local_record=local,
    )

    assert result["recovery"] == recovery
    assert result["recovery_history"] == [recovery]
    document = json.loads((tmp_path / result["friction_observation"]).read_text(encoding="utf-8"))
    assert document["friction"]["recovery_recorded"] is True
    assert document["friction"]["recovery_from_status"] == "ATTENTION"
    assert document["friction"]["recovery_transition_count"] == 1
    assert document["local_friction"]["records_with_recovery"] == 1
    assert document["local_friction"]["recovery_transition_count"] == 1
    with pytest.raises(ValueError, match="recovery context HEAD"):
        reconcile_delivery(
            tmp_path,
            "retroSoC/retroSoC",
            248,
            cleanup=True,
            delete_remote=True,
            local_record={**local, "head_sha": "c" * 40},
        )


def test_reconcile_only_loads_recovery_record_from_custom_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from scripts import pr_delivery as cli

    record = {"schema_version": 1, "pr": 248, "recovery": {"from_status": "ATTENTION"}}
    (tmp_path / "pr-248-delivery.json").write_text(json.dumps(record), encoding="utf-8")
    output = tmp_path / "custom-result.json"
    seen = []

    def reconcile(*args, **kwargs):
        seen.append(kwargs["local_record"])
        return {"schema_version": 1, "pr": 248, "status": "MERGED"}

    monkeypatch.setattr(cli, "reconcile_delivery", reconcile)
    monkeypatch.setattr(
        cli.sys,
        "argv",
        ["pr_delivery.py", "--pr", "248", "--reconcile-only", "--output", str(output)],
    )
    assert cli.main() == 0
    assert seen == [record]
    assert json.loads(output.read_text(encoding="utf-8"))["status"] == "MERGED"
