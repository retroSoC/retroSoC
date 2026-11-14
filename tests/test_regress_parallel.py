from __future__ import annotations

import json
import subprocess
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

import pytest

from scripts.ci_summary import collect_results
from scripts.regress import (
    TINY_PROFILES,
    behavioral_only,
    run_parallel_iverilog,
    select_regression,
    split_iverilog_assembly,
)

ROOT = Path(__file__).resolve().parents[1]


def mini_commands() -> tuple:
    commands, _ = select_regression("pr", "ICS55")
    return behavioral_only(
        tuple(
            (profile, values)
            for profile, values in commands
            if profile not in TINY_PROFILES.values()
        )
    )


def test_parallel_selection_preserves_the_complete_mini_command_set() -> None:
    commands = mini_commands()
    primary, iverilog = split_iverilog_assembly(commands)
    assert len(iverilog) == 1
    assert "sim-asm" in iverilog[0][1]
    assert "SIMU=IVERILOG" in iverilog[0][1]
    assert (*primary, *iverilog) == commands


def test_parallel_groups_have_isolated_build_identities(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    primary, iverilog = split_iverilog_assembly(mini_commands())
    barrier = threading.Barrier(2)
    calls = []

    def fake_run(command, root, capture_output, environment):
        calls.append((command, environment["BUILD_TIMESTAMP"]))
        if "rtl-lint" in command or "sim-asm" in command:
            barrier.wait(timeout=5)
        return ""

    monkeypatch.setattr("scripts.regress.run_command", fake_run)
    monkeypatch.setattr("scripts.regress.self_owned_warnings", lambda root, output: [])
    result = run_parallel_iverilog(
        primary, iverilog, tmp_path, {"BUILD_TIMESTAMP": "2026-11-14-00-00"}
    )
    assert result == 0
    assert len(calls) == len(primary) + len(iverilog)
    timestamps = {
        target: timestamp
        for command, timestamp in calls
        for target in command
        if target in {"sim", "sim-asm"}
    }
    assert timestamps["sim-asm"] == "2026-11-14-00-00-iverilog"
    assert timestamps["sim"] == "2026-11-14-00-00"
    plan = json.loads(
        (tmp_path / "build/ci-summary/parallel-iverilog.json").read_text(encoding="utf-8")
    )
    assert plan["failure_policy"] == "both groups finish; either failure fails the regression"
    assert plan["iverilog_build_timestamp"] != plan["primary_build_timestamp"]


def test_parallel_failure_does_not_hide_the_other_group(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    primary, iverilog = split_iverilog_assembly(mini_commands())
    calls = []

    def fake_run(command, root, capture_output, environment):
        calls.append(command)
        if "sim-asm" in command:
            raise subprocess.CalledProcessError(1, command)
        return ""

    monkeypatch.setattr("scripts.regress.run_command", fake_run)
    monkeypatch.setattr("scripts.regress.self_owned_warnings", lambda root, output: [])
    result = run_parallel_iverilog(
        primary, iverilog, tmp_path, {"BUILD_TIMESTAMP": "2026-11-14-00-00"}
    )
    assert result == 1
    assert len(calls) == len(primary) + len(iverilog)


def test_both_simulation_results_are_discoverable(tmp_path: Path) -> None:
    for variant, simulator in (("main", "verilator"), ("iverilog", "iverilog/behv")):
        result = tmp_path / "build" / variant / "sim" / simulator / "result-sim.json"
        result.parent.mkdir(parents=True)
        result.write_text(
            json.dumps(
                {
                    "status": "passed",
                    "exit_code": 0,
                    "started_at": "2026-11-14T00:00:01+00:00",
                }
            ),
            encoding="utf-8",
        )
    results, issues = collect_results(
        tmp_path / "build", tmp_path, datetime(2026, 11, 14, tzinfo=timezone.utc)
    )
    assert issues == []
    assert len(results) == 2


def test_parallel_cli_dry_run_and_scope_guard(tmp_path: Path) -> None:
    command = [
        sys.executable,
        str(ROOT / "scripts/regress.py"),
        "--root",
        str(tmp_path),
        "--suite",
        "pr",
        "--pdk",
        "ICS55",
        "--soc",
        "MINI",
        "--behavioral-only",
        "--parallel-iverilog",
        "--dry-run",
    ]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    assert completed.returncode == 0, completed.stderr
    assert "sim-asm" in completed.stdout
    assert "--fast-flash" in completed.stdout
    assert not (tmp_path / "build/ci-summary/parallel-iverilog.json").exists()
    command.remove("--soc")
    command.remove("MINI")
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    assert completed.returncode == 2
    assert "--parallel-iverilog requires" in completed.stderr


def test_parallel_switch_is_limited_to_ics55_pull_request_mini() -> None:
    caller = (ROOT / ".github/workflows/regression-ics55.yml").read_text(encoding="utf-8")
    reusable = (ROOT / ".github/workflows/_regression.yml").read_text(encoding="utf-8")
    assert "parallel_iverilog: ${{ github.event_name == 'pull_request' }}" in caller
    assert 'PARALLEL_IVERILOG: ${{ inputs.parallel_iverilog }}' in reusable
    assert '"${PARALLEL_IVERILOG}" == "true" && "${PRODUCT}" == "MINI"' in reusable
    assert "regression-gate:" in reusable
