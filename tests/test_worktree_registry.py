from __future__ import annotations

import json
import subprocess
from pathlib import Path

from scripts.worktree_registry import reconcile_worktrees


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def make_repo(root: Path) -> None:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    git(root, "config", "user.email", "registry@example.invalid")
    git(root, "config", "user.name", "Registry")
    (root / "README.md").write_text("initial\n", encoding="utf-8")
    (root / ".gitignore").write_text("build/\n", encoding="utf-8")
    git(root, "add", "README.md", ".gitignore")
    git(root, "commit", "-qm", "initial")
    git(root, "checkout", "-qb", "dev")
    git(root, "checkout", "-qb", "feat/example")
    (root / "feature.txt").write_text("feature\n", encoding="utf-8")
    git(root, "add", "feature.txt")
    git(root, "commit", "-qm", "feature")
    git(root, "checkout", "dev")
    git(root, "merge", "--no-ff", "-m", "merge feature", "feat/example")
    git(root, "update-ref", "refs/remotes/origin/dev", "dev")
    linked = root / "build/agent-worktrees/example"
    linked.parent.mkdir(parents=True)
    git(root, "worktree", "add", str(linked), "feat/example")


def test_registry_dry_run_then_cleans_merged_branch(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    dry_run = reconcile_worktrees(root)
    assert dry_run["execution"] == "dry-run"
    assert dry_run["actions"] == []
    record = next(item for item in dry_run["worktrees"] if item["path"] == str(linked))
    assert record["status"] == "ELIGIBLE"
    assert record["cleanup_eligible"] is True
    assert linked.exists()

    completed = reconcile_worktrees(root, execute=True)
    assert completed["actions"][0]["status"] == "CLEANED"
    assert not linked.exists()
    assert subprocess.run(["git", "-C", str(root), "show-ref", "--verify", "--quiet", "refs/heads/feat/example"], check=False).returncode == 1


def test_registry_preserves_artifacts_before_cleanup(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    packet = linked / "build/tasks/demo/task.json"
    packet.parent.mkdir(parents=True)
    packet.write_text(json.dumps({"task_id": "demo"}), encoding="utf-8")
    result = linked / "build/result.json"
    result.write_text('{"status": "passed"}\n', encoding="utf-8")

    completed = reconcile_worktrees(root, execute=True)
    assert completed["actions"][0]["status"] == "CLEANED"
    preserved = root / "build/agent-artifacts/demo"
    assert json.loads((preserved / "result.json").read_text(encoding="utf-8"))["status"] == "passed"
    manifest = json.loads((preserved / "artifact-manifest.json").read_text(encoding="utf-8"))
    assert manifest["source_worktree"] == str(linked)
    assert manifest["file_count"] == 2
    assert manifest["evidence_files"][0]["sha256"]
    assert not linked.exists()


def test_registry_preserves_dirty_unmerged_and_detached_worktrees(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    (linked / "dirty.txt").write_text("keep\n", encoding="utf-8")
    unmerged = root / "build/agent-worktrees/unmerged"
    git(root, "checkout", "dev")
    git(root, "checkout", "-qb", "feat/unmerged")
    (root / "unmerged.txt").write_text("unmerged\n", encoding="utf-8")
    git(root, "add", "unmerged.txt")
    git(root, "commit", "-qm", "unmerged")
    git(root, "checkout", "dev")
    git(root, "worktree", "add", str(unmerged), "feat/unmerged")
    detached = root / "build/agent-worktrees/detached"
    git(root, "worktree", "add", "--detach", str(detached), "dev")

    document = reconcile_worktrees(root, execute=True)
    statuses = {Path(item["path"]).name: item["status"] for item in document["worktrees"]}
    assert statuses["example"] == "DIRTY"
    assert statuses["unmerged"] == "UNMERGED"
    assert statuses["detached"] == "DETACHED"
    assert document["actions"] == []
    assert (linked / "dirty.txt").is_file()
    assert unmerged.exists()
    assert detached.exists()


def test_registry_preserves_noncanonical_worktree(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    external = root.parent / "external"
    git(root, "branch", "feat/external", "dev")
    git(root, "worktree", "add", str(external), "feat/external")
    document = reconcile_worktrees(root, execute=True)
    record = next(item for item in document["worktrees"] if item["path"] == str(external))
    assert record["status"] == "NON_CANONICAL"
    assert record["cleanup_eligible"] is False
    assert external.exists()
    assert git(root, "show-ref", "--verify", "--quiet", "refs/heads/feat/external").returncode == 0


def test_registry_keeps_unregistered_orphan_directory(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    orphan = root / "build/agent-worktrees/orphan"
    orphan.mkdir(parents=True)
    (orphan / "evidence.json").write_text("{}\n", encoding="utf-8")
    document = reconcile_worktrees(root, execute=True)
    record = next(item for item in document["worktrees"] if item["path"] == str(orphan))
    assert record["status"] == "ORPHAN_DIRECTORY"
    assert record["cleanup_eligible"] is False
    assert (orphan / "evidence.json").is_file()


def test_registry_can_reconcile_only_the_selected_branch(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    other = root / "build/agent-worktrees/other"
    git(root, "branch", "feat/other", "dev")
    git(root, "worktree", "add", str(other), "feat/other")
    document = reconcile_worktrees(root, execute=True, only_branch="feat/example")
    assert [action["branch"] for action in document["actions"]] == ["feat/example"]
    assert not linked.exists()
    assert other.exists()
    assert git(root, "show-ref", "--verify", "--quiet", "refs/heads/feat/other").returncode == 0
