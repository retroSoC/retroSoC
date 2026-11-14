from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.incremental_ci import (
    evaluate,
    evidence_from_run,
    load_policy,
)

ROOT = Path(__file__).resolve().parents[1]


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


def manifest() -> dict:
    return {
        "node_ids_sha256": "node-a",
        "test_count": 1,
        "pytest_version": "9.2.0",
        "tool_inputs_sha256": "tools-a",
        "policy_sha256": "policy-a",
        "durations_sha256": "durations-a",
    }


def make_repo(root: Path) -> str:
    (root / "quality").mkdir(parents=True)
    shutil.copy(ROOT / "quality/incremental-ci.json", root / "quality/incremental-ci.json")
    (root / "quality/pytest-shards.json").write_text('{"shards": 4}\n', encoding="utf-8")
    (root / "quality/pytest-durations.json").write_text('{"durations": {}}\n', encoding="utf-8")
    for directory in ("scripts", "tests", "requirements", "dependencies", "docs", ".github"):
        (root / directory).mkdir()
    (root / "scripts/tool.py").write_text("VALUE = 1\n", encoding="utf-8")
    (root / "tests/test_sample.py").write_text("def test_sample(): pass\n", encoding="utf-8")
    (root / "requirements/build.txt").write_text("build==1\n", encoding="utf-8")
    (root / "requirements/ci.txt").write_text("ci==1\n", encoding="utf-8")
    vendor = root / "vendor"
    (vendor / "doc").mkdir(parents=True)
    (vendor / "doc/datasheet.md").write_text("managed source\n", encoding="utf-8")
    git(vendor, "init", "-q")
    git(vendor, "config", "user.email", "incremental@example.invalid")
    git(vendor, "config", "user.name", "Incremental")
    git(vendor, "add", "doc/datasheet.md")
    git(vendor, "commit", "-qm", "managed source")
    vendor_revision = git(vendor, "rev-parse", "HEAD")
    lock = {
        "schema_version": 1,
        "sources": {"managed": {"destination": "vendor", "revision": vendor_revision}},
    }
    (root / "dependencies/dependencies.lock.json").write_text(json.dumps(lock), encoding="utf-8")
    (root / "Makefile").write_text("all:\n\t@true\n", encoding="utf-8")
    (root / "pyproject.toml").write_text("[tool.pytest.ini_options]\n", encoding="utf-8")
    (root / "docs/guide.md").write_text("initial\n", encoding="utf-8")
    (root / ".gitignore").write_text("build/\n", encoding="utf-8")
    git(root, "init", "-q")
    git(root, "config", "user.email", "incremental@example.invalid")
    git(root, "config", "user.name", "Incremental")
    git(root, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(vendor), "vendor")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "base")
    return git(root, "rev-parse", "HEAD")


def previous(revision: str) -> dict:
    return {
        "source_revision": revision,
        "status": "passed",
        "contexts": [{"name": "quality-gate", "status": "PASS"}],
        **manifest(),
    }


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, str]:
    root = tmp_path / "repo"
    root.mkdir()
    revision = make_repo(root)
    monkeypatch.setattr("scripts.incremental_ci.reviewed_source_paths", lambda root: [])
    monkeypatch.setattr("scripts.incremental_ci.create_plan", lambda root: manifest())
    return root, revision


def test_shadow_recommends_reuse_only_for_identical_inputs(repo: tuple[Path, str]) -> None:
    root, base = repo
    (root / "docs/guide.md").write_text("documentation only\n", encoding="utf-8")
    git(root, "add", "docs/guide.md")
    git(root, "commit", "-qm", "docs")
    result = evaluate(root, base, "HEAD", previous(base), "pull_request", False, ["quality-gate"])
    assert result["decision"] == "SHADOW_REUSE_CANDIDATE"
    assert result["current"]["fingerprint"] == result["previous"]["fingerprint"]
    assert result["changed_inputs"] == []


