from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

from scripts.check_contribution import (  # noqa: E402
    validate_ownership,
    validate_pull_request,
    validate_release,
)


def test_pull_request_rules_accept_topic_and_release_integration() -> None:
    assert validate_pull_request("dev", "feat/agent-control", "feat(agents): add task contract", ["feat(agents): add task contract"]) == []
    assert validate_pull_request("main", "dev", "chore(release): integrate dev", ["Merge branch 'dev'"]) == []
    assert validate_pull_request("dev", "dependabot/pip/requirements/dev/pytest-9", "build(deps): bump pytest", ["build(deps): bump pytest"]) == []


def test_pull_request_rules_reject_invalid_base_branch_and_subjects() -> None:
    issues = validate_pull_request("main", "feat/unreviewed", "implement everything", ["wip"])
    assert "main accepts only the controlled dev release-integration branch" in issues
    assert "pull request title must use type(scope): summary" in issues
    assert "invalid commit subject: wip" in issues


def test_ownership_matches_codeowners_and_reports_backup_gaps() -> None:
    issues, warnings = validate_ownership(ROOT)
    assert issues == []
    assert len(warnings) == 14


def release_repository(tmp_path: Path, required_stages: list[str] | None = None) -> tuple[Path, str]:
    root = tmp_path / "release"
    root.mkdir()
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "release@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "Release"], check=True)
    subprocess.run(["git", "-C", str(root), "checkout", "-qb", "main"], check=True)
    (root / "dependencies").mkdir()
    (root / "quality").mkdir()
    (root / "dependencies/dependencies.lock.json").write_text('{"locked": true}\n', encoding="utf-8")
    lock_digest = hashlib.sha256((root / "dependencies/dependencies.lock.json").read_bytes()).hexdigest()
    ownership = {
        "schema_version": 1,
        "review_policy": {
            "mode": "sole_maintainer",
            "self_approval_allowed": True,
            "agent_approval_allowed": False,
            "required_approving_review_count": 0,
            "require_code_owner_reviews": False,
        },
        "entries": [{"path": "/Makefile", "owners": ["@maksyuki"], "backup_owners": []}],
    }
    (root / "quality/ownership.json").write_text(json.dumps(ownership, indent=2) + "\n", encoding="utf-8")
    candidate = {
        "schema_version": 1,
        "version": "v1.2.3",
        "release_branch": "main",
        "dependency_lock_sha256": lock_digest,
        "approval": {
            "approved_by": "@maksyuki",
            "reference": "https://github.com/retroSoC/retroSoC/pull/227",
        },
        "required_stages": required_stages or ["behavioral"],
        "checks": [{"name": "quality", "stages": ["behavioral"]}],
        "accepted_gaps": [
            {"stage": "physical", "reason": "Source package is not a physical signoff", "approved_by": "@maksyuki"}
        ],
    }
    (root / "quality/release-candidate.json").write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "chore(release): candidate"], check=True)
    subprocess.run(["git", "-C", str(root), "tag", "v1.2.3"], check=True)
    revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    return root, revision


def release_lookups(revision: str):
    runs = [
        {
            "id": 42,
            "name": "quality",
            "head_sha": revision,
            "status": "completed",
            "conclusion": "success",
            "html_url": "https://github.com/retroSoC/retroSoC/actions/runs/42",
            "event": "push",
        }
    ]
    approval = {
        "state": "MERGED",
        "mergedAt": "2026-11-08T00:00:00Z",
        "mergeCommit": {"oid": revision},
        "reviewDecision": "APPROVED",
        "reviews": [{"state": "APPROVED", "author": {"login": "maksyuki"}}],
    }
    return runs, approval


def test_release_validation_binds_tag_runs_and_human_approval(tmp_path: Path) -> None:
    root, revision = release_repository(tmp_path)
    runs, approval = release_lookups(revision)
    issues, verified = validate_release(
        root,
        "v1.2.3",
        root / "quality/release-candidate.json",
        "main",
        "retroSoC/retroSoC",
        run_lookup=lambda _repository, _revision: runs,
        approval_lookup=lambda _repository, _reference: approval,
    )
    assert issues == []
    assert verified[0]["id"] == 42
    assert verified[0]["head_sha"] == revision


def test_release_validation_rejects_missing_required_stage(tmp_path: Path) -> None:
    root, revision = release_repository(tmp_path, ["behavioral", "synthesis"])
    runs, approval = release_lookups(revision)
    issues, _ = validate_release(
        root,
        "v1.2.3",
        root / "quality/release-candidate.json",
        "main",
        "retroSoC/retroSoC",
        run_lookup=lambda _repository, _revision: runs,
        approval_lookup=lambda _repository, _reference: approval,
    )
    assert "required release stage has no successful evidence: synthesis" in issues


def test_release_validation_rejects_stale_runs_and_unapproved_review(tmp_path: Path) -> None:
    root, revision = release_repository(tmp_path)
    runs, approval = release_lookups(revision)
    runs[0]["head_sha"] = "0" * 40
    approval["reviewDecision"] = "CHANGES_REQUESTED"
    issues, verified = validate_release(
        root,
        "v1.2.3",
        root / "quality/release-candidate.json",
        "main",
        "retroSoC/retroSoC",
        run_lookup=lambda _repository, _revision: runs,
        approval_lookup=lambda _repository, _reference: approval,
    )
    assert f"release workflow quality has no successful run at {revision}" in issues
    assert "sole-maintainer release PR must not have changes requested" in issues
    assert verified == []


def test_release_validation_rejects_modified_candidate_and_moved_main(tmp_path: Path) -> None:
    root, revision = release_repository(tmp_path)
    runs, approval = release_lookups(revision)
    candidate = root / "quality/release-candidate.json"
    document = json.loads(candidate.read_text(encoding="utf-8"))
    document["version"] = "v9.9.9"
    candidate.write_text(json.dumps(document), encoding="utf-8")
    (root / "dependencies/dependencies.lock.json").write_text('{"locked": false}\n', encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "move main"], check=True)
    issues, _ = validate_release(
        root,
        "v1.2.3",
        candidate,
        "main",
        "retroSoC/retroSoC",
        run_lookup=lambda _repository, _revision: runs,
        approval_lookup=lambda _repository, _reference: approval,
    )
    assert any("does not point to the approved main head" in issue for issue in issues)
    assert "release candidate content must match the released tag" in issues
    assert "release candidate version does not match the tag" in issues
    assert "release candidate dependency lock digest is stale" in issues


def test_release_validation_accepts_sole_maintainer_without_peer_review(tmp_path: Path) -> None:
    root, revision = release_repository(tmp_path)
    runs, approval = release_lookups(revision)
    approval["reviewDecision"] = ""
    approval["reviews"] = []
    issues, verified = validate_release(
        root,
        "v1.2.3",
        root / "quality/release-candidate.json",
        "main",
        "retroSoC/retroSoC",
        run_lookup=lambda _repository, _revision: runs,
        approval_lookup=lambda _repository, _reference: approval,
    )
    assert issues == []
    assert verified[0]["id"] == 42
