from __future__ import annotations

from pathlib import Path

import pytest

from scripts.pr_delivery import deliver, delivery_preflight, enable_delivery

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
