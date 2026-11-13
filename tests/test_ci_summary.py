from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

from scripts.ci_summary import collect_coverage, collect_results, gate, parse_time


def result(path: Path, started: str, status: str = "passed") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "tool": "verilator",
                "started_at": started,
                "finished_at": started,
                "status": status,
                "exit_code": 0 if status == "passed" else 1,
                "command": ["sim"],
                "log": "sim.log",
            }
        ),
        encoding="utf-8",
    )


def args(root: Path, **overrides) -> SimpleNamespace:
    values = {
        "root": root,
        "build_root": root / "build",
        "since": "2026-11-08T00:00:00Z",
        "label": "test",
        "profile": "configs/ci/ihp130.mk",
        "pdk": "IHP130",
        "suite": "pr",
        "behavioral_only": True,
        "require_full_flow": False,
        "executed_formal": False,
        "require_formal": False,
        "run_status": "success",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def initialize_git(root: Path) -> None:
    import subprocess

    subprocess.run(["git", "init", "-q", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "ci@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "CI"], check=True)
    (root / "tracked.txt").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "tracked.txt"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "fixture"], check=True)


def test_results_reject_stale_evidence(tmp_path: Path) -> None:
    build = tmp_path / "build"
    result(build / "old/sim/result-sim.json", "2026-11-07T23:59:00Z")
    result(build / "current/sim/result-sim.json", "2026-11-08T00:01:00Z")
    results, issues = collect_results(build, tmp_path, parse_time("2026-11-08T00:00:00Z"))
    assert issues == []
    assert [item["path"] for item in results] == ["build/current/sim/result-sim.json"]


def test_result_preserves_peak_resource_usage(tmp_path: Path) -> None:
    path = tmp_path / "build/current/formal/ga2d/result-cover.json"
    result(path, "2026-11-08T00:01:00Z")
    document = json.loads(path.read_text(encoding="utf-8"))
    document["peak_rss_kib"] = 127214812
    path.write_text(json.dumps(document), encoding="utf-8")

    results, issues = collect_results(tmp_path / "build", tmp_path, parse_time("2026-11-08T00:00:00Z"))

    assert issues == []
    assert results[0]["peak_rss_kib"] == 127214812


def test_behavioral_summary_marks_physical_stages_not_run(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    result(tmp_path / "build/current/sim/result-sim.json", "2026-11-08T00:01:00Z")
    document = collect_coverage(args(tmp_path))
    assert document["overall_status"] == "PASS"
    coverage = {item["stage"]: item["status"] for item in document["coverage"]}
    assert coverage == {
        "behavioral": "PASS",
        "synthesis": "NOT_RUN",
        "netlist_simulation": "NOT_RUN",
        "sta": "NOT_RUN",
        "formal": "NOT_RUN",
    }


def test_missing_or_failed_current_results_cannot_pass(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    missing = collect_coverage(args(tmp_path))
    assert missing["overall_status"] == "FAIL"
    result(tmp_path / "build/current/sim/result-sim.json", "2026-11-08T00:01:00Z", "failed")
    failed = collect_coverage(args(tmp_path))
    assert failed["overall_status"] == "FAIL"


def test_full_flow_requirement_fails_closed_on_missing_stages(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    result(tmp_path / "build/current/sim/result-sim.json", "2026-11-08T00:01:00Z")
    document = collect_coverage(
        args(tmp_path, behavioral_only=False, require_full_flow=True)
    )
    assert document["overall_status"] == "FAIL"


def test_gate_supports_only_explicitly_optional_skips() -> None:
    document = gate(["impact=success", "fast=success", "fixtures=skipped"], {"fixtures"}, "quality")
    assert document["overall_status"] == "PASS"
    document = gate(["impact=success", "fast=success", "fixtures=skipped"], set(), "quality")
    assert document["overall_status"] == "FAIL"
    assert document["failed_jobs"] == ["fixtures"]


def test_formal_summary_requires_actual_solver_result(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    path = tmp_path / "build/current/formal/uart/prove/result-prove.json"
    result(path, "2026-11-08T00:01:00Z")
    document = json.loads(path.read_text(encoding="utf-8"))
    document["tool"] = "formal-sby-prove"
    path.write_text(json.dumps(document), encoding="utf-8")

    proof_result = collect_coverage(args(tmp_path, behavioral_only=False, executed_formal=True, require_formal=True))
    assert proof_result["overall_status"] == "PASS"
    coverage = {item["stage"]: item["status"] for item in proof_result["coverage"]}
    assert coverage["behavioral"] == "NOT_RUN"
    assert coverage["formal"] == "PASS"
    assert coverage["synthesis"] == "NOT_RUN"

    path.unlink()
    missing = collect_coverage(args(tmp_path, behavioral_only=False, executed_formal=True, require_formal=True))
    assert missing["overall_status"] == "FAIL"
    assert any(item["stage"] == "formal" and item["status"] == "NOT_RUN" for item in missing["coverage"])


def test_existing_result_schemas_are_accepted_without_weakening_verdict(tmp_path: Path) -> None:
    initialize_git(tmp_path)
    debug = tmp_path / "build/current/sim/verilator/debug/result-debug-sim.json"
    debug.parent.mkdir(parents=True, exist_ok=True)
    debug.write_text(json.dumps({"status": "passed", "started_at": "2026-11-08T00:01:00Z"}), encoding="utf-8")
    check = tmp_path / "build/current/sim/verilator/result-sim-check.json"
    check.write_text(json.dumps({"flow_status": "passed", "status": "passed"}), encoding="utf-8")

    document = collect_coverage(args(tmp_path))
    assert document["overall_status"] == "PASS"
    assert document["issues"] == []
    assert any(item["time_basis"] == "mtime" for item in document["results"])

    check.write_text(json.dumps({"flow_status": "failed", "status": "failed"}), encoding="utf-8")
    document = collect_coverage(args(tmp_path))
    assert document["overall_status"] == "FAIL"
    assert any(item["stage"] == "behavioral" and item["status"] == "FAIL" for item in document["coverage"])
