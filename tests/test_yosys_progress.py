from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.yosys_progress import analyze


def initialize_git(root: Path) -> str:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "ci@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "CI"], check=True)
    (root / "tracked.txt").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "tracked.txt"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "fixture"], check=True)
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def test_counts_iterations_without_claiming_nonconvergence(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    log = tmp_path / "yosys.log"
    lines = ["[1.0] 44.1. Executing OTHER pass"]
    for iteration in range(1, 168):
        if iteration == 9:
            lines.append("[10.0] 45.9. Rerunning OPT passes. (Maybe there is more to do..)")
            continue
        pass_name = "OPT_DFF" if iteration % 2 else "OPT_EXPR"
        lines.append(f"[{iteration + 1}.0] 45.{iteration}. Executing {pass_name} pass")
    lines.extend(["[168.0] Removed 3 cells.", "[168.5] Removed a total of 4 cells.", "[169.0] Removed 0 cells."])
    log.write_text("\n".join(lines) + "\n", encoding="utf-8")
    revision = "a" * 40
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"repository": {"commit": revision, "dirty": False}}), encoding="utf-8")
    result = tmp_path / "result-synth.json"
    result.write_text(json.dumps({"status": "failed", "exit_code": 124, "duration_seconds": 10800}), encoding="utf-8")

    document = analyze(log, result=result, manifest=manifest, root=tmp_path)

    metrics = document["metrics"]
    assert metrics["step_count"] == 167
    assert metrics["executing_pass_count"] == 166
    assert metrics["rerun_marker_count"] == 1
    assert metrics["first_step"] == 1
    assert metrics["last_step"] == 167
    assert metrics["elapsed_seconds"] == 166.0
    assert metrics["pass_counts"] == {"OPT_DFF": 83, "OPT_EXPR": 83}
    assert metrics["phase_complete"] is False
    assert metrics["removed_cell_events"] == 2
    assert metrics["removed_cells_reported"] == 7
    assert document["synthesis"]["exit_code"] == 124
    assert document["source"] == {
        "revision": revision,
        "dirty": False,
        "matches_worktree": False,
        "manifest": str(manifest),
    }
    assert "cannot be inferred" in document["issues"][0]


def test_detects_a_subsequent_phase_and_summary_failure(tmp_path: Path) -> None:
    log = tmp_path / "yosys.log"
    log.write_text(
        "[10.0] 45.1. Executing OPT_EXPR pass\n[20.0] 46.1. Executing TECHMAP pass\n",
        encoding="utf-8",
    )
    summary = tmp_path / "summary.json"
    summary.write_text(
        json.dumps({"results": [{"tool": "yosys", "status": "failed", "exit_code": 124}]}),
        encoding="utf-8",
    )
    document = analyze(log, summary=summary)
    assert document["metrics"]["phase_complete"] is True
    assert document["synthesis"]["exit_code"] == 124
    assert document["issues"] == []


def test_requires_matching_phase_and_rejects_conflicting_inputs(tmp_path: Path) -> None:
    log = tmp_path / "yosys.log"
    log.write_text("[1.0] 44.1. Executing OTHER pass\n", encoding="utf-8")
    with pytest.raises(ValueError, match="no Yosys progress records"):
        analyze(log)
    with pytest.raises(ValueError, match="not both"):
        analyze(log, result=tmp_path / "result.json", summary=tmp_path / "summary.json")


def test_source_revision_is_bound_to_the_manifest_not_the_current_head(tmp_path: Path) -> None:
    revision = initialize_git(tmp_path)
    log = tmp_path / "yosys.log"
    log.write_text("[1.0] 45.1. Executing OPT_EXPR pass\n[2.0] 46.1. Executing TECHMAP pass\n", encoding="utf-8")
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"repository": {"commit": revision, "dirty": False}}), encoding="utf-8")

    document = analyze(log, manifest=manifest, root=tmp_path)

    assert document["source"]["revision"] == revision
    assert document["source"]["matches_worktree"] is True
