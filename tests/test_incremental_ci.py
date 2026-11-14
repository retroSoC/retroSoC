from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.incremental_ci import (
    EvidenceMissing,
    evaluate,
    evidence_from_run,
    load_policy,
    select_previous_quality_run,
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


def test_run_artifact_revision_mismatch_is_rejected(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    monkeypatch.setattr(
        "scripts.incremental_ci.gh_json",
        lambda arguments: {"id": 124, "name": "quality", "head_sha": base, "conclusion": "success", "run_attempt": 1},
    )
    monkeypatch.setattr("scripts.incremental_ci.required_check_contexts", lambda repository, branch, root: ["quality-gate"])
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            {"id": 1, "name": "quality-gate", "status": "COMPLETED", "conclusion": "success"}
        ] if key == "check_runs" else [],
    )

    def download(command, **kwargs):
        destination = Path(command[command.index("--dir") + 1])
        destination.mkdir(parents=True)
        mismatched = previous(base)
        mismatched["source_revision"] = "0" * 40
        (destination / "summary.json").write_text(json.dumps(mismatched), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", download)
    with pytest.raises(ValueError, match="source revision differs"):
        evidence_from_run(root, "retroSoC/retroSoC", "dev", base, 124)


def quality_run(identifier: int, head: str, created: str, pr: int = 7, conclusion: str = "success") -> dict:
    return {
        "id": identifier,
        "name": "quality",
        "event": "pull_request",
        "status": "completed",
        "conclusion": conclusion,
        "run_attempt": 1,
        "head_sha": head,
        "created_at": created,
        "pull_requests": [{"number": pr}],
    }


def test_selects_only_an_earlier_successful_run_from_the_same_pr(monkeypatch: pytest.MonkeyPatch) -> None:
    head = "a" * 40
    current = quality_run(200, head, "2026-11-01T03:00:00Z")
    monkeypatch.setattr("scripts.incremental_ci.gh_json", lambda arguments: current)
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            quality_run(199, "b" * 40, "2026-11-01T02:00:00Z"),
            quality_run(198, "c" * 40, "2026-11-01T01:00:00Z"),
            current,
            quality_run(197, "d" * 40, "2026-11-01T02:30:00Z", pr=8),
            quality_run(196, "e" * 40, "2026-11-01T02:45:00Z", conclusion="failure"),
            quality_run(201, "f" * 40, "2026-11-01T04:00:00Z"),
        ],
    )
    result = select_previous_quality_run("retroSoC/retroSoC", 7, 200, head)
    assert result["selected_run_id"] == 199
    assert result["selected_head_sha"] == "b" * 40
    assert result["current_head_sha"] == head
    assert 196 not in result["candidate_run_ids"]
    assert 197 not in result["candidate_run_ids"]
    assert 201 not in result["candidate_run_ids"]


def test_history_selection_rejects_ambiguity_and_current_head_mismatch(monkeypatch: pytest.MonkeyPatch) -> None:
    current = quality_run(200, "a" * 40, "2026-11-01T03:00:00Z")
    monkeypatch.setattr("scripts.incremental_ci.gh_json", lambda arguments: current)
    with pytest.raises(ValueError, match="differs"):
        select_previous_quality_run("retroSoC/retroSoC", 7, 200, "b" * 40)
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            quality_run(198, "b" * 40, "2026-11-01T02:00:00Z"),
            quality_run(199, "c" * 40, "2026-11-01T02:00:00Z"),
        ],
    )
    with pytest.raises(EvidenceMissing, match="ambiguous"):
        select_previous_quality_run("retroSoC/retroSoC", 7, 200, "a" * 40)


def test_workflow_identity_binds_pr_head_and_evaluated_merge_revision(repo: tuple[Path, str]) -> None:
    root, base = repo
    (root / "docs/guide.md").write_text("documentation only\n", encoding="utf-8")
    git(root, "add", "docs/guide.md")
    git(root, "commit", "-qm", "docs")
    current_head = git(root, "rev-parse", "HEAD")
    previous_merge = git(root, "commit-tree", f"{base}^{{tree}}", "-p", base, "-m", "previous merge")
    assert previous_merge != base
    evidence = previous(previous_merge)
    evidence.update(
        workflow_head_sha=base,
        workflow_run_id=100,
        run_attempt=1,
        pr_number=7,
    )
    result = evaluate(
        root,
        base,
        current_head,
        evidence,
        "pull_request",
        False,
        ["quality-gate"],
        workflow_head=current_head,
        workflow_run_id=101,
        pr_number=7,
    )
    assert result["decision"] == "SHADOW_REUSE_CANDIDATE"
    assert result["previous"]["source_revision"] == previous_merge
    assert result["previous"]["workflow_head_sha"] == base

    for field, value in (
        ("pr_number", 8),
        ("workflow_run_id", 101),
        ("workflow_head_sha", "f" * 40),
    ):
        invalid = dict(evidence)
        invalid[field] = value
        with pytest.raises(ValueError):
            evaluate(
                root,
                base,
                current_head,
                invalid,
                "pull_request",
                False,
                ["quality-gate"],
                workflow_head=current_head,
                workflow_run_id=101,
                pr_number=7,
            )
    missing = dict(evidence)
    missing["source_revision"] = "f" * 40
    with pytest.raises(EvidenceMissing, match="unavailable"):
        evaluate(
            root,
            base,
            current_head,
            missing,
            "pull_request",
            False,
            ["quality-gate"],
            workflow_head=current_head,
            workflow_run_id=101,
            pr_number=7,
        )