def test_changed_inputs_tools_config_and_test_manifest_force_full(repo: tuple[Path, str]) -> None:
    root, base = repo
    for path in ("scripts/tool.py", "dependencies/dependencies.lock.json", "quality/pytest-durations.json"):
        (root / path).write_text("changed\n", encoding="utf-8")
        git(root, "add", path)
        git(root, "commit", "-qm", f"change {path}")
        result = evaluate(root, base, "HEAD", previous(base), "pull_request", False, ["quality-gate"])
        assert result["decision"] == "RUN_FULL"
        assert "input evidence differs" in result["reason"]
        git(root, "checkout", "-q", base, "--", path)

    (root / "scripts/tool.py").write_text("VALUE = 1\n", encoding="utf-8")
    git(root, "add", "scripts/tool.py")
    git(root, "commit", "-qm", "restore tool")
    (root / "quality/pytest-shards.json").write_text('{"shards": 3}\n', encoding="utf-8")
    git(root, "add", "quality/pytest-shards.json")
    git(root, "commit", "-qm", "change shard configuration")
    result = evaluate(root, base, "HEAD", previous(base), "pull_request", False, ["quality-gate"])
    assert result["decision"] == "RUN_FULL"


def test_deleted_input_and_dirty_worktree_cannot_reuse(repo: tuple[Path, str]) -> None:
    root, base = repo
    (root / "scripts/tool.py").unlink()
    git(root, "add", "-u")
    git(root, "commit", "-qm", "delete input")
    result = evaluate(root, base, "HEAD", previous(base), "pull_request", False, ["quality-gate"])
    assert result["decision"] == "RUN_FULL"
    assert "scripts/tool.py" in result["changed_inputs"]

    (root / "scripts/tool.py").write_text("VALUE = 2\n", encoding="utf-8")
    dirty = evaluate(root, base, base, previous(base), "pull_request", False, ["quality-gate"])
    assert dirty["decision"] == "RUN_FULL"
    assert "worktree contains changes" in dirty["reason"]


def test_failed_tampered_or_missing_evidence_is_not_accepted(repo: tuple[Path, str]) -> None:
    root, base = repo
    failed = previous(base)
    failed["status"] = "failed"
    assert evaluate(root, base, base, failed, "pull_request", False, ["quality-gate"])["decision"] == "RUN_FULL"
    tampered = previous(base)
    tampered["fingerprint"] = "0" * 64
    with pytest.raises(ValueError, match="does not match its own source inputs"):
        evaluate(root, base, base, tampered, "pull_request", False, ["quality-gate"])
    missing = evaluate(root, base, base, None, "pull_request", False, ["quality-gate"])
    assert missing["decision"] == "RUN_FULL"
    assert "no historical evidence" in missing["reason"]


def test_scheduled_and_release_events_always_run_full(repo: tuple[Path, str]) -> None:
    root, base = repo
    for event in ("schedule", "workflow_dispatch", "release"):
        result = evaluate(root, base, base, previous(base), event, False, ["quality-gate"])
        assert result["decision"] == "RUN_FULL"
        assert "always require the full flow" in result["reason"]


def test_execute_requires_explicit_enablement(repo: tuple[Path, str]) -> None:
    root, base = repo
    policy_path = root / "quality/incremental-ci.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    with pytest.raises(ValueError, match="reuse is disabled"):
        evaluate(root, base, base, previous(base), "pull_request", True, ["quality-gate"])
    policy["mode"] = "execute"
    policy["enabled"] = True
    policy_path.write_text(json.dumps(policy), encoding="utf-8")
    git(root, "add", "quality/incremental-ci.json")
    git(root, "commit", "-qm", "enable reuse")
    enabled_base = git(root, "rev-parse", "HEAD")
    result = evaluate(root, enabled_base, enabled_base, previous(enabled_base), "pull_request", True, ["quality-gate"])
    assert result["decision"] == "REUSE_AUTHORIZED"


