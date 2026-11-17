from __future__ import annotations

import hashlib
import io
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

from scripts import regress
from scripts.performance_evidence import bind_sample, evaluate
from scripts.regress import command_record, selection_digest, semantic_digest

ROOT = Path(__file__).resolve().parents[1]
REVISION = "a" * 40
OTHER_REVISION = "b" * 40
LOCK = "d" * 64


def job(run_id: int = 1, revision: str = REVISION) -> dict:
    return {
        "id": run_id * 10,
        "run_id": run_id,
        "run_attempt": 1,
        "head_sha": revision,
        "status": "completed",
        "conclusion": "success",
        "runner_id": 99,
        "runner_name": "hosted-runner",
        "runner_group_id": 1,
        "labels": ["ubuntu-22.04"],
    }


def isolation(run_id: int = 1) -> dict:
    return {
        "exclusive": True,
        "lease_id": f"lease-{run_id}",
        "machine": "test-x86",
        "cpu_count": 4,
        "memory_bytes": 16 * 1024**3,
        "contention": "NONE",
        "runner_id": 99,
    }


def plan(revision: str) -> dict:
    document = {
        "schema_version": 1,
        "kind": "regression-command-identity",
        "execution": "execute",
        "source_revision": revision,
        "dependency_lock_sha256": LOCK,
        "suite": "pr",
        "pdk": "IHP130",
        "soc": "ALL",
        "behavioral_only": True,
        "netsim_boot_only": False,
        "tiny_p7_iverilog": "exclude",
        "tiny_p7_iverilog_timeout_seconds": 14400,
        "commands": [
            command_record("configs/ci/ihp130.mk", ("SIMU=VERILATOR", "rtl-lint")),
            command_record("configs/ci/ihp130.mk", ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
        ],
        "observations": [command_record("configs/ci/ihp130.mk", ("check-metrics",))],
    }
    document["command_set_sha256"] = selection_digest(document)
    return document


def manifest(revision: str) -> dict:
    return {
        "schema_version": 1,
        "profile": "ihp130",
        "repository": {"commit": revision, "dirty": False},
        "dependency_lock": {"sha256": LOCK},
        "configuration": {"PDK": "IHP130", "SOC": "MINI"},
        "tools": {"iverilog": "Icarus test version", "verilator": "Verilator test version"},
    }


def result(revision: str) -> dict:
    command = ["stdbuf", "-oL", "-eL", "vvp", "simv", "-fst", "+sim_timeout=5200000", "+wave_NO"]
    return {
        "schema_version": 2,
        "task_id": "iverilog-sim",
        "status": "passed",
        "source_revision": revision,
        "source_dirty": False,
        "source_state_sha256": "c" * 64,
        "environment_sha256": "e" * 64,
        "tool_lock_sha256": None,
        "configuration": {"profile": None, "pdk": None, "soc": None},
        "command": command,
        "command_sha256": semantic_digest(command),
        "duration_seconds": 998.948,
        "peak_rss_kib": 2392704,
    }


def artifact(revision: str = REVISION, with_plan: bool = True) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        variant = "ihp130-2026-01-01-deadbeef"
        archive.writestr(f"{variant}/meta/manifest.json", json.dumps(manifest(revision)))
        archive.writestr(f"{variant}/sim/iverilog/behv/result-sim.json", json.dumps(result(revision)))
        if with_plan:
            archive.writestr("ci-summary/regression-plan-pr-IHP130.json", json.dumps(plan(revision)))
    return output.getvalue()


def write_artifact(root: Path, run_id: int, revision: str = REVISION, with_plan: bool = True) -> Path:
    path = root / f"pr-regression-{run_id}-1.zip"
    path.write_bytes(artifact(revision, with_plan))
    return path


def test_dry_run_plan_matches_the_printed_command_selection(tmp_path: Path) -> None:
    output = tmp_path / "plan.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/regress.py"),
            "--root",
            str(ROOT),
            "--suite",
            "smoke",
            "--pdk",
            "IHP130",
            "--behavioral-only",
            "--dry-run",
            "--plan-output",
            str(output),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    document = json.loads(output.read_text(encoding="utf-8"))
    expected = [line.removeprefix("+ ").split() for line in completed.stdout.splitlines() if line.startswith("+ make ")]
    actual = [entry["command"] for entry in [*document["commands"], *document["observations"]]]
    assert actual == expected
    assert document["execution"] == "dry-run"
    assert document["behavioral_only"] is True
    assert document["command_set_sha256"] == selection_digest(document)
    assert document["source_revision"] == subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    assert document["dependency_lock_sha256"] == hashlib.sha256(
        (ROOT / "dependencies/dependencies.lock.json").read_bytes()
    ).hexdigest()
    assert all("synth" not in entry["arguments"] and "netsim" not in entry["arguments"] for entry in document["commands"])


