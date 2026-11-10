#!/usr/bin/env python3
"""Merge a pull request only after green checks, then clean merged branches safely."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import read_json  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


def run_ok(command: list[str], cwd: Path) -> None:
    result = run(command, cwd)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr}")


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return run(["git", "-C", str(root), *arguments], root)


def clean_worktree(root: Path) -> bool:
    result = git(root, "status", "--porcelain", "--untracked-files=all")
    if result.returncode:
        raise RuntimeError(result.stderr)
    return not result.stdout.strip()


def current_branch(root: Path) -> str:
    result = git(root, "branch", "--show-current")
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


def local_branch_exists(root: Path, branch: str) -> bool:
    return git(root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0


def worktree_main_root(root: Path) -> Path:
    result = git(root, "worktree", "list", "--porcelain")
    if result.returncode:
        raise RuntimeError(result.stderr)
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            return Path(line.removeprefix("worktree "))
    raise RuntimeError("cannot determine the main worktree")


def remote_branch_delete(repository: str, branch: str, root: Path) -> None:
    result = run(["gh", "api", "-X", "DELETE", f"repos/{repository}/git/refs/heads/{branch}"], root)
    if result.returncode and "404" not in result.stderr and "Not Found" not in result.stderr:
        raise RuntimeError(result.stderr)


def cleanup_merged_branch(
    root: Path,
    pull: dict[str, Any],
    delete_remote: bool = True,
    remote_delete: Any = None,
) -> list[str]:
    warnings: list[str] = []
    if pull.get("state") != "MERGED":
        raise RuntimeError("refusing cleanup before the PR is merged")
    if pull.get("baseRefName") != "dev":
        raise RuntimeError("automatic cleanup is supported only for PRs targeting dev")
    repository = pull.get("headRepository", {}).get("name")
    owner = pull.get("headRepositoryOwner", {}).get("login")
    if repository != "retroSoC" or owner != "retroSoC":
        return [f"skip cleanup for non-canonical head repository: {owner}/{repository}"]
    branch = pull["headRefName"]
    if branch in {"dev", "main"}:
        raise RuntimeError("refusing to delete a protected branch")
    if not clean_worktree(root):
        return ["worktree is dirty; keep the merged branch and worktree unchanged"]
    main_root = worktree_main_root(root)
    merge_commit = pull.get("mergeCommit", {}).get("oid")
    if not merge_commit:
        raise RuntimeError("merged PR has no merge commit; refusing cleanup")
    run_ok(["git", "fetch", "origin", "dev"], main_root)
    run_ok(["git", "cat-file", "-e", f"{merge_commit}^{{commit}}"], main_root)
    if local_branch_exists(main_root, branch):
        contained = git(main_root, "merge-base", "--is-ancestor", branch, merge_commit)
        if contained.returncode == 1:
            return [f"local branch has unmerged commits; keep {branch} and its worktree unchanged"]
        if contained.returncode:
            raise RuntimeError(contained.stderr)
    current = current_branch(root)
    if current == branch and root.resolve() == main_root.resolve():
        run_ok(["git", "switch", "dev"], main_root)
        run_ok(["git", "merge", "--ff-only", "origin/dev"], main_root)
    elif current == branch:
        run_ok(["git", "-C", str(main_root), "worktree", "remove", str(root.resolve())], main_root)
    if local_branch_exists(main_root, branch):
        result = git(main_root, "branch", "-d", branch)
        if result.returncode:
            warnings.append(f"local branch could not be deleted safely: {branch}: {result.stderr.strip()}")
    if warnings:
        return warnings
    if delete_remote:
        (remote_delete or remote_branch_delete)("retroSoC/retroSoC", branch, main_root)
    return warnings


def view_pr(repository: str, number: int, root: Path) -> dict[str, Any]:
    return gh_json(
        [
            "pr",
            "view",
            str(number),
            "--repo",
            repository,
            "--json",
            "state,isDraft,baseRefName,headRefName,headRepository,headRepositoryOwner,mergeCommit,isCrossRepository",
        ]
    )


def merge_pr(repository: str, number: int, root: Path, pull: dict[str, Any]) -> None:
    if pull.get("isDraft"):
        ready = run(["gh", "pr", "ready", str(number), "--repo", repository], root)
        if ready.returncode:
            raise RuntimeError(f"failed to mark PR ready: {ready.stderr}")
    result = run(["gh", "pr", "merge", str(number), "--repo", repository, "--merge", "--auto"], root)
    if result.returncode:
        raise RuntimeError(f"merge failed: {result.stderr}")


def required_check_contexts(repository: str, base: str, root: Path) -> list[str]:
    protection = gh_json(["api", f"repos/{repository}/branches/{base}/protection/required_status_checks"])
    required = sorted({check["context"] for check in protection.get("checks", [])})
    if not required:
        raise RuntimeError(f"no required checks are configured for {base}; refusing to merge")
    return required


def native_auto_merge_enabled(repository: str, number: int, root: Path) -> bool:
    pull = gh_json(["api", f"repos/{repository}/pulls/{number}"])
    request = pull.get("auto_merge")
    if request is None:
        return False
    if request.get("merge_method") != "MERGE":
        raise RuntimeError("existing auto-merge request must use a merge commit")
    return True


def checks_result(root: Path, number: int, repository: str) -> subprocess.CompletedProcess[str]:
    return run(["gh", "pr", "checks", str(number), "--repo", repository], root)


def checks_green(result: subprocess.CompletedProcess[str], required: list[str] | None = None) -> bool:
    output = result.stdout.strip()
    lines = output.splitlines()
    reported = {line.split("\t", 1)[0] for line in lines}
    return (
        result.returncode == 0
        and bool(lines)
        and set(required or []).issubset(reported)
        and not any(marker in output.lower() for marker in ("pending", "queued", "in_progress"))
    )


def checks_failed(result: subprocess.CompletedProcess[str]) -> bool:
    output = result.stdout.lower()
    if "pending" in output or "queued" in output or "in_progress" in output:
        return False
    return any(marker in output for marker in ("fail", "error", "cancelled", "timed_out"))


def auto_merge_policy(root: Path) -> dict[str, Any]:
    policy = read_json(root / "quality/ownership.json").get("auto_merge", {})
    if policy.get("enabled") is not True:
        raise RuntimeError("auto_merge.enabled is not true in quality/ownership.json")
    if policy.get("strategy") != "merge_commit":
        raise RuntimeError("auto_merge.strategy must be merge_commit")
    if policy.get("require_green_checks") is not True:
        raise RuntimeError("auto_merge.require_green_checks must be true")
    if policy.get("cleanup_merged_branches") is not True:
        raise RuntimeError("auto_merge.cleanup_merged_branches must be true")
    if policy.get("allow_dirty_worktree") is not False:
        raise RuntimeError("auto_merge.allow_dirty_worktree must be false")
    return policy


def watch_and_merge(
    root: Path,
    repository: str,
    number: int,
    interval: int,
    cleanup: bool = True,
    delete_remote: bool = True,
) -> None:
    auto_merge_policy(root)
    if interval <= 0:
        raise ValueError("interval must be positive")
    previous_output = ""
    while True:
        pull = view_pr(repository, number, root)
        if pull.get("state") == "MERGED":
            if cleanup:
                warnings = cleanup_merged_branch(root, pull, delete_remote=delete_remote)
                for warning in warnings:
                    print(f"cleanup warning: {warning}", file=sys.stderr)
            print(f"PR #{number} merged", flush=True)
            return
        required = required_check_contexts(repository, pull["baseRefName"], root)
        result = checks_result(root, number, repository)
        output = result.stdout + (result.stderr or "")
        if output != previous_output:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
            previous_output = output
        if not result.stdout.strip():
            raise RuntimeError("no checks were reported; refusing to merge")
        if checks_failed(result):
            raise RuntimeError(f"PR #{number} checks failed; no merge or cleanup attempted")
        if checks_green(result, required):
            if not native_auto_merge_enabled(repository, number, root):
                merge_pr(repository, number, root, pull)
                print(f"PR #{number} native auto-merge enabled; waiting for GitHub", flush=True)
        time.sleep(interval)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--no-cleanup", action="store_true")
    parser.add_argument("--no-remote-delete", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        watch_and_merge(
            args.root.resolve(),
            args.repository,
            args.pr,
            args.interval,
            cleanup=not args.no_cleanup,
            delete_remote=not args.no_remote_delete,
        )
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"pr workflow: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
