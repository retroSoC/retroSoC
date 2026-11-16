from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import pytest

from scripts.flow_control import (
    Lease,
    execution_fingerprint,
    fingerprint_mismatches,
    process_start_ticks,
    terminate_process_group,
    write_json,
)

ROOT = Path(__file__).resolve().parents[1]
RUN_FLOW = ROOT / "scripts/run_flow.py"


def invoke(tmp_path: Path, command: list[str], *extra: str) -> tuple[subprocess.CompletedProcess[str], dict, Path, Path]:
    log = tmp_path / "flow.log"
    result = tmp_path / "result.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(RUN_FLOW),
            "--tool",
            "unit",
            "--log",
            str(log),
            "--result",
            str(result),
            *extra,
            "--",
            *command,
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    document = json.loads(result.read_text(encoding="utf-8")) if result.is_file() else {}
    return completed, document, log, result


def process_alive(pid: int) -> bool:
    try:
        fields = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").rsplit(")", 1)[1].split()
        return fields[0] not in {"Z", "X"}
    except (OSError, IndexError):
        return False


def test_resume_reuses_only_matching_passed_result(tmp_path: Path) -> None:
    command = [sys.executable, "-c", "print('ok')"]
    first, original, log, result = invoke(tmp_path, command, "--env", "FLOW_TEST_VALUE=initial")
    assert first.returncode == 0
    assert original["status"] == "passed"
    assert original["schema_version"] == 2
    assert original["attempt"] == 1
    assert original["parent_start_ticks"] is not None
    original_mtime = result.stat().st_mtime_ns

    resumed, reused, _, _ = invoke(tmp_path, command, "--env", "FLOW_TEST_VALUE=initial", "--resume")
    assert resumed.returncode == 0
    assert reused["run_id"] == original["run_id"]
    assert reused["attempt"] == 1
    assert result.stat().st_mtime_ns == original_mtime

    changed, _, _, _ = invoke(tmp_path, command, "--env", "FLOW_TEST_VALUE=changed", "--resume")
    assert changed.returncode == 2
    assert "fingerprint mismatch" in changed.stderr
    assert json.loads(result.read_text(encoding="utf-8"))["run_id"] == original["run_id"]
    assert log.read_text(encoding="utf-8") == "ok\n"


def test_failed_attempt_resumes_with_new_identity_and_retained_history(tmp_path: Path) -> None:
    command = [sys.executable, "-c", "raise SystemExit(4)"]
    first, original, _, result = invoke(tmp_path, command)
    assert first.returncode == 4
    assert original["status"] == "failed"
    second, retried, _, _ = invoke(tmp_path, command, "--resume")
    assert second.returncode == 4
    assert retried["attempt"] == 2
    assert retried["run_id"] != original["run_id"]
    attempts = list((result.parent / "result.json.attempts").glob("*.json"))
    assert len(attempts) == 1
    assert json.loads(attempts[0].read_text(encoding="utf-8"))["run_id"] == original["run_id"]


def test_legacy_pass_is_not_accepted_for_resume(tmp_path: Path) -> None:
    result = tmp_path / "result.json"
    write_json(result, {"schema_version": 1, "status": "passed", "exit_code": 0})
    completed, _, _, _ = invoke(tmp_path, [sys.executable, "-c", "print('must not run')"], "--resume")
    assert completed.returncode == 2
    assert "fingerprint mismatch" in completed.stderr
    assert json.loads(result.read_text(encoding="utf-8"))["schema_version"] == 1


def test_single_flight_rejects_live_lease_and_recovers_after_release(tmp_path: Path) -> None:
    result = tmp_path / "result.json"
    lock = result.with_name(result.name + ".lock")
    command = [sys.executable, "-c", "print('ok')"]
    with Lease(lock, {"task_id": "unit"}):
        completed, _, _, _ = invoke(tmp_path, command)
        assert completed.returncode == 2
        assert "active lease" in completed.stderr
    completed, document, _, _ = invoke(tmp_path, command)
    assert completed.returncode == 0
    assert document["status"] == "passed"