def test_plan_is_written_before_the_same_mocked_commands_execute(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    output = tmp_path / "plan.json"
    primary = []
    observations = []
    monkeypatch.setattr(
        regress.sys,
        "argv",
        ["regress.py", "--root", str(ROOT), "--suite", "smoke", "--pdk", "IHP130", "--plan-output", str(output)],
    )

    def execute(command, root, capture_output, environment):
        primary.append(command)
        return ""

    monkeypatch.setattr(regress, "run_command", execute)
    monkeypatch.setattr(regress, "run_observation", lambda command, root, environment: observations.append(command))

    assert regress.main() == 0
    document = json.loads(output.read_text(encoding="utf-8"))
    assert document["execution"] == "execute"
    assert primary == [entry["command"] for entry in document["commands"]]
    assert observations == [entry["command"] for entry in document["observations"]]
    workflow = (ROOT / ".github/workflows/_regression.yml").read_text(encoding="utf-8")
    assert "--plan-output" in workflow
    assert "build/ci-summary/regression-plan-" in workflow


def test_binder_supplies_manifest_identity_and_requires_isolation(tmp_path: Path) -> None:
    path = write_artifact(tmp_path, 1)
    isolated = bind_sample(path, job(), role="baseline", isolation=isolation())
    assert isolated["identity_complete"] is True
    assert isolated["identity_gaps"] == []
    assert isolated["pairing_eligible"] is True
    assert isolated["pairing_key"] is not None
    assert isolated["evaluated_profile"] == "configs/ci/ihp130.mk"
    assert isolated["evaluated_arguments"] == ["SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm"]
    assert isolated["tool_lock_sha256"] == LOCK
    assert isolated["tool_lock_source"] == "manifest"
    assert isolated["tool_versions"]["iverilog"] == "Icarus test version"
    assert isolated["isolation"]["machine"] == "test-x86"

    observed = bind_sample(path, job())
    assert observed["identity_complete"] is False
    assert observed["identity_gaps"] == ["runner isolation and contention controls absent"]
    assert observed["evaluated_profile"] == "configs/ci/ihp130.mk"
    assert observed["pairing_key"] is None
    assert observed["pairing_eligible"] is False


def test_legacy_artifact_stays_observational_without_a_command_plan(tmp_path: Path) -> None:
    sample = bind_sample(write_artifact(tmp_path, 2, with_plan=False), job(2), isolation=isolation(2))
    assert sample["identity_gaps"] == ["evaluated command plan is unavailable"]
    assert sample["evaluated_profile"] is None
    assert sample["command_set_sha256"] is None
    assert sample["tool_lock_sha256"] == LOCK
    assert sample["pairing_key"] is None
    assert evaluate([sample])["decision"] == "HOLD"
    assert evaluate([sample])["experiment_started"] is False


def test_missing_legacy_digests_remain_null_and_block_pairing(tmp_path: Path) -> None:
    output = io.BytesIO()
    incomplete = result(REVISION)
    incomplete["environment_sha256"] = None
    incomplete["source_state_sha256"] = None
    with zipfile.ZipFile(output, "w") as archive:
        variant = "ihp130-2026-01-01-deadbeef"
        archive.writestr(f"{variant}/meta/manifest.json", json.dumps(manifest(REVISION)))
        archive.writestr(f"{variant}/sim/iverilog/behv/result-sim.json", json.dumps(incomplete))
        archive.writestr("ci-summary/regression-plan-pr-IHP130.json", json.dumps(plan(REVISION)))
    path = tmp_path / "pr-regression-3-1.zip"
    path.write_bytes(output.getvalue())
    sample = bind_sample(path, job(3), role="baseline", isolation=isolation(3))
    assert sample["environment_sha256"] is None
    assert sample["source_state_sha256"] is None
    assert set(sample["identity_gaps"]) == {"execution environment digest is unavailable", "source state digest is unavailable"}
    assert sample["pairing_key"] is None


def test_identity_mismatch_and_unsafe_artifacts_are_rejected(tmp_path: Path) -> None:
    path = write_artifact(tmp_path, 4)
    with pytest.raises(ValueError, match="revisions differ"):
        bind_sample(path, job(4, OTHER_REVISION))
    with pytest.raises(ValueError, match="lease and machine"):
        bind_sample(path, job(4), isolation={"exclusive": True, "lease_id": "missing-resources"})

    unsafe = io.BytesIO()
    with zipfile.ZipFile(unsafe, "w") as archive:
        archive.writestr("../meta/manifest.json", "{}")
    path.write_bytes(unsafe.getvalue())
    with pytest.raises(ValueError, match="unsafe"):
        bind_sample(path, job(4))


def test_five_distinct_pairs_are_required_before_review(tmp_path: Path) -> None:
    samples = []
    for number in range(1, 6):
        for role, run_id, revision in (("baseline", number, REVISION), ("candidate", 100 + number, OTHER_REVISION)):
            sample = bind_sample(
                write_artifact(tmp_path, run_id, revision),
                job(run_id, revision),
                role=role,
                isolation=isolation(run_id),
            )
            samples.append(sample)
        if number == 4:
            assert evaluate(samples)["decision"] == "HOLD"
    result_document = evaluate(samples)
    assert result_document["decision"] == "READY_FOR_REVIEW"
    assert result_document["complete_pair_group_count"] == 1
    assert result_document["pair_groups"][0]["baseline_count"] == 5
    assert result_document["pair_groups"][0]["candidate_count"] == 5
    assert result_document["complete_identity_count"] == 10
    assert result_document["experiment_started"] is False
    assert result_document["network_access"] is False


def test_duplicate_run_roles_cannot_fill_a_pair_threshold() -> None:
    samples = [
        {"run_id": 1, "job_id": 10, "role": "baseline", "identity_complete": True, "pairing_eligible": True, "pairing_key": "same"},
        {"run_id": 1, "job_id": 10, "role": "baseline", "identity_complete": True, "pairing_eligible": True, "pairing_key": "same"},
    ]
    with pytest.raises(ValueError, match="duplicate run, job, and role"):
        evaluate(samples)
