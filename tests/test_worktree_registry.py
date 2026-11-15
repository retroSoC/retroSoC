from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.worktree_registry import reconcile_worktrees


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def make_repo(root: Path) -> None:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    git(root, "config", "user.email", "registry@example.invalid")
    git(root, "config", "user.name", "Registry")
    (root / "README.md").write_text("initial\n", encoding="utf-8")
    (root / ".gitignore").write_text("build/\n", encoding="utf-8")
    (root / "quality").mkdir()
    shutil.copyfile(
        Path(__file__).resolve().parents[1] / "quality/artifact-retention.json",
        root / "quality/artifact-retention.json",
    )
    git(root, "add", "README.md", ".gitignore", "quality/artifact-retention.json")
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


def test_registry_classifies_evidence_and_rebuildable_outputs(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    payloads = {
        "result.json": b'{"status":"passed"}\n',
        "run.log": b"SIM_TEST_PASS\n",
        "agent-evals/smoke/case/worktrees/replica/blob.bin": b"workspace" * 100,
        "ccache/object": b"cache" * 100,
        "engineering/mini-yosys-deferred-test/state/input.il": b"deferred evidence",
        "unknown.bin": b"retain unknown data",
    }
    for relative, payload in payloads.items():
        path = linked / "build" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)

    dry_run = reconcile_worktrees(root)
    record = next(item for item in dry_run["worktrees"] if item["path"] == str(linked))
    assert record["artifact_inventory"]["file_count"] == len(payloads)
    assert record["artifact_inventory"]["retained_file_count"] == 4
    completed = reconcile_worktrees(root, execute=True)
    assert completed["actions"][0]["status"] == "CLEANED"
    preserved = root / "build/agent-artifacts/feat-example"
    manifest = json.loads((preserved / "artifact-manifest.json").read_text(encoding="utf-8"))
    assert manifest["status"] == "PRESERVED"
    assert manifest["retained_bytes"] == sum(len(payloads[name]) for name in (
        "result.json", "run.log", "engineering/mini-yosys-deferred-test/state/input.il", "unknown.bin"
    ))
    assert (preserved / "result.json").is_file()
    assert (preserved / "run.log").is_file()
    assert (preserved / "engineering/mini-yosys-deferred-test/state/input.il").is_file()
    assert (preserved / "unknown.bin").is_file()
    assert not (preserved / "agent-evals/smoke/case/worktrees/replica/blob.bin").exists()
    assert not (preserved / "ccache/object").exists()
    categories = {item["class"]: item for item in manifest["categories"]}
    assert categories["cache"]["rebuildable"] is True
    assert categories["evaluation_workspace"]["retained_file_count"] == 0
    deferred = next(item for item in manifest["retained_files"] if item["path"].endswith("input.il"))
    assert deferred["on_expiry"] == "retain_until_gap_resolved"


def test_registry_capacity_and_destination_conflict_preserve_worktree(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from types import SimpleNamespace

    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    (linked / "build").mkdir()
    (linked / "build/result.json").write_text('{"status":"passed"}\n', encoding="utf-8")
    monkeypatch.setattr(
        "scripts.artifact_lifecycle.shutil.disk_usage",
        lambda path: SimpleNamespace(free=0),
    )
    result = reconcile_worktrees(root, execute=True)
    assert result["actions"][0]["status"] == "PRESERVED"
    assert "insufficient artifact capacity" in result["actions"][0]["warning"]
    assert linked.exists()
    assert not (root / "build/agent-artifacts/feat-example").exists()

    monkeypatch.undo()
    destination = root / "build/agent-artifacts/feat-example"
    destination.mkdir(parents=True)
    (destination / "keep.txt").write_text("keep\n", encoding="utf-8")
    result = reconcile_worktrees(root, execute=True)
    assert result["actions"][0]["status"] == "PRESERVED"
    assert linked.exists()
    assert (destination / "keep.txt").is_file()


def test_registry_rejects_artifact_symlink_escape(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    outside = tmp_path / "outside.txt"
    outside.write_text("not an artifact\n", encoding="utf-8")
    (linked / "build").mkdir()
    (linked / "build/result.json").symlink_to(outside)
    result = reconcile_worktrees(root, execute=True)
    record = next(item for item in result["worktrees"] if item["path"] == str(linked))
    assert record["cleanup_eligible"] is False
    assert "manual review" in record["artifact_issue"]
    assert result["actions"] == []
    assert linked.exists()
    assert outside.read_text(encoding="utf-8") == "not an artifact\n"


def test_registry_skips_only_rebuildable_workspace_symlinks(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    make_repo(root)
    linked = root / "build/agent-worktrees/example"
    workspace = linked / "build/agent-evals/smoke/case-01-workspace/rtl/managed"
    workspace.mkdir(parents=True)
    external = tmp_path / "external-managed"
    external.mkdir()
    (external / "keep.txt").write_text("keep\n", encoding="utf-8")
    (workspace / "mpw").symlink_to(external, target_is_directory=True)

    dry_run = reconcile_worktrees(root)
    record = next(item for item in dry_run["worktrees"] if item["path"] == str(linked))
    assert record["cleanup_eligible"] is True
    assert record["artifact_inventory"]["retained_file_count"] == 0
    assert record["artifact_inventory"]["skipped_symlinks"][0]["class"] == "evaluation_workspace"
    completed = reconcile_worktrees(root, execute=True)
    assert completed["actions"][0]["status"] == "CLEANED"
    assert (external / "keep.txt").read_text(encoding="utf-8") == "keep\n"
    manifest_path = root / "build/agent-artifacts/feat-example/artifact-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["retained_file_count"] == 0
    assert manifest["skipped_symlinks"][0]["path"].endswith("rtl/managed/mpw")