def test_cancel_uses_run_identity_and_terminates_wrapper(tmp_path: Path) -> None:
    log = tmp_path / "cancel.log"
    result = tmp_path / "cancel.json"
    process = subprocess.Popen(
        [
            sys.executable,
            str(RUN_FLOW),
            "--tool",
            "unit",
            "--log",
            str(log),
            "--result",
            str(result),
            "--heartbeat-seconds",
            "0.05",
            "--",
            sys.executable,
            "-u",
            "-c",
            "print('READY', flush=True); import time; time.sleep(30)",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        assert process.stdout is not None
        assert process.stdout.readline().strip() == "READY"
        running = json.loads(result.read_text(encoding="utf-8"))
        cancelled = subprocess.run(
            [
                sys.executable,
                str(RUN_FLOW),
                "--tool",
                "unit",
                "--log",
                str(log),
                "--result",
                str(result),
                "--cancel",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert cancelled.returncode == 0, cancelled.stderr
        _, stderr = process.communicate(timeout=15)
        assert process.returncode == 130, stderr
        final = json.loads(result.read_text(encoding="utf-8"))
        assert final["status"] == "interrupted"
        assert final["child_cleanup_pending"] is False
        marker = json.loads(result.with_name(result.name + ".cancel.json").read_text(encoding="utf-8"))
        assert marker["run_id"] == running["run_id"]
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)


def test_internal_deadline_is_bounded_and_cleans_group(tmp_path: Path) -> None:
    completed, document, _, _ = invoke(
        tmp_path,
        [sys.executable, "-c", "import time; time.sleep(30)"],
        "--timeout-seconds",
        "0.2",
        "--heartbeat-seconds",
        "0.05",
    )
    assert completed.returncode == 124
    assert document["status"] == "failed"
    assert document["child_cleanup_pending"] is False
    assert "deadline" in document["error"]


def test_direct_parent_exit_cannot_leave_live_descendant_or_pass(tmp_path: Path) -> None:
    command = [
        sys.executable,
        "-u",
        "-c",
        "import subprocess,time; child=subprocess.Popen(['sleep','30']); print(child.pid,flush=True); time.sleep(0.2)",
    ]
    completed, document, log, _ = invoke(
        tmp_path,
        command,
        "--descendant-grace-seconds",
        "0.1",
        "--heartbeat-seconds",
        "0.05",
    )
    assert completed.returncode != 0
    assert document["status"] == "failed"
    assert "process group remained active" in document["error"]
    descendant = int(log.read_text(encoding="utf-8").splitlines()[0])
    for _ in range(100):
        if not process_alive(descendant):
            break
        time.sleep(0.05)
    assert not process_alive(descendant)


def test_short_lived_descendant_can_finish_after_parent_exits(tmp_path: Path) -> None:
    command = [
        sys.executable,
        "-u",
        "-c",
        "import subprocess; child=subprocess.Popen(['sleep','6']); print(child.pid,flush=True)",
    ]
    completed, document, log, _ = invoke(tmp_path, command, "--heartbeat-seconds", "0.1")
    assert completed.returncode == 0, document
    assert document["status"] == "passed"
    assert document["child_cleanup_pending"] is False
    descendant = int(log.read_text(encoding="utf-8").splitlines()[0])
    assert not process_alive(descendant)


def test_status_reconciles_stale_parent_without_signaling_unrelated_process(tmp_path: Path) -> None:
    child = subprocess.Popen(["sleep", "30"], start_new_session=True)
    result = tmp_path / "stale.json"
    write_json(
        result,
        {
            "schema_version": 2,
            "run_id": "stale-run",
            "status": "running",
            "parent_pid": 99999999,
            "parent_start_ticks": 1,
            "child_pid": child.pid,
            "child_start_ticks": process_start_ticks(child.pid),
            "log": str(tmp_path / "stale.log"),
        },
    )
    try:
        completed = subprocess.run(
            [
                sys.executable,
                str(RUN_FLOW),
                "--tool",
                "unit",
                "--log",
                str(tmp_path / "stale.log"),
                "--result",
                str(result),
                "--status",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, completed.stderr
        document = json.loads(result.read_text(encoding="utf-8"))
        assert document["status"] == "interrupted"
        assert child.wait(timeout=5) == -15
        assert not process_alive(child.pid)
    finally:
        if child.poll() is None:
            terminate_process_group(child.pid)
            child.wait(timeout=5)


def test_fingerprint_rejects_changed_input_script_and_environment(tmp_path: Path) -> None:
    script = tmp_path / "flow.tcl"
    script.write_text("first\n", encoding="utf-8")
    input_path = tmp_path / "input.txt"
    input_path.write_text("first\n", encoding="utf-8")
    environment = {"VALUE": "one"}
    command = ["tool", "run"]
    original = execution_fingerprint(
        tmp_path,
        command,
        environment,
        script=script,
        inputs=[input_path],
        configuration={"pdk": "TEST"},
    )
    assert fingerprint_mismatches(original, original) == []

    input_path.write_text("changed\n", encoding="utf-8")
    changed_input = execution_fingerprint(
        tmp_path,
        command,
        environment,
        script=script,
        inputs=[input_path],
        configuration={"pdk": "TEST"},
    )
    assert "input_sha256" in fingerprint_mismatches(original, changed_input)

    script.write_text("changed\n", encoding="utf-8")
    changed_script = execution_fingerprint(
        tmp_path,
        command,
        environment,
        script=script,
        inputs=[input_path],
        configuration={"pdk": "TEST"},
    )
    assert "script_sha256" in fingerprint_mismatches(changed_input, changed_script)

    changed_environment = execution_fingerprint(
        tmp_path,
        command,
        {"VALUE": "two"},
        script=script,
        inputs=[input_path],
        configuration={"pdk": "TEST"},
    )
    assert "environment_sha256" in fingerprint_mismatches(changed_script, changed_environment)


def test_process_group_ignores_zombie_members() -> None:
    from scripts.flow_control import process_group_exists

    child = subprocess.Popen(["true"], start_new_session=True)
    try:
        for _ in range(100):
            if not process_alive(child.pid):
                break
            time.sleep(0.01)
        assert not process_alive(child.pid)
        assert not process_group_exists(child.pid)
    finally:
        child.wait(timeout=5)


@pytest.mark.parametrize("field", ["parent_start_ticks", "child_start_ticks"])
def test_cancel_refuses_uncertain_process_identity(tmp_path: Path, field: str) -> None:
    result = tmp_path / "cancel.json"
    write_json(
        result,
        {
            "schema_version": 2,
            "run_id": "running",
            "status": "running",
            "parent_pid": 99999999,
            "parent_start_ticks": 1,
            "child_pid": 99999998,
            "child_start_ticks": 1,
            field: None,
        },
    )
    completed = subprocess.run(
        [
            sys.executable,
            str(RUN_FLOW),
            "--tool",
            "unit",
            "--log",
            str(tmp_path / "cancel.log"),
            "--result",
            str(result),
            "--cancel",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 2
    assert "refusing to signal another process" in completed.stderr
