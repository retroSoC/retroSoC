#!/usr/bin/env python3
"""Inventory agent worktrees and preserve evidence before safe cleanup."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.agent_control import read_json  # noqa: E402
from scripts.flow_control import file_digest, utc_now, write_json  # noqa: E402


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True, check=False)


def parse_worktrees(root: Path) -> tuple[Path, list[dict[str, Any]]]:
    result = git(root, "worktree", "list", "--porcelain")
    if result.returncode:
        raise RuntimeError(result.stderr)
    records = []
    current: dict[str, Any] = {}
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            if current:
                records.append(current)
            current = {"path": line.removeprefix("worktree "), "branch": None, "detached": True}
        elif line.startswith("HEAD "):
            current["head"] = line.removeprefix("HEAD ")
        elif line.startswith("branch "):
            current["branch"] = line.removeprefix("branch ").removeprefix("refs/heads/")
            current["detached"] = False
    if current:
        records.append(current)
    if not records:
        raise RuntimeError("no main worktree found")
    main_root = Path(records[0]["path"]).resolve()
    registered = {Path(record["path"]).resolve() for record in records}
    for path in sorted((main_root / "build/agent-worktrees").glob("*")):
        if path.is_dir() and path.resolve() not in registered:
            records.append({"path": str(path), "branch": None, "detached": True, "orphan": True})
    return main_root, records


def has_artifacts(worktree: Path) -> bool:
    build = worktree / "build"
    return build.is_dir() and any(path.is_file() for path in build.rglob("*"))


def task_identity(worktree: Path, branch: str) -> str:
    packets = sorted((worktree / "build/tasks").glob("*/task.json"))
    for packet in packets:
        try:
            task_id = read_json(packet).get("task_id")
            if task_id:
                return str(task_id)
        except ValueError:
            continue
    return branch.replace("/", "-")


def evidence_summary(path: Path) -> dict[str, Any]:
    files = [item for item in path.rglob("*") if item.is_file()]
    evidence_files = []
    for item in files:
        if item.name.startswith("result") or item.name in {"manifest.json", "state.json", "summary.json"}:
            record = {"path": item.relative_to(path).as_posix(), "bytes": item.stat().st_size}
            if item.stat().st_size <= 1024 * 1024:
                record["sha256"] = file_digest(item)
            evidence_files.append(record)
    return {
        "file_count": len(files),
        "bytes": sum(item.stat().st_size for item in files),
        "evidence_files": evidence_files,
    }


def inventory_record(main_root: Path, entry: dict[str, Any]) -> dict[str, Any]:
    path = Path(entry["path"]).resolve()
    branch = entry.get("branch")
    canonical_root = main_root / "build/agent-worktrees"
    if entry.get("orphan"):
        status = "ORPHAN_DIRECTORY"
    elif path == main_root:
        status = "MAIN_WORKTREE"
    elif not path.is_relative_to(canonical_root):
        status = "NON_CANONICAL"
    elif entry.get("detached") or not branch:
        status = "DETACHED"
    elif git(path, "status", "--porcelain", "--untracked-files=all").stdout.strip():
        status = "DIRTY"
    elif git(main_root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode:
        status = "MISSING_BRANCH"
    elif git(main_root, "merge-base", "--is-ancestor", branch, "origin/dev").returncode == 0:
        status = "ELIGIBLE"
    else:
        status = "UNMERGED"
    return {
        **entry,
        "path": str(path),
        "status": status,
        "cleanup_eligible": status == "ELIGIBLE",
        "artifacts_present": has_artifacts(path),
        "artifact_identity": task_identity(path, branch) if branch else None,
    }


def preserve_artifacts(main_root: Path, record: dict[str, Any]) -> Path | None:
    if not record["artifacts_present"]:
        return None
    identity = record["artifact_identity"] or "detached-artifacts"
    destination = main_root / "build/agent-artifacts" / identity
    if destination.exists():
        raise RuntimeError(f"artifact destination already exists: {destination}")
    source = Path(record["path"]) / "build"
    summary = evidence_summary(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    source.replace(destination)
    write_json(destination / "artifact-manifest.json", {
        "schema_version": 1,
        "source_revision": record.get("head"),
        "branch": record.get("branch"),
        "source_worktree": record["path"],
        **summary,
    })
    return destination


def reconcile_worktrees(root: Path, execute: bool = False, only_branch: str | None = None) -> dict[str, Any]:
    main_root, entries = parse_worktrees(root)
    records = [inventory_record(main_root, entry) for entry in entries]
    actions = []
    for record in records:
        if only_branch is not None and record.get("branch") != only_branch:
            continue
        if not execute or not record["cleanup_eligible"]:
            continue
        action = {"path": record["path"], "branch": record["branch"], "status": "CLEANED"}
        try:
            preserved = preserve_artifacts(main_root, record)
            if preserved:
                action["preserved_artifacts"] = str(preserved)
            removed = git(main_root, "worktree", "remove", record["path"])
            if removed.returncode:
                raise RuntimeError(removed.stderr.strip())
            branch = record["branch"]
            deleted = git(
                main_root,
                "-c",
                f"branch.{branch}.remote=origin",
                "-c",
                f"branch.{branch}.merge=refs/heads/dev",
                "branch",
                "-d",
                branch,
            )
            if deleted.returncode:
                raise RuntimeError(deleted.stderr.strip())
        except (OSError, ValueError, RuntimeError) as error:
            action["status"] = "PARTIAL" if action.get("preserved_artifacts") else "PRESERVED"
            action["warning"] = str(error)
        actions.append(action)
    return {
        "schema_version": 1,
        "source_revision": git(main_root, "rev-parse", "HEAD").stdout.strip(),
        "created_at": utc_now(),
        "execution": "execute" if execute else "dry-run",
        "worktrees": records,
        "actions": actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--branch", help="restrict cleanup to one merged topic branch")
    args = parser.parse_args()
    try:
        document = reconcile_worktrees(args.root.resolve(), execute=args.execute, only_branch=args.branch)
        output = args.output or args.root.resolve() / "build/agent-worktrees/registry.json"
        write_json(output, document)
        print(json.dumps(document, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"worktree registry: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
