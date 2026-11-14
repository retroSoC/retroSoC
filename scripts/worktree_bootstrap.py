#!/usr/bin/env python3
"""Create or restore a canonical agent worktree from validated locked inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import read_json, safe_relative_path, validate_task  # noqa: E402
from scripts.flow_control import file_digest, utc_now, write_json  # noqa: E402
from scripts.setup_helpers import (  # noqa: E402
    download_file_from_urls,
    ensure_git_repo,
    git_output,
    sha256,
)
from scripts.worktree_registry import git, parse_worktrees  # noqa: E402

BRANCH = re.compile(r"(?:ci|fix|feat|docs)/[a-z0-9][a-z0-9._/-]*")


def locked_source(root: Path, revision: str, name: str) -> tuple[dict[str, Any], bytes]:
    payload = subprocess.check_output(
        ["git", "-C", str(root), "show", f"{revision}:dependencies/dependencies.lock.json"]
    )
    document = json.loads(payload)
    source = document.get("sources", {}).get(name)
    if not isinstance(source, dict):
        raise ValueError(f"unknown locked Git source: {name}")
    if not {"url", "revision", "destination"}.issubset(source):
        raise ValueError(f"locked source identity is incomplete: {name}")
    if not isinstance(source["url"], str) or not source["url"].startswith("https://"):
        raise ValueError(f"locked source URL must use HTTPS: {name}")
    if re.fullmatch(r"[0-9a-f]{40}", source["revision"]) is None:
        raise ValueError(f"locked source revision must be a full commit: {name}")
    if not safe_relative_path(source["destination"]):
        raise ValueError(f"locked source destination is unsafe: {name}")
    if source.get("recursive") or source.get("submodules"):
        raise ValueError(f"recursive source {name} requires its existing submodule-aware setup flow")
    return source, payload


def target_path(main_root: Path, task: dict[str, Any]) -> Path:
    value = task["execution"]["worktree"]
    prefix = "build/agent-worktrees/"
    if not safe_relative_path(value) or not value.startswith(prefix) or value == prefix:
        raise ValueError("task worktree must name one canonical build/agent-worktrees child")
    canonical = main_root / prefix
    requested = main_root / value
    if canonical.is_symlink() or requested.is_symlink():
        raise ValueError("the canonical worktree parent and target must not be symlinks")
    target = requested.resolve()
    if target.parent != canonical.resolve() or target == main_root:
        raise ValueError("task worktree must be a direct canonical child")
    return target


def available_offline_checkout(destination: Path, revision: str) -> bool:
    if not (destination / ".git").exists():
        return False
    return git(destination, "cat-file", "-e", f"{revision}^{{commit}}").returncode == 0


def restore_sources(
    main_root: Path,
    target: Path,
    base_revision: str,
    names: list[str],
    allow_network: bool,
) -> list[dict[str, Any]]:
    if len(set(names)) != len(names):
        raise ValueError("source names must be unique")
    records = []
    for name in names:
        source, payload = locked_source(main_root, base_revision, name)
        destination = target / source["destination"]
        reference = main_root / source["destination"]
        if reference == destination:
            raise ValueError("source and destination checkouts must be distinct")
        if not destination.resolve().is_relative_to(target):
            raise ValueError("destination must stay inside the target worktree")
        if not reference.resolve().is_relative_to(main_root) or reference.is_symlink():
            raise ValueError(f"reference must stay inside the main repository without a symlink: {reference}")
        selected_reference = reference if reference.exists() else None
        local_checkout = available_offline_checkout(destination, source["revision"])
        if selected_reference is None and not allow_network and not local_checkout:
            raise RuntimeError(f"no validated local copy of {name}; network fallback is disabled")
        ensure_git_repo(
            source["url"],
            destination,
            source["revision"],
            reference=selected_reference,
            fetch_timeout=300,
            fetch_attempts=3,
        )
        records.append(
            {
                "name": name,
                "url": source["url"],
                "revision": source["revision"],
                "destination": source["destination"],
                "lock_sha256": hashlib.sha256(payload).hexdigest(),
                "restore_mode": "locked-copy" if selected_reference else "local-checkout" if local_checkout else "network",
                "reference": str(selected_reference) if selected_reference else None,
                "status": "VERIFIED",
            }
        )
    return records


def restore_archives(
    main_root: Path,
    target: Path,
    base_revision: str,
    names: list[str],
    allow_network: bool,
) -> list[dict[str, Any]]:
    if len(set(names)) != len(names):
        raise ValueError("archive names must be unique")
    payload = subprocess.check_output(
        ["git", "-C", str(main_root), "show", f"{base_revision}:dependencies/dependencies.lock.json"]
    )
    lock = json.loads(payload)
    records = []
    for name in names:
        archive = lock.get("archives", {}).get(name)
        if not isinstance(archive, dict) or not {"url", "sha256", "destination"}.issubset(archive):
            raise ValueError(f"unknown or incomplete locked archive: {name}")
        if not archive["destination"].endswith((".tar.gz", ".tgz", ".tar", ".zip")):
            raise ValueError(f"archive {name} is a package directory; use its existing setup flow")
        if not safe_relative_path(archive["destination"]) or re.fullmatch(r"[0-9a-f]{64}", archive["sha256"]) is None:
            raise ValueError(f"archive {name} has an unsafe path or invalid SHA-256")
        urls = [archive["url"], *archive.get("fallback_urls", [])]
        if any(not isinstance(url, str) or not url.startswith("https://") for url in urls):
            raise ValueError(f"archive {name} URLs must use HTTPS")
        destination = target / archive["destination"]
        reference = main_root / archive["destination"]
        if not destination.resolve().is_relative_to(target):
            raise ValueError("archive destination must stay inside the target worktree")
        if not reference.resolve().is_relative_to(main_root) or reference.is_symlink():
            raise ValueError("archive reference must stay inside the main repository without a symlink")
        if destination.is_symlink():
            raise ValueError("archive destination must not be a symlink")
        if destination.exists():
            if not destination.is_file() or sha256(destination) != archive["sha256"]:
                raise RuntimeError(f"existing archive does not match the lock: {name}")
            mode = "local-archive"
        else:
            selected_reference = reference if reference.exists() else None
            if selected_reference is not None:
                if not selected_reference.is_file() or sha256(selected_reference) != archive["sha256"]:
                    raise RuntimeError(f"archive reference does not match the lock: {name}")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(
                    prefix=f".{destination.name}.", dir=destination.parent, delete=False
                ) as stream:
                    temporary = Path(stream.name)
                try:
                    shutil.copyfile(selected_reference, temporary)
                    if sha256(temporary) != archive["sha256"]:
                        raise RuntimeError(f"archive copy does not match the lock: {name}")
                    if destination.exists():
                        raise RuntimeError(f"archive destination appeared during restore: {destination}")
                    temporary.replace(destination)
                finally:
                    temporary.unlink(missing_ok=True)
                mode = "locked-copy"
            else:
                if not allow_network:
                    raise RuntimeError(f"no validated local archive for {name}; network fallback is disabled")
                download_file_from_urls(urls, destination, archive["sha256"], retries=3, timeout=30)
                mode = "network"
        records.append(
            {
                "name": name,
                "destination": archive["destination"],
                "sha256": archive["sha256"],
                "bytes": destination.stat().st_size,
                "lock_sha256": hashlib.sha256(payload).hexdigest(),
                "restore_mode": mode,
                "status": "VERIFIED",
            }
        )
    return records


def bootstrap_worktree(
    root: Path,
    task_path: Path,
    branch: str | None,
    source_names: list[str],
    execute: bool,
    create: bool,
    allow_network: bool,
    output: Path | None = None,
    archive_names: list[str] | None = None,
) -> dict[str, Any]:
    main_root, entries = parse_worktrees(root)
    if task_path.is_symlink():
        raise ValueError("task packet must not be a symlink")
    task_path = task_path.resolve()
    if not task_path.is_file() or not task_path.is_relative_to(main_root):
        raise ValueError("task packet must be a regular file inside the repository")
    task = read_json(task_path)
    issues = validate_task(task, main_root)
    if issues:
        raise ValueError("invalid task packet: " + "; ".join(issues))
    if task["execution"]["mode"] != "workspace-write":
        raise ValueError("worktree bootstrap requires a workspace-write task")
    target = target_path(main_root, task)
    artifact_root = (target / task["execution"]["artifact_root"]).resolve()
    if not artifact_root.is_relative_to(target):
        raise ValueError("task artifact root must stay inside the target worktree")
    base = task["base_revision"]
    if git(main_root, "cat-file", "-e", f"{base}^{{commit}}").returncode:
        raise ValueError("task base revision is unavailable")
    if create:
        if branch is None or BRANCH.fullmatch(branch) is None or branch in {"dev", "main"}:
            raise ValueError("create requires a conventional ci/fix/feat/docs topic branch")
        if git(main_root, "check-ref-format", "--branch", branch).returncode:
            raise ValueError("invalid Git branch")
        if base != git_output(main_root, "rev-parse", "origin/dev"):
            raise ValueError("new worktree task base must equal current origin/dev")
        for reference in (f"refs/heads/{branch}", f"refs/remotes/origin/{branch}"):
            if git(main_root, "show-ref", "--verify", "--quiet", reference).returncode == 0:
                raise ValueError(f"branch already exists: {branch}")
        if target.exists():
            raise ValueError(f"target worktree already exists: {target}")
    else:
        registered = [entry for entry in entries if Path(entry["path"]).resolve() == target]
        if len(registered) != 1 or registered[0].get("detached"):
            raise ValueError("existing target must be one registered non-detached worktree")
        if root.resolve() != target:
            raise ValueError("restore must be invoked from the target worktree")
        if branch is not None and branch != registered[0].get("branch"):
            raise ValueError("branch does not match the registered target")
        branch = registered[0].get("branch")
        if git(target, "merge-base", "--is-ancestor", base, "HEAD").returncode:
            raise ValueError("task base is not an ancestor of the target head")
    document = {
        "schema_version": 1,
        "task_id": task["task_id"],
        "created_at": utc_now(),
        "execution": "execute" if execute else "dry-run",
        "operation": "create" if create else "restore",
        "status": "PLANNED",
        "base_revision": base,
        "branch": branch,
        "worktree": str(target),
        "reference_root": str(main_root),
        "network_allowed": allow_network,
        "network_policy": "explicit network fallback enabled" if allow_network else "offline/local-copy only",
        "requested_sources": source_names,
        "requested_archives": archive_names or [],
        "sources": [],
        "archives": [],
        "packet_sha256": file_digest(task_path),
    }

    def write_result() -> None:
        destination = output or (
            target / task["execution"]["artifact_root"] / "bootstrap.json"
            if target.is_dir()
            else main_root / "build/agent-worktrees" / f"bootstrap-{task['task_id']}.json"
        )
        write_json(destination, document)

    try:
        if execute:
            if create:
                result = git(main_root, "worktree", "add", "-b", branch, str(target), base)
                if result.returncode:
                    raise RuntimeError(result.stderr.strip())
            document["sources"] = restore_sources(main_root, target, base, source_names, allow_network)
            document["archives"] = restore_archives(
                main_root, target, base, archive_names or [], allow_network
            )
            packet_destination = target / task["execution"]["artifact_root"] / "task.json"
            if packet_destination.is_symlink():
                raise ValueError("task packet destination must not be a symlink")
            if packet_destination.exists() and packet_destination.resolve() != task_path:
                raise ValueError(f"task packet destination already exists: {packet_destination}")
            if packet_destination.resolve() != task_path:
                packet_destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(task_path, packet_destination)
            document["source_revision"] = git_output(target, "rev-parse", "HEAD")
            document["source_dirty"] = bool(git(target, "status", "--porcelain", "--untracked-files=all").stdout.strip())
            document["status"] = "READY"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        document["status"] = "FAILED"
        document["error"] = str(error)
        write_result()
        raise
    write_result()
    return document


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--task", type=Path, required=True)
    parser.add_argument("--branch")
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--archive", action="append", default=[])
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = bootstrap_worktree(
            args.root.resolve(),
            args.task,
            args.branch,
            args.source,
            args.execute,
            args.create,
            args.allow_network,
            args.output,
            archive_names=args.archive,
        )
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"worktree bootstrap: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
