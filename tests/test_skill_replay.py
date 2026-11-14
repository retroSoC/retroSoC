from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

from scripts.skill_eval import evaluation_prompt, input_snapshot_sha256, load_cases, replay_traces

ROOT = Path(__file__).resolve().parents[1]


def valid_trace() -> dict:
    _, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "implementation-06")
    entrypoint = ROOT / case["skill_entrypoint"]
    prompt = evaluation_prompt(case, 80)
    return {
        "schema_version": 1,
        "case": case,
        "source_revision": "a" * 40,
        "skill_source_revision": "a" * 40,
        "skill_contract_version": 1,
        "skill_entrypoint_sha256": hashlib.sha256(entrypoint.read_bytes()).hexdigest(),
        "input_snapshot_sha256": input_snapshot_sha256(case),
        "evaluation_prompt": prompt,
        "evaluation_prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
        "command_budget": 80,
        "workspace_revision": "b" * 40,
        "workspace_tree": "c" * 40,
        "runner": "codex",
        "runner_version": "codex-test",
        "model": "test-model",
        "duration_seconds": 1.0,
        "exit_code": 0,
        "error": None,
        "response": {
            "invoked_skills": [case["skill"]],
            "verdict": "SPEC_CONFLICT",
            "route": "retrosoc-feature-review",
            "summary": "SPEC_CONFLICT: the selected profile is MINI, not TINY; NOT_RUN elsewhere.",
        },
        "commands": [{"command": "git diff --check", "exit_code": 0, "status": "completed"}],
        "file_changes": [],
        "repository_delta": [],
        "usage": [],
    }


def write_trace(directory: Path, trace: dict, name: str = "case.trace.json") -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / name
    path.write_text(json.dumps(trace), encoding="utf-8")
    return path


def test_replay_binds_provenance_without_running_a_runner(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = write_trace(tmp_path, valid_trace())
    monkeypatch.setattr(
        "scripts.skill_eval.run_codex",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("runner called")),
    )
    monkeypatch.setattr(
        "scripts.skill_eval.run_kimi",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("runner called")),
    )
    result = replay_traces(ROOT, [path])
    assert result["status"] == "REPLAYED"
    assert result["runner_invocations"] == 0
    assert result["behavior_execution"] == "NOT_RUN"
    assert result["grade_passed_count"] == 1
    identity = result["records"][0]["identity"]
    assert identity["case_snapshot_status"] == "current"
    assert identity["skill_matches_current"] is True
    assert identity["workspace_tree"] == "c" * 40
    assert result["records"][0]["trace_sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()


def test_replay_rejects_input_tampering_and_unknown_runner(tmp_path: Path) -> None:
    tampered = valid_trace()
    tampered["case"]["prompt"] = "changed after capture"
    first = write_trace(tmp_path, tampered, "tampered.trace.json")
    unknown = valid_trace()
    unknown["runner"] = "implicit-fallback"
    second = write_trace(tmp_path, unknown, "unknown.trace.json")
    result = replay_traces(ROOT, [first, second])
    assert result["status"] == "INVALID"
    assert result["invalid_trace_count"] == 2
    assert result["grade_passed_count"] == 0


def test_replay_marks_historical_input_and_read_only_violations(tmp_path: Path) -> None:
    from scripts.skill_eval import validate_trace_identity

    _, cases = load_cases(ROOT)
    trace = valid_trace()
    trace["case"]["prompt"] = "Earlier frozen prompt"
    trace["input_snapshot_sha256"] = input_snapshot_sha256(trace["case"])
    identity = validate_trace_identity(ROOT, trace, cases)
    assert identity["case_snapshot_status"] == "historical"
    trace["repository_delta"] = [" M docs/ip/example.md"]
    path = write_trace(tmp_path, trace)
    result = replay_traces(ROOT, [path])
    assert result["status"] == "REPLAYED"
    assert result["grade_failed_count"] == 1
    assert result["behavior_execution"] == "NOT_RUN"


def test_replay_cli_and_empty_evidence_fail_closed(tmp_path: Path) -> None:
    trace = write_trace(tmp_path, valid_trace())
    output = tmp_path / "replay.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/skill_eval.py"),
            "replay",
            "--root",
            str(ROOT),
            "--trace",
            str(trace),
            "--output",
            str(output),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    document = json.loads(output.read_text(encoding="utf-8"))
    assert document["status"] == "REPLAYED"
    assert document["runner_invocations"] == 0
    empty = tmp_path / "empty"
    empty.mkdir()
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/skill_eval.py"),
            "replay",
            "--root",
            str(ROOT),
            "--trace-root",
            str(empty),
            "--output",
            str(output),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode != 0
    assert json.loads(output.read_text(encoding="utf-8"))["status"] == "NOT_RUN"


def test_replay_rejects_duplicate_trace_paths(tmp_path: Path) -> None:
    trace = write_trace(tmp_path, valid_trace())
    with pytest.raises(ValueError, match="must be unique"):
        replay_traces(ROOT, [trace, trace])


def test_replay_distinguishes_legacy_and_tampered_prompt_provenance(tmp_path: Path) -> None:
    legacy = valid_trace()
    for field in ("evaluation_prompt", "evaluation_prompt_sha256", "command_budget"):
        legacy.pop(field)
    legacy_path = write_trace(tmp_path, legacy, "legacy.trace.json")
    result = replay_traces(ROOT, [legacy_path])
    identity = result["records"][0]["identity"]
    assert identity["provenance_complete"] is False
    assert identity["rendered_prompt_status"] == "NOT_RECORDED"
    assert identity["evaluation_prompt_matches_current"] is None
    assert result["partial_provenance_count"] == 1

    tampered = valid_trace()
    tampered["evaluation_prompt"] = "changed after capture"
    tampered_path = write_trace(tmp_path, tampered, "tampered-prompt.trace.json")
    result = replay_traces(ROOT, [tampered_path])
    assert result["status"] == "INVALID"
    assert result["invalid_trace_count"] == 1
    assert result["grade_passed_count"] == 0


def test_replay_rejects_an_entrypoint_outside_the_registered_case(tmp_path: Path) -> None:
    trace = valid_trace()
    trace["case"]["skill_entrypoint"] = ".agents/skills/retrosoc-feature-review/SKILL.md"
    path = write_trace(tmp_path, trace, "wrong-entrypoint.trace.json")
    result = replay_traces(ROOT, [path])
    assert result["status"] == "INVALID"
    assert result["invalid_trace_count"] == 1
    assert "registered case" in result["records"][0]["error"]