def test_github_run_and_artifact_are_bound_to_complete_green_evidence(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    monkeypatch.setattr(
        "scripts.incremental_ci.gh_json",
        lambda arguments: {
            "id": 123,
            "name": "quality",
            "head_sha": base,
            "conclusion": "success",
            "run_attempt": 1,
        },
    )
    monkeypatch.setattr("scripts.incremental_ci.required_check_contexts", lambda repository, branch, root: ["quality-gate"])
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            {"id": 1, "name": "quality-gate", "status": "COMPLETED", "conclusion": "success", "html_url": "https://example.invalid/1"}
        ] if key == "check_runs" else [],
    )

    real_run = subprocess.run

    def download(command, **kwargs):
        if command[0] != "gh":
            return real_run(command, **kwargs)
        destination = Path(command[command.index("--dir") + 1])
        destination.mkdir(parents=True)
        (destination / "summary.json").write_text(json.dumps(previous(base)), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", download)
    evidence = evidence_from_run(root, "retroSoC/retroSoC", "dev", base, 123)
    assert evidence["workflow_run_id"] == 123
    assert evidence["contexts"][0]["status"] == "PASS"
    result = evaluate(root, base, base, evidence, "pull_request", False, ["quality-gate"])
    assert result["decision"] == "SHADOW_REUSE_CANDIDATE"


def test_production_policy_is_shadow_only() -> None:
    policy = load_policy(ROOT)
    assert policy["mode"] == "shadow"
    assert policy["enabled"] is False
    assert len(policy["jobs"]) == 1
    assert policy["jobs"][0]["configuration"]["shards"] == 4


def test_input_closure_contains_real_sources(repo: tuple[Path, str]) -> None:
    from scripts.incremental_ci import tracked_inputs

    root, base = repo
    files = tracked_inputs(root, load_policy(root)["jobs"][0], base)
    assert "scripts/tool.py" in files
    assert "tests/test_sample.py" in files
    assert "dependencies/dependencies.lock.json" in files
    assert "quality/pytest-shards.json" in files


def test_changed_test_manifest_forces_full(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    changed = manifest()
    changed["node_ids_sha256"] = "node-b"
    changed["test_count"] = 2
    monkeypatch.setattr("scripts.incremental_ci.create_plan", lambda root: changed)
    result = evaluate(root, base, base, previous(base), "pull_request", False, ["quality-gate"])
    assert result["decision"] == "RUN_FULL"
    assert "test_manifest_sha256" in result["reason"]


def test_shadow_workflow_preserves_full_required_jobs() -> None:
    import yaml

    workflow = yaml.load(
        (ROOT / ".github/workflows/quality.yml").read_text(encoding="utf-8"),
        Loader=yaml.BaseLoader,
    )
    shadow = workflow["jobs"]["incremental-shadow"]
    assert shadow["if"].startswith("always()")
    run = next(step for step in shadow["steps"] if step["name"] == "Evaluate shadow reuse without skipping full jobs")
    assert "--execute" not in run["run"]
    assert "incremental-ci/shadow.json" in run["run"]
    gate = workflow["jobs"]["quality-gate"]
    assert "incremental-shadow" in gate["needs"]
    aggregate = next(step for step in gate["steps"] if step["name"] == "Aggregate quality verdict")
    assert "incremental-shadow=${{ needs.incremental-shadow.result }}" in aggregate["run"]
    assert "--allow-skip incremental-shadow" not in aggregate["run"]
    assert workflow["jobs"]["fixtures"]["strategy"]["matrix"]["shard"] == ["0", "1", "2", "3"]


def test_managed_gitlink_inputs_use_their_locked_content(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    monkeypatch.setattr(
        "scripts.incremental_ci.reviewed_source_paths",
        lambda root: ["vendor/doc/datasheet.md"],
    )
    assert evaluate(root, base, base, previous(base), "pull_request", False, ["quality-gate"])["decision"] == "SHADOW_REUSE_CANDIDATE"
    vendor = root / "vendor"
    (vendor / "doc/datasheet.md").write_text("changed managed source\n", encoding="utf-8")
    git(vendor, "add", "doc/datasheet.md")
    git(vendor, "commit", "-qm", "change managed input")
    lock_path = root / "dependencies/dependencies.lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    lock["sources"]["managed"]["revision"] = git(vendor, "rev-parse", "HEAD")
    lock_path.write_text(json.dumps(lock), encoding="utf-8")
    git(root, "add", "vendor", "dependencies/dependencies.lock.json")
    git(root, "commit", "-qm", "update managed gitlink")
    result = evaluate(root, base, "HEAD", previous(base), "pull_request", False, ["quality-gate"])
    assert result["decision"] == "RUN_FULL"
    assert "vendor" in result["changed_inputs"]
