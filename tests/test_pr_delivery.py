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
    monkeypatch.setattr("scripts.pr_delivery.checks_report", lambda *args, **kwargs: pytest.fail("must not poll"))
    result = deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=False)
    assert result["status"] == "AUTO_MERGE_ENABLED"
    assert result["cleanup"] == "PENDING"
    assert calls == [248]

    blocked = enable_delivery(ROOT, "retroSoC/retroSoC", 248, {**preflight(), "status": "BLOCKED"})
    assert blocked["status"] == "BLOCKED"
    assert calls == [248]


def test_watch_enables_auto_merge_before_pending_checks(monkeypatch: pytest.MonkeyPatch) -> None:
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
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda root, repository, number: preflight())
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: next(native))
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: next(states))
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda repository, number, root, current: calls.append(number))

    def report(*args, **kwargs):
        assert kwargs["allow_empty"] is True
        return next(reports)

    monkeypatch.setattr("scripts.pr_delivery.checks_report", report)
    monkeypatch.setattr("scripts.pr_delivery.reconcile_delivery", lambda *args: {"status": "MERGED"})
    monkeypatch.setattr("scripts.pr_delivery.time.sleep", sleeps.append)
    result = deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True)
    assert result["status"] == "MERGED"
    assert calls == [248]
    assert sleeps == [60, 60]


def test_failed_checks_and_disabled_native_auto_merge_stop_watch(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pr_delivery.delivery_preflight", lambda root, repository, number: preflight())
    native = iter([False, True])
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: next(native))
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: pull())
    monkeypatch.setattr("scripts.pr_delivery.merge_pr", lambda repository, number, root, current: None)
    monkeypatch.setattr(
        "scripts.pr_delivery.checks_report",
        lambda *args, **kwargs: {"status": "FAIL", "head_sha": "a" * 40},
    )
    with pytest.raises(RuntimeError, match="checks failed"):
        deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True)

    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: False)
    monkeypatch.setattr("scripts.pr_delivery.checks_report", lambda *args, **kwargs: pytest.fail("must not poll"))
    with pytest.raises(RuntimeError, match="auto-merge was disabled"):
        deliver(ROOT, "retroSoC/retroSoC", 248, 60, watch=True)


def test_head_change_between_preflight_and_enable_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pr_delivery.native_auto_merge_enabled", lambda repository, number, root: False)
    changed = pull()
    changed["headRefOid"] = "c" * 40
    monkeypatch.setattr("scripts.pr_delivery.view_pr", lambda repository, number, root: changed)
    with pytest.raises(RuntimeError, match="head changed"):
        enable_delivery(ROOT, "retroSoC/retroSoC", 248, preflight())
