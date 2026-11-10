from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from scripts.pr_workflow import (
    checks_failed,
    checks_green,
    cleanup_merged_branch,
    current_branch,
    local_branch_exists,
)


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def make_repo(root: Path) -> dict:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    git(root, "config", "user.email", "workflow@example.invalid")
    git(root, "config", "user.name", "Workflow")
    (root / "README.md").write_text("initial\n", encoding="utf-8")
    git(root, "add", "README.md")
    git(root, "commit", "-qm", "initial")
    git(root, "checkout", "-qb", "dev")
    git(root, "checkout", "-qb", "feat/example")
    (root / "feature.txt").write_text("merged feature\n", encoding="utf-8")
    git(root, "add", "feature.txt")
    git(root, "commit", "-qm", "feature")
    git(root, "checkout", "dev")
    git(root, "merge", "--no-ff", "-m", "merge feature", "feat/example")
    merge_commit = git(root, "rev-parse", "HEAD").stdout.strip()
    git(root, "remote", "add", "origin", str(root))
    git(root, "fetch", "-q", "origin", "dev")
    git(root, "checkout", "feat/example")
    return {
        "state": "MERGED",
        "baseRefName": "dev",
        "headRefName": "feat/example",
        "headRepository": {"name": "retroSoC"},
        "headRepositoryOwner": {"login": "retroSoC"},
        "mergeCommit": {"oid": merge_commit},
    }


def test_checks_require_nonempty_green_output() -> None:
    green = subprocess.CompletedProcess([], 0, stdout="fast pass\n")
    pending = subprocess.CompletedProcess([], 1, stdout="fast pending\n")
    failed = subprocess.CompletedProcess([], 1, stdout="fast fail\n")
    empty = subprocess.CompletedProcess([], 1, stdout="")
    assert checks_green(green)
    assert not checks_green(pending)
    assert not checks_green(failed)
    assert not checks_green(empty)
    assert checks_failed(failed)
    assert not checks_failed(pending)
    assert not checks_failed(empty)


def test_checks_require_all_protected_contexts() -> None:
    visible = subprocess.CompletedProcess([], 0, stdout="fast\tpass\ncontribution-gate\tpass\n")
    complete = subprocess.CompletedProcess([], 0, stdout=visible.stdout + "quality-gate\tpass\n")
    running = subprocess.CompletedProcess([], 0, stdout="quality-gate\tin_progress\n")
    required = ["quality-gate", "contribution-gate"]
    assert not checks_green(visible, required)
    assert checks_green(complete, required)
    assert not checks_green(running, required)


