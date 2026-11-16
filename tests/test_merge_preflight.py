from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from scripts.merge_preflight import merge_conflict_scan


ROOT = Path(__file__).resolve().parents[1]


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def commit(root: Path, relative: str, content: str, message: str) -> str:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    git(root, "add", relative)
    git(root, "commit", "-qm", message)
    return git(root, "rev-parse", "HEAD").stdout.strip()


def repository(root: Path, conflict: bool) -> tuple[Path, str]:
    subprocess.run(["git", "init", "-q", "-b", "dev", str(root)], check=True)
    git(root, "config", "user.email", "merge-check@example.invalid")
    git(root, "config", "user.name", "Merge Check")
    commit(root, "shared.txt", "base\n", "base")
    commit(root, "target.txt", "base\n", "target base")
    git(root, "switch", "-qc", "ci/topic")
    commit(root, "shared.txt" if conflict else "topic.txt", "topic\n", "topic")
    git(root, "switch", "-q", "dev")
    target = commit(root, "shared.txt" if conflict else "target.txt", "target\n", "target")
    linked = root.parent / "topic"
    git(root, "worktree", "add", "-q", str(linked), "ci/topic")
    return linked, target


def assert_source_unchanged(source: Path, expected_head: str, expected_worktrees: list[str]) -> None:
    assert git(source, "rev-parse", "HEAD").stdout.strip() == expected_head
    assert git(source, "status", "--porcelain", "--untracked-files=all").stdout == ""
    assert len(git(source, "rev-list", "--parents", "-n", "1", "HEAD").stdout.split()) == 2
    assert not (source / ".git/MERGE_HEAD").exists()
    assert git(source, "worktree", "list", "--porcelain").stdout.splitlines() == expected_worktrees


def test_conflicting_merge_preserves_linked_source_and_removes_temporary_worktree(tmp_path: Path) -> None:
    source, target = repository(tmp_path / "repo", conflict=True)
    head = git(source, "rev-parse", "HEAD").stdout.strip()
    before = git(source, "worktree", "list", "--porcelain").stdout.splitlines()

    evidence = merge_conflict_scan(source, "dev")

    assert evidence == {
        "status": "CONFLICT",
        "merge_ref": "dev",
        "merge_revision": target,
        "unmerged_paths": ["shared.txt"],
        "worktree_removed": True,
        "merge_commit_created": False,
    }
    assert (source / "shared.txt").read_text(encoding="utf-8") == "topic\n"
    assert_source_unchanged(source, head, before)
    assert not list((tmp_path / "repo/build/agent-worktrees").glob(".merge-preflight-*"))


def test_nonconflicting_merge_passes_without_committing_or_touching_source(tmp_path: Path) -> None:
    source, target = repository(tmp_path / "repo", conflict=False)
    head = git(source, "rev-parse", "HEAD").stdout.strip()
    before = git(source, "worktree", "list", "--porcelain").stdout.splitlines()

    evidence = merge_conflict_scan(source, "dev")

    assert evidence["status"] == "PASS"
    assert evidence["merge_revision"] == target
    assert evidence["unmerged_paths"] == []
    assert evidence["worktree_removed"] is True
    assert evidence["merge_commit_created"] is False
    assert (source / "topic.txt").read_text(encoding="utf-8") == "topic\n"
    assert (source / "target.txt").read_text(encoding="utf-8") == "base\n"
    assert_source_unchanged(source, head, before)


def test_dirty_source_does_not_create_a_merge_environment(tmp_path: Path) -> None:
    source, _ = repository(tmp_path / "repo", conflict=True)
    head = git(source, "rev-parse", "HEAD").stdout.strip()
    before = git(source, "worktree", "list", "--porcelain").stdout.splitlines()
    (source / "topic-local.txt").write_text("keep\n", encoding="utf-8")

    evidence = merge_conflict_scan(source, "dev")

    assert evidence["status"] == "DIRTY"
    assert evidence["merge_commit_created"] is False
    assert evidence["worktree_removed"] is True
    assert (source / "topic-local.txt").read_text(encoding="utf-8") == "keep\n"
    assert git(source, "rev-parse", "HEAD").stdout.strip() == head
    assert git(source, "worktree", "list", "--porcelain").stdout.splitlines() == before
    assert not (tmp_path / "repo/build/agent-worktrees").exists()


@pytest.mark.parametrize("reference", ["", "--help", "missing-target"])
def test_invalid_merge_reference_fails_without_a_merge(reference: str, tmp_path: Path) -> None:
    source, _ = repository(tmp_path / "repo", conflict=True)
    head = git(source, "rev-parse", "HEAD").stdout.strip()
    before = git(source, "worktree", "list", "--porcelain").stdout.splitlines()

    with pytest.raises(ValueError, match="merge reference"):
        merge_conflict_scan(source, reference)

    assert_source_unchanged(source, head, before)


def test_ancestor_target_passes_without_a_temporary_worktree(tmp_path: Path) -> None:
    source, _ = repository(tmp_path / "repo", conflict=False)
    head = git(source, "rev-parse", "HEAD").stdout.strip()
    before = git(source, "worktree", "list", "--porcelain").stdout.splitlines()

    evidence = merge_conflict_scan(source, "HEAD")

    assert evidence["status"] == "PASS"
    assert evidence["merge_revision"] == head
    assert evidence["merge_commit_created"] is False
    assert_source_unchanged(source, head, before)
    assert not (tmp_path / "repo/build/agent-worktrees").exists()


def test_make_preflight_enables_merge_check_with_an_explicit_opt_out() -> None:
    default = subprocess.run(
        ["make", "-s", "-n", "agent-preflight", "TASK=build/tasks/example/task.json"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    disabled = subprocess.run(
        [
            "make",
            "-s",
            "-n",
            "agent-preflight",
            "TASK=build/tasks/example/task.json",
            "MERGE_CHECK=0",
            "MERGE_REF=dev",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout

    assert "--merge-check" in default
    assert "--no-merge-check" not in default
    assert "--merge-ref origin/dev" in default
    assert "--no-merge-check" in disabled
    assert " --merge-check " not in disabled
    assert "--merge-ref dev" in disabled
