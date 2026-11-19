#!/usr/bin/env python3
"""Run an isolated, non-committing merge check and return its exact conflicts."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path
from typing import Any


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], text=True, capture_output=True, check=False)


def result(
    status: str,
    merge_ref: str,
    merge_revision: str | None = None,
    unmerged_paths: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "status": status,
        "merge_ref": merge_ref,
        "merge_revision": merge_revision,
        "unmerged_paths": unmerged_paths or [],
        "worktree_removed": True,
        "merge_commit_created": False,
    }


def merge_conflict_scan(root: Path, merge_ref: str) -> dict[str, Any]:
    root = root.resolve()
    if not merge_ref or merge_ref.startswith("-"):
        raise ValueError("merge reference must not be empty or an option")
    worktree = git(root, "rev-parse", "--show-toplevel")
    if worktree.returncode or not worktree.stdout.strip():
        raise RuntimeError("merge check requires a Git worktree")
    main_root = Path(worktree.stdout.strip()).resolve()
    if git(root, "status", "--porcelain", "--untracked-files=all").stdout.strip():
        return result("DIRTY", merge_ref)
    revision = git(root, "rev-parse", "--verify", f"{merge_ref}^{{commit}}")
    if revision.returncode or not revision.stdout.strip():
        raise ValueError(f"merge reference is unavailable: {merge_ref}")
    merge_revision = revision.stdout.strip()
    head = git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if head.returncode or not head.stdout.strip():
        raise RuntimeError("merge check requires a HEAD commit")
    head_revision = head.stdout.strip()
    if git(root, "merge-base", "--is-ancestor", merge_revision, head_revision).returncode == 0:
        return result("PASS", merge_ref, merge_revision)

    parent = main_root / "build/agent-worktrees"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".merge-preflight-", dir=parent) as temporary:
        target = Path(temporary) / "checkout"
        added = git(main_root, "worktree", "add", "--detach", str(target), head_revision)
        if added.returncode:
            raise RuntimeError(f"cannot create isolated merge-check worktree: {added.stderr.strip()}")
        try:
            completed = git(target, "merge", "--no-commit", "--no-ff", merge_revision)
            conflicts = git(target, "diff", "--name-only", "--diff-filter=U")
            unmerged = sorted(path for path in conflicts.stdout.splitlines() if path)
            if completed.returncode == 0 and not unmerged:
                status = "PASS"
            elif completed.returncode != 0 and unmerged:
                status = "CONFLICT"
            else:
                raise RuntimeError(
                    f"merge check failed without a conflict list: {completed.stderr.strip() or completed.stdout.strip()}"
                )
        finally:
            cleanup_errors = []
            if git(target, "rev-parse", "--verify", "-q", "MERGE_HEAD").returncode == 0:
                aborted = git(target, "merge", "--abort")
                if aborted.returncode:
                    cleanup_errors.append(f"cannot abort isolated merge check: {aborted.stderr.strip()}")
            if git(target, "status", "--porcelain", "--untracked-files=all").stdout.strip():
                cleanup_errors.append("isolated merge check left changes in the temporary worktree")
            removed = git(main_root, "worktree", "remove", str(target))
            if removed.returncode:
                cleanup_errors.append(f"cannot remove isolated merge-check worktree: {removed.stderr.strip()}")
            if cleanup_errors:
                raise RuntimeError("; ".join(cleanup_errors))
    return result(status, merge_ref, merge_revision, unmerged)
