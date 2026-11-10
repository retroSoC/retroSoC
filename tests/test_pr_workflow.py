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


def git(root: Path, *arguments: str) -> None:
    subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True)


def make_repo(root: Path) -> dict:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    git(root, "config", "user.email", "workflow@example.invalid")
    git(root, "config", "user.name", "Workflow")
    (root / "README.md").write_text("initial\n", encoding="utf-8")
    git(root, "add", "README.md")
    git(root, "commit", "-qm", "initial")
    git(root, "checkout", "-qb", "dev")
    git(root, "update-ref", "refs/remotes/origin/dev", "HEAD")
    git(root, "checkout", "-qb", "feat/example")
    return {
        "state": "MERGED",
        "baseRefName": "dev",
        "headRefName": "feat/example",
        "headRepository": {"name": "retroSoC"},
        "headRepositoryOwner": {"login": "retroSoC"},
        "mergeCommit": {"oid": "a" * 40},
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
