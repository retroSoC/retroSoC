from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.setup_helpers import ensure_git_repo, sha256
from scripts.worktree_bootstrap import bootstrap_worktree, restore_archives

ROOT = Path(__file__).resolve().parents[1]
LOCKED_URL = "https://example.invalid/locked.git"


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def task_packet(root: Path, base: str, task_id: str = "demo") -> Path:
    task = {
        "schema_version": 1,
        "task_id": task_id,
        "task_class": "tooling",
        "base_revision": base,
        "target_socs": [],
        "scope": {
            "summary": "Validate lock-bound worktree startup",
            "allowed_paths": ["scripts/**", "tests/**", "quality/**", "Makefile"],
            "forbidden_paths": ["crt/**", "app/**"],
            "non_goals": ["product changes"],
        },
        "acceptance": ["Restore only the locked revision without shared writable state"],
        "validation": {"risk": "low", "mode": "affected", "profiles": [], "pdks": []},
        "execution": {
            "mode": "workspace-write",
            "worktree": f"build/agent-worktrees/{task_id}",
            "artifact_root": f"build/tasks/{task_id}",
        },
        "status": "in_progress",
    }
    path = root / "build/tasks" / f"{task_id}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(task), encoding="utf-8")
    return path


def repository(root: Path, with_reference: bool = True) -> tuple[str, Path]:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    git(root, "config", "user.email", "agent@example.invalid")
    git(root, "config", "user.name", "Agent")
    (root / ".gitignore").write_text("build/\n.cache/\nrtl/managed/\n", encoding="utf-8")
    upstream = root / ".cache/upstream"
    subprocess.run(["git", "init", "-q", str(upstream)], check=True)
    git(upstream, "config", "user.email", "upstream@example.invalid")
    git(upstream, "config", "user.name", "Upstream")
    (upstream / "dependency.txt").write_text("locked\n", encoding="utf-8")
    git(upstream, "add", "dependency.txt")
    git(upstream, "commit", "-qm", "locked source")
    revision = git(upstream, "rev-parse", "HEAD").stdout.strip()
    reference = root / "rtl/managed/example"
    if with_reference:
        subprocess.run(
            ["git", "clone", "-q", "--no-local", str(upstream), str(reference)], check=True
        )
        git(reference, "checkout", "--detach", revision)
        git(reference, "remote", "set-url", "origin", LOCKED_URL)
    archive = root / ".cache/downloads/example.tar.gz"
    archive.parent.mkdir(parents=True)
    archive.write_bytes(b"verified archive\n")
    lock = {
        "schema_version": 1,
        "sources": {
            "example": {
                "url": LOCKED_URL,
                "revision": revision,
                "destination": "rtl/managed/example",
            }
        },
        "archives": {
            "example-archive": {
                "url": "https://example.invalid/example.tar.gz",
                "sha256": sha256(archive),
                "destination": ".cache/downloads/example.tar.gz",
            }
        },
    }
    (root / "dependencies").mkdir()
    (root / "dependencies/dependencies.lock.json").write_text(json.dumps(lock), encoding="utf-8")
    git(root, "add", ".gitignore", "dependencies/dependencies.lock.json")
    git(root, "commit", "-qm", "initial")
    git(root, "update-ref", "refs/remotes/origin/dev", "HEAD")
    return revision, reference


