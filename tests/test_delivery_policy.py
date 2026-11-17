from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from scripts.delivery_policy import (
    evaluate,
    evaluate_merge_queue,
    evaluate_metrics,
    load_policy,
    merge_group_parity,
)

ROOT = Path(__file__).resolve().parents[1]


def make_root(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    (root / "quality/metrics").mkdir(parents=True)
    shutil.copy(ROOT / "quality/delivery-policy.json", root / "quality/delivery-policy.json")
    shutil.copy(ROOT / "quality/metrics/policy.json", root / "quality/metrics/policy.json")
    (root / "configs/ci").mkdir(parents=True)
    (root / "configs/ci/ihp130.mk").write_text("SOC := MINI\n", encoding="utf-8")
    (root / ".github/workflows").mkdir(parents=True)
    policy = load_policy(root)
    for name in policy["merge_queue"]["required_workflows"]:
        (root / ".github/workflows" / name).write_text("on:\n  pull_request:\n", encoding="utf-8")
    return root


def pull(number: int, *, draft: bool = False, mergeable: str = "MERGEABLE") -> dict:
    return {
        "number": number,
        "isDraft": draft,
        "baseRefName": "dev",
        "headRefName": f"ci/example-{number}",
        "mergeable": mergeable,
        "mergeStateStatus": "UNSTABLE" if mergeable == "MERGEABLE" else "DIRTY",
        "headRepositoryOwner": {"login": "retroSoC"},
    }


def sample(index: int) -> dict:
    return {
        "source_revision": f"{index:040x}",
        "profile": "configs/ci/ihp130.mk",
        "tool_lock_sha256": "a" * 64,
        "status": "passed",
        "metrics": {
            "firmware": {"retrosoc_fw.bin": {"bytes": 1024}},
            "synthesis": {"top_area": 10.0, "top_cells": 100},
            "timing": {"wns_max": 0.5},
        },
    }


def successful_runs(count: int) -> list[dict]:
    return [
        {"id": index, "name": "quality", "conclusion": "success", "event": "push"}
        for index in range(count)
    ]


def write_baseline(root: Path, sample_document: dict) -> None:
    baseline = {
        "sample_count": 10,
        "values": {},
        "profile": sample_document["profile"],
        "tool_lock_sha256": sample_document["tool_lock_sha256"],
        "review": {"approved_by": "@maksyuki", "approved_at": "2026-11-14T00:00:00Z"},
    }
    (root / "quality/metrics/baseline.json").write_text(json.dumps(baseline), encoding="utf-8")


def test_merge_queue_requires_sustained_conflicts_and_workflow_parity(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    pulls = [pull(1, mergeable="CONFLICTING"), pull(2, mergeable="CONFLICTING"), pull(3)]
    result = evaluate_merge_queue(root, load_policy(root)["merge_queue"], pulls)
    assert result["ready_pr_count"] == 3
    assert result["conflicting_pr_count"] == 2
    assert result["decision"] == "NOT_RECOMMENDED"
    assert result["merge_group"]["supported"] is False

    for name in load_policy(root)["merge_queue"]["required_workflows"]:
        path = root / ".github/workflows" / name
        path.write_text("on:\n  merge_group:\n  pull_request:\n", encoding="utf-8")
    eligible = evaluate_merge_queue(root, load_policy(root)["merge_queue"], pulls)
    assert eligible["decision"] == "ELIGIBLE_FOR_REVIEW"
    assert eligible["changes_applied"] is False
    assert evaluate_merge_queue(root, load_policy(root)["merge_queue"], pulls[:2])["decision"] == "NOT_RECOMMENDED"


def test_merge_queue_ignores_draft_and_noncanonical_prs(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    draft = pull(1, draft=True, mergeable="CONFLICTING")
    fork = pull(2, mergeable="CONFLICTING")
    fork["headRepositoryOwner"]["login"] = "fork-owner"
    result = evaluate_merge_queue(root, load_policy(root)["merge_queue"], [draft, fork])
    assert result["ready_pr_count"] == 0
    assert result["conflicting_pr_count"] == 0
    assert result["decision"] == "NOT_RECOMMENDED"


def test_metrics_distinguishes_ci_success_from_valid_baseline_samples(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    result = evaluate_metrics(root, load_policy(root)["metrics"], successful_runs(12), [])
    assert result["successful_main_quality_run_count"] == 12
    assert result["valid_metric_sample_count"] == 0
    assert result["baseline"]["present"] is False
    assert result["decision"] == "HOLD"
    assert result["mode"] == "observe"
    assert result["changes_applied"] is False


def test_metrics_requires_ten_matching_samples_and_reviewed_baseline(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    samples = [sample(index) for index in range(1, 11)]
    write_baseline(root, samples[0])
    result = evaluate_metrics(root, load_policy(root)["metrics"], successful_runs(10), samples)
    assert result["valid_metric_sample_count"] == 10
    assert result["baseline"]["valid"] is True
    assert result["decision"] == "ELIGIBLE_FOR_REVIEW"
    assert result["mode"] == "observe"

    samples[-1]["tool_lock_sha256"] = "b" * 64
    mixed = evaluate_metrics(root, load_policy(root)["metrics"], successful_runs(10), samples)
    assert mixed["decision"] == "HOLD"
    assert any("identical locked tools" in reason for reason in mixed["reasons"])

    samples[-1]["tool_lock_sha256"] = "a" * 64
    samples[-1]["source_revision"] = samples[0]["source_revision"]
    duplicate = evaluate_metrics(root, load_policy(root)["metrics"], successful_runs(10), samples)
    assert duplicate["decision"] == "HOLD"
    assert any("must be unique" in reason for reason in duplicate["reasons"])


def test_valid_samples_without_reviewed_baseline_hold(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    result = evaluate_metrics(root, load_policy(root)["metrics"], successful_runs(10), [sample(index) for index in range(1, 11)])
    assert result["valid_metric_sample_count"] == 10
    assert result["baseline"]["valid"] is False
    assert result["decision"] == "HOLD"


def test_evaluation_is_read_only_and_contains_no_policy_changes(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    result = evaluate(root, [pull(1)], successful_runs(1), [], "test")
    assert result["evaluation_only"] is True
    assert result["policy_changes"] == []
    assert result["merge_queue"]["changes_applied"] is False
    assert result["metrics"]["changes_applied"] is False


def test_offline_cli_emits_evidence_without_mutation(tmp_path: Path) -> None:
    root = make_root(tmp_path)
    pulls_path = tmp_path / "pulls.json"
    runs_path = tmp_path / "runs.json"
    samples_path = tmp_path / "samples.json"
    pulls_path.write_text(json.dumps([pull(1, draft=True)]), encoding="utf-8")
    runs_path.write_text(json.dumps(successful_runs(1)), encoding="utf-8")
    samples_path.write_text("[]", encoding="utf-8")
    output = tmp_path / "evaluation.json"
    completed = subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/delivery_policy.py"),
            "--root",
            str(root),
            "--offline",
            "--pulls",
            str(pulls_path),
            "--runs",
            str(runs_path),
            "--samples",
            str(samples_path),
            "--output",
            str(output),
        ],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    result = json.loads(output.read_text(encoding="utf-8"))
    assert result["source"] == "offline"
    assert result["merge_queue"]["ready_pr_count"] == 0
    assert result["metrics"]["decision"] == "HOLD"


def test_current_policy_has_no_merge_queue_or_metric_gate() -> None:
    policy = load_policy(ROOT)
    assert merge_group_parity(ROOT, policy["merge_queue"]["required_workflows"])["supported"] is False
    metrics = json.loads((ROOT / "quality/metrics/policy.json").read_text(encoding="utf-8"))
    assert metrics["mode"] == "observe"
    assert not (ROOT / "quality/metrics/baseline.json").exists()