def test_cleanup_switches_to_dev_and_deletes_merged_branch(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    deleted = []
    warnings = cleanup_merged_branch(
        tmp_path,
        pull,
        remote_delete=lambda repository, branch, root: deleted.append((repository, branch)),
    )
    assert warnings == []
    assert current_branch(tmp_path) == "dev"
    assert not local_branch_exists(tmp_path, "feat/example")
    assert deleted == [("retroSoC/retroSoC", "feat/example")]


def test_cleanup_preserves_unmerged_local_commits(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    (tmp_path / "local-only.txt").write_text("not in the PR\n", encoding="utf-8")
    git(tmp_path, "add", "local-only.txt")
    git(tmp_path, "commit", "-qm", "local only")
    deleted = []
    warnings = cleanup_merged_branch(
        tmp_path,
        pull,
        remote_delete=lambda repository, branch, root: deleted.append((repository, branch)),
    )
    assert warnings == ["local branch has unmerged commits; keep feat/example and its worktree unchanged"]
    assert current_branch(tmp_path) == "feat/example"
    assert local_branch_exists(tmp_path, "feat/example")
    assert deleted == []
    assert (tmp_path / "local-only.txt").is_file()


def test_cleanup_removes_clean_linked_worktree(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    git(tmp_path, "switch", "dev")
    linked = tmp_path.parent / "linked"
    git(tmp_path, "worktree", "add", str(linked), "feat/example")
    deleted = []
    warnings = cleanup_merged_branch(
        linked,
        pull,
        remote_delete=lambda repository, branch, root: deleted.append((repository, branch)),
    )
    assert warnings == []
    assert not linked.exists()
    assert current_branch(tmp_path) == "dev"
    assert not local_branch_exists(tmp_path, "feat/example")
    assert deleted == [("retroSoC/retroSoC", "feat/example")]


def test_cleanup_preserves_dirty_worktree_and_remote_branch(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    (tmp_path / "untracked.txt").write_text("preserve me\n", encoding="utf-8")
    deleted = []
    warnings = cleanup_merged_branch(
        tmp_path,
        pull,
        remote_delete=lambda repository, branch, root: deleted.append((repository, branch)),
    )
    assert warnings == ["worktree is dirty; keep the merged branch and worktree unchanged"]
    assert current_branch(tmp_path) == "feat/example"
    assert local_branch_exists(tmp_path, "feat/example")
    assert deleted == []
    assert (tmp_path / "untracked.txt").is_file()


def test_cleanup_skips_noncanonical_head_repository(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    pull["headRepository"] = {"name": "fork"}
    pull["headRepositoryOwner"] = {"login": "someone"}
    warnings = cleanup_merged_branch(tmp_path, pull)
    assert len(warnings) == 1
    assert "non-canonical" in warnings[0]
    assert current_branch(tmp_path) == "feat/example"


def test_cleanup_rejects_unmerged_pr(tmp_path: Path) -> None:
    pull = make_repo(tmp_path)
    pull["state"] = "OPEN"
    with pytest.raises(RuntimeError, match="before the PR is merged"):
        cleanup_merged_branch(tmp_path, pull)


def test_merge_marks_draft_pr_ready_before_merging(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []

    def fake_run(command, _cwd):
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("scripts.pr_workflow.run", fake_run)
    from scripts.pr_workflow import merge_pr

    merge_pr("retroSoC/retroSoC", 231, Path.cwd(), {"isDraft": True})
    assert calls[0][2] == "ready"
    assert calls[1][2] == "merge"
    assert "--auto" in calls[1]
    assert "--admin" not in calls[1]


def test_merge_does_not_mark_ready_pr_again(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []

    def fake_run(command, _cwd):
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("scripts.pr_workflow.run", fake_run)
    from scripts.pr_workflow import merge_pr

    merge_pr("retroSoC/retroSoC", 230, Path.cwd(), {"isDraft": False})
    assert [command[2] for command in calls] == ["merge"]


def test_required_checks_come_from_branch_protection(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.pr_workflow import required_check_contexts

    monkeypatch.setattr(
        "scripts.pr_workflow.gh_json",
        lambda command: {"checks": [{"context": "quality-gate"}, {"context": "contribution-gate"}]},
    )
    assert required_check_contexts("retroSoC/retroSoC", "dev", Path.cwd()) == [
        "contribution-gate",
        "quality-gate",
    ]
    monkeypatch.setattr("scripts.pr_workflow.gh_json", lambda command: {"checks": []})
    with pytest.raises(RuntimeError, match="no required checks"):
        required_check_contexts("retroSoC/retroSoC", "dev", Path.cwd())


def test_native_auto_merge_requires_merge_commit(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.pr_workflow import native_auto_merge_enabled

    monkeypatch.setattr("scripts.pr_workflow.gh_json", lambda command: {"auto_merge": None})
    assert not native_auto_merge_enabled("retroSoC/retroSoC", 230, Path.cwd())
    monkeypatch.setattr(
        "scripts.pr_workflow.gh_json", lambda command: {"auto_merge": {"merge_method": "MERGE"}}
    )
    assert native_auto_merge_enabled("retroSoC/retroSoC", 230, Path.cwd())
    monkeypatch.setattr(
        "scripts.pr_workflow.gh_json", lambda command: {"auto_merge": {"merge_method": "SQUASH"}}
    )
    with pytest.raises(RuntimeError, match="must use a merge commit"):
        native_auto_merge_enabled("retroSoC/retroSoC", 230, Path.cwd())


def test_watch_waits_for_native_merge_without_duplicate_requests(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.pr_workflow import watch_and_merge

    pull = {"state": "OPEN", "baseRefName": "dev", "isDraft": False}
    states = iter([pull, pull, {**pull, "state": "MERGED"}])
    queued = iter([False, True])
    merge_calls = []
    cleanup_calls = []
    sleeps = []
    monkeypatch.setattr("scripts.pr_workflow.auto_merge_policy", lambda root: {})
    monkeypatch.setattr("scripts.pr_workflow.view_pr", lambda repository, number, root: next(states))
    monkeypatch.setattr("scripts.pr_workflow.required_check_contexts", lambda repository, base, root: ["quality-gate"])
    monkeypatch.setattr(
        "scripts.pr_workflow.checks_result",
        lambda root, number, repository: subprocess.CompletedProcess([], 0, stdout="quality-gate\tpass\n"),
    )
    monkeypatch.setattr("scripts.pr_workflow.native_auto_merge_enabled", lambda repository, number, root: next(queued))
    monkeypatch.setattr("scripts.pr_workflow.merge_pr", lambda repository, number, root, pull: merge_calls.append(number))
    monkeypatch.setattr(
        "scripts.pr_workflow.cleanup_merged_branch",
        lambda root, pull, delete_remote: cleanup_calls.append(pull["state"]) or [],
    )
    monkeypatch.setattr("scripts.pr_workflow.time.sleep", sleeps.append)
    watch_and_merge(Path.cwd(), "retroSoC/retroSoC", 230, 60)
    assert merge_calls == [230]
    assert cleanup_calls == ["MERGED"]
    assert sleeps == [60, 60]