def test_bootstrap_dry_run_then_real_locked_copy(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    revision, reference = repository(root)
    packet = task_packet(root, git(root, "rev-parse", "HEAD").stdout.strip())
    plan = bootstrap_worktree(
        root, packet, "feat/example", ["example"], execute=False, create=True, allow_network=False
    )
    target = root / "build/agent-worktrees/demo"
    assert plan["status"] == "PLANNED"
    assert plan["sources"] == []
    assert not target.exists()

    completed = subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/worktree_bootstrap.py"),
            "--root",
            str(root),
            "--task",
            str(packet),
            "--branch",
            "feat/example",
            "--source",
            "example",
            "--archive",
            "example-archive",
            "--create",
            "--execute",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    document = json.loads((target / "build/tasks/demo/bootstrap.json").read_text(encoding="utf-8"))
    assert document["status"] == "READY"
    assert document["network_allowed"] is False
    assert document["sources"][0]["restore_mode"] == "locked-copy"
    assert document["archives"][0]["restore_mode"] == "locked-copy"
    assert (target / ".cache/downloads/example.tar.gz").read_bytes() == b"verified archive\n"
    assert document["sources"][0]["revision"] == revision
    destination = target / "rtl/managed/example"
    assert (destination / "dependency.txt").read_text(encoding="utf-8") == "locked\n"
    assert git(destination, "remote", "get-url", "origin").stdout.strip() == LOCKED_URL
    assert git(destination, "rev-parse", "HEAD").stdout.strip() == revision
    assert not (destination / ".git/objects/info/alternates").exists()
    assert not destination.is_symlink()
    assert git(reference, "status", "--porcelain").stdout == ""

    restored = bootstrap_worktree(
        target,
        target / "build/tasks/demo/task.json",
        None,
        ["example"],
        execute=True,
        create=False,
        allow_network=False,
    )
    assert restored["status"] == "READY"
    assert restored["branch"] == "feat/example"
    assert restored["source_dirty"] is False


def test_bootstrap_missing_reference_is_offline_failure_with_retained_evidence(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    revision, _ = repository(root, with_reference=False)
    packet = task_packet(root, git(root, "rev-parse", "HEAD").stdout.strip())
    target = root / "build/agent-worktrees/demo"
    with pytest.raises(RuntimeError, match="network fallback is disabled"):
        bootstrap_worktree(
            root, packet, "feat/example", ["example"], execute=True, create=True, allow_network=False
        )
    document = json.loads((target / "build/tasks/demo/bootstrap.json").read_text(encoding="utf-8"))
    assert document["status"] == "FAILED"
    assert document["sources"] == []
    assert target.exists()
    assert not (target / "rtl/managed/example/dependency.txt").exists()


def test_bootstrap_rejects_dirty_or_mismatched_reference(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    revision, reference = repository(root)
    packet = task_packet(root, git(root, "rev-parse", "HEAD").stdout.strip())
    (reference / "dependency.txt").write_text("local change\n", encoding="utf-8")
    with pytest.raises(RuntimeError, match="local changes"):
        bootstrap_worktree(
            root, packet, "feat/example", ["example"], execute=True, create=True, allow_network=False
        )
    assert (reference / "dependency.txt").read_text(encoding="utf-8") == "local change\n"

    git(reference, "remote", "set-url", "origin", "https://example.invalid/other.git")
    with pytest.raises(RuntimeError, match="remote mismatch"):
        ensure_git_repo(LOCKED_URL, tmp_path / "new-copy", revision, reference=reference)
    assert not (tmp_path / "new-copy").exists()


def test_bootstrap_rejects_path_and_target_conflicts(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    revision, _ = repository(root)
    packet = task_packet(root, git(root, "rev-parse", "HEAD").stdout.strip())
    task = json.loads(packet.read_text(encoding="utf-8"))
    task["execution"]["worktree"] = "build/agent-worktrees/../escape"
    packet.write_text(json.dumps(task), encoding="utf-8")
    with pytest.raises(ValueError, match="unsafe|canonical"):
        bootstrap_worktree(
            root, packet, "feat/example", [], execute=True, create=True, allow_network=False
        )
    assert not (root / "build/escape").exists()

    packet = task_packet(root, git(root, "rev-parse", "HEAD").stdout.strip())
    target = root / "build/agent-worktrees/demo"
    target.mkdir(parents=True)
    (target / "keep.txt").write_text("keep\n", encoding="utf-8")
    with pytest.raises(ValueError, match="already exists"):
        bootstrap_worktree(
            root, packet, "feat/example", [], execute=True, create=True, allow_network=False
        )
    assert (target / "keep.txt").read_text(encoding="utf-8") == "keep\n"


def test_archive_restore_checks_reference_destination_and_offline_boundaries(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    repository(root)
    base = git(root, "rev-parse", "HEAD").stdout.strip()
    reference = root / ".cache/downloads/example.tar.gz"
    target = root / "build/agent-worktrees/demo"
    target.mkdir(parents=True)
    destination = target / ".cache/downloads/example.tar.gz"
    reference.write_bytes(b"tampered archive\n")
    with pytest.raises(RuntimeError, match="reference does not match"):
        restore_archives(root, target, base, ["example-archive"], False)
    assert not destination.exists()

    reference.unlink()
    with pytest.raises(RuntimeError, match="network fallback is disabled"):
        restore_archives(root, target, base, ["example-archive"], False)
    reference.write_bytes(b"verified archive\n")
    result = restore_archives(root, target, base, ["example-archive"], False)
    assert result[0]["status"] == "VERIFIED"
    assert destination.read_bytes() == b"verified archive\n"
    destination.write_bytes(b"local mismatch\n")
    with pytest.raises(RuntimeError, match="existing archive does not match"):
        restore_archives(root, target, base, ["example-archive"], False)
    assert destination.read_bytes() == b"local mismatch\n"


def test_only_equivalent_github_ssh_and_https_identities_are_accepted(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    revision, reference = repository(root)
    git(reference, "remote", "set-url", "origin", "git@github.com:retroSoC/example.git")
    destination = tmp_path / "github-copy"
    ensure_git_repo(
        "https://github.com/retroSoC/example.git", destination, revision, reference=reference
    )
    assert (destination / "dependency.txt").read_text(encoding="utf-8") == "locked\n"
    assert git(destination, "remote", "get-url", "origin").stdout.strip() == (
        "https://github.com/retroSoC/example.git"
    )
    git(reference, "remote", "set-url", "origin", "git@github.com:other/example.git")
    with pytest.raises(RuntimeError, match="remote mismatch"):
        ensure_git_repo(
            "https://github.com/retroSoC/example.git",
            tmp_path / "other-copy",
            revision,
            reference=reference,
        )
    assert not (tmp_path / "other-copy").exists()


def test_make_entrypoint_forwards_scoped_sources_and_archives() -> None:
    completed = subprocess.run(
        [
            "make",
            "--no-print-directory",
            "-n",
            "-C",
            str(ROOT),
            "agent-worktree-start",
            "TASK=build/tasks/demo.json",
            "SOURCES=mpw hazard3",
            "ARCHIVES=serv",
            "EXECUTE=",
            "CREATE=",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    assert "--source mpw --source hazard3" in completed.stdout
    assert "--archive serv" in completed.stdout
    assert "--execute" not in completed.stdout