def test_workflow_bound_run_artifact_has_matching_identity(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    run = quality_run(321, base, "2026-11-01T02:00:00Z")
    monkeypatch.setattr("scripts.incremental_ci.gh_json", lambda arguments: run)
    monkeypatch.setattr("scripts.incremental_ci.required_check_contexts", lambda repository, branch, root: ["quality-gate"])
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            {"id": 1, "name": "quality-gate", "status": "COMPLETED", "conclusion": "success"}
        ] if key == "check_runs" else [],
    )

    real_run = subprocess.run

    def download(command, **kwargs):
        if command[0] != "gh":
            return real_run(command, **kwargs)
        destination = Path(command[command.index("--dir") + 1])
        destination.mkdir(parents=True)
        document = previous(base)
        document.update(
            workflow_head_sha=base,
            workflow_run_id=321,
            run_attempt=1,
            pr_number=7,
        )
        (destination / "summary.json").write_text(json.dumps(document), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", download)
    evidence = evidence_from_run(
        root,
        "retroSoC/retroSoC",
        "dev",
        base,
        321,
        require_workflow_identity=True,
        pr_number=7,
    )
    assert evidence["workflow_head_sha"] == base
    assert evidence["run_attempt"] == 1
    result = evaluate(
        root,
        base,
        base,
        evidence,
        "pull_request",
        False,
        workflow_head=base,
        workflow_run_id=322,
        pr_number=7,
    )
    assert result["decision"] == "SHADOW_REUSE_CANDIDATE"


def test_fan_in_binds_optional_workflow_identity(repo: tuple[Path, str]) -> None:
    from scripts.pytest_shards import bind_workflow_identity

    root, base = repo
    document = {"source_revision": base}
    identity = {
        "workflow_head_sha": base,
        "workflow_run_id": 321,
        "run_attempt": 1,
        "pr_number": 7,
    }
    assert bind_workflow_identity(document, root, identity)["pr_number"] == 7
    with pytest.raises(ValueError, match="incomplete"):
        bind_workflow_identity(document, root, {"workflow_head_sha": base})
    with pytest.raises(ValueError, match="ancestor"):
        bind_workflow_identity(
            {"source_revision": base},
            root,
            {**identity, "workflow_head_sha": "f" * 40},
        )


def test_history_workflow_binds_run_without_skipping_full_jobs() -> None:
    import yaml

    workflow = yaml.load(
        (ROOT / ".github/workflows/quality.yml").read_text(encoding="utf-8"),
        Loader=yaml.BaseLoader,
    )
    shadow = workflow["jobs"]["incremental-shadow"]
    run = next(step for step in shadow["steps"] if step["name"] == "Evaluate shadow reuse without skipping full jobs")
    assert "--auto-previous" in run["run"]
    assert "--workflow-head" in run["run"]
    assert "--workflow-run" in run["run"]
    assert "--pr-number" in run["run"]
    assert "--execute" not in run["run"]
    fan_in = next(
        step
        for step in workflow["jobs"]["fixtures-fan-in"]["steps"]
        if step["name"] == "Verify complete fixture coverage"
    )
    assert "--workflow-head" in fan_in["run"]
    assert "--workflow-run" in fan_in["run"]
    assert "--run-attempt" in fan_in["run"]
    assert "--pr-number" in fan_in["run"]
    gate = next(
        step
        for step in workflow["jobs"]["quality-gate"]["steps"]
        if step["name"] == "Aggregate quality verdict"
    )
    assert "--allow-skip incremental-shadow" not in gate["run"]


def test_history_selection_requires_current_pr_and_allows_no_candidates(monkeypatch: pytest.MonkeyPatch) -> None:
    current = quality_run(200, "a" * 40, "2026-11-01T03:00:00Z")
    monkeypatch.setattr("scripts.incremental_ci.gh_json", lambda arguments: current)
    monkeypatch.setattr("scripts.incremental_ci.paginated_check_data", lambda endpoint, key: [])
    result = select_previous_quality_run("retroSoC/retroSoC", 7, 200, "a" * 40)
    assert result["selected_run_id"] is None
    current["pull_requests"] = [{"number": 8}]
    with pytest.raises(ValueError, match="does not belong"):
        select_previous_quality_run("retroSoC/retroSoC", 7, 200, "a" * 40)


def test_workflow_bound_artifact_requires_complete_identity(repo: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> None:
    root, base = repo
    run = quality_run(321, base, "2026-11-01T02:00:00Z")
    monkeypatch.setattr("scripts.incremental_ci.gh_json", lambda arguments: run)
    monkeypatch.setattr("scripts.incremental_ci.required_check_contexts", lambda repository, branch, root: ["quality-gate"])
    monkeypatch.setattr(
        "scripts.incremental_ci.paginated_check_data",
        lambda endpoint, key: [
            {"id": 1, "name": "quality-gate", "status": "COMPLETED", "conclusion": "success"}
        ] if key == "check_runs" else [],
    )

    def download(command, **kwargs):
        destination = Path(command[command.index("--dir") + 1])
        destination.mkdir(parents=True)
        (destination / "summary.json").write_text(json.dumps(previous(base)), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", download)
    with pytest.raises(EvidenceMissing, match="workflow identity"):
        evidence_from_run(
            root,
            "retroSoC/retroSoC",
            "dev",
            base,
            321,
            require_workflow_identity=True,
            pr_number=7,
        )
