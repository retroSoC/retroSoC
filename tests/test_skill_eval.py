from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]

from scripts.skill_eval import (  # noqa: E402
    grade_trace,
    load_cases,
    prepare_workspace,
    repo_snapshot,
    selected_cases,
    validate_evals,
    walk_events,
)


def trace_for(case: dict) -> dict:
    return {
        "case": case,
        "exit_code": 0,
        "error": None,
        "response": {
            "invoked_skills": [case["skill"]],
            "verdict": "SPEC_CONFLICT",
            "route": "retrosoc-feature-review",
            "summary": "TINY profile conflict; shared repository evidence remains read-only.",
        },
        "commands": [{"command": "git diff --check", "exit_code": 0, "status": "completed"}],
        "file_changes": [],
        "repository_delta": [],
        "duration_seconds": 1.0,
        "usage": [],
    }


def test_registry_and_behavior_corpus_are_complete() -> None:
    assert validate_evals(ROOT) == []
    document, cases = load_cases(ROOT)
    assert len(cases) == 57
    assert document["defaults"]["read_only"] is True
    assert all(case["prompt"] and case["expected_output"] for case in cases)
    assert all(case["skill_contract_version"] == 1 for case in cases)


def test_smoke_selects_one_live_case_per_registered_skill() -> None:
    _, cases = load_cases(ROOT)
    args = SimpleNamespace(skill=None, smoke=True, case=None)
    selected = selected_cases(cases, args)
    assert len(selected) == 6
    assert {case["skill"] for case in selected} == {
        "retrosoc-feature-design",
        "retrosoc-feature-implementation",
        "retrosoc-feature-review",
        "retrosoc-datasheet",
        "retrosoc-dependency-maintenance",
        "retrosoc-physical-flow",
    }
    assert all(case["live"] for case in selected)


def test_event_parser_extracts_commands_changes_and_usage() -> None:
    events = [
        {
            "type": "item.completed",
            "item": {"type": "command_execution", "command": "git status", "exit_code": 0, "status": "completed"},
        },
        {"type": "turn.completed", "usage": {"input_tokens": 10, "output_tokens": 5}},
    ]
    commands = []
    changes = []
    usage = []
    walk_events(events, commands, changes, usage)
    assert commands == [{"command": "git status", "exit_code": 0, "status": "completed"}]
    assert changes == []
    assert usage == [{"input_tokens": 10, "output_tokens": 5}]


def test_grader_accepts_matching_read_only_trace() -> None:
    document, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "implementation-06")
    trace = trace_for(case)
    trace["response"]["summary"] = "SPEC_CONFLICT: the selected profile is MINI, not TINY."
    result = grade_trace(trace, document["defaults"])
    assert result["status"] == "passed", result


def test_grader_rejects_forbidden_writes_and_wrong_route() -> None:
    document, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "design-03")
    trace = trace_for(case)
    trace["response"]["route"] = "retrosoc-feature-implementation"
    trace["commands"] = [{"command": "git push origin topic", "exit_code": 0}]
    trace["repository_delta"] = [" M docs/ip/uart.md"]
    result = grade_trace(trace, document["defaults"])
    failed = {item["id"] for item in result["checks"] if not item["pass"]}
    assert "route" in failed
    assert any(identifier.startswith("forbidden-command:") for identifier in failed)
    assert "repository-read-only" in failed


def test_negative_trigger_case_is_enforced() -> None:
    document, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "design-10")
    trace = trace_for(case)
    result = grade_trace(trace, document["defaults"])
    assert result["status"] == "failed"
    assert any(item["id"] == "skill-negative-trigger" and not item["pass"] for item in result["checks"])


def test_repository_snapshot_detects_content_changes_even_when_status_is_unchanged(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "eval@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "Eval"], check=True)
    path = tmp_path / "tracked.txt"
    path.write_text("before\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(tmp_path), "add", "tracked.txt"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "initial"], check=True)
    path.write_text("first modification\n", encoding="utf-8")
    before = repo_snapshot(tmp_path)
    path.write_text("second modification\n", encoding="utf-8")
    after = repo_snapshot(tmp_path)
    assert before != after
    assert sorted(set(after) - set(before))


def test_prepare_workspace_isolated_from_later_source_changes(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    subprocess.run(["git", "init", "-q", str(source)], check=True)
    subprocess.run(["git", "-C", str(source), "config", "user.email", "eval@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(source), "config", "user.name", "Eval"], check=True)
    (source / ".gitignore").write_text("build/\n", encoding="utf-8")
    (source / "README.md").write_text("before\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(source), "add", ".gitignore", "README.md"], check=True)
    subprocess.run(["git", "-C", str(source), "commit", "-qm", "initial"], check=True)
    (source / "scripts").mkdir()
    (source / "scripts/new.py").write_text("VALUE = 1\n", encoding="utf-8")
    (source / "build").mkdir()
    (source / "build/generated.txt").write_text("ignored\n", encoding="utf-8")

    workspace = tmp_path / "workspace"
    prepare_workspace(source, workspace)
    (source / "README.md").write_text("after\n", encoding="utf-8")
    assert (workspace / "README.md").read_text(encoding="utf-8") == "before\n"
    assert (workspace / "scripts/new.py").is_file()
    assert not (workspace / "build/generated.txt").exists()
    status = subprocess.check_output(["git", "-C", str(workspace), "status", "--porcelain"], text=True)
    assert status == ""
    assert subprocess.check_output(["git", "-C", str(workspace), "branch", "--show-current"], text=True).strip() == "dev"


def test_run_trace_binds_skill_runner_and_input_provenance(tmp_path: Path, monkeypatch) -> None:
    from scripts.skill_eval import input_snapshot_sha256, run_codex

    _, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "design-03")
    monkeypatch.setattr("scripts.skill_eval.prepare_workspace", lambda root, workspace: None)
    monkeypatch.setattr("scripts.skill_eval.repo_snapshot", lambda root: [])
    monkeypatch.setattr(
        "scripts.skill_eval.git_output",
        lambda root, *args: "b" * 40 if args[-1] == "HEAD^{tree}" else "a" * 40,
    )
    monkeypatch.setattr(subprocess, "check_output", lambda *args, **kwargs: "codex-test\n")

    def execute(command, **kwargs):
        response = command[command.index("--output-last-message") + 1]
        Path(response).write_text(
            json.dumps(
                {
                    "invoked_skills": [case["skill"]],
                    "verdict": "NONE",
                    "route": "retrosoc-feature-review",
                    "summary": "Read-only repository evidence; NOT_RUN.",
                }
            ),
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, 0, stdout='{"type":"turn.completed","usage":{}}\n', stderr="")

    monkeypatch.setattr(subprocess, "run", execute)
    trace = run_codex(ROOT, case, tmp_path, ROOT / ".agents/skills/response.schema.json", "test-model", 60)
    assert trace["skill_source_revision"] == "a" * 40
    assert trace["skill_contract_version"] == 1
    assert trace["runner_version"] == "codex-test"
    assert trace["model"] == "test-model"
    assert trace["input_snapshot_sha256"] == input_snapshot_sha256(case)
    assert trace["workspace_tree"] == "b" * 40
    assert len(trace["skill_entrypoint_sha256"]) == 64


def test_eval_contract_compatibility_and_migration(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    (root / ".agents").mkdir(parents=True)
    shutil.copytree(ROOT / ".agents/skills", root / ".agents/skills")
    behavior = root / ".agents/skills/behavior-evals.json"
    document = json.loads(behavior.read_text(encoding="utf-8"))
    document.pop("skill_case_counts")
    behavior.write_text(json.dumps(document), encoding="utf-8")
    assert validate_evals(root) == []

    registry_path = root / ".agents/skills/registry.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    registry["skills"][0]["contract_version"] = 2
    registry_path.write_text(json.dumps(registry), encoding="utf-8")
    assert any("contract migration" in issue for issue in validate_evals(root))
    migration = root / ".agents/skills/migrations/design-v2.md"
    migration.parent.mkdir()
    migration.write_text("v1 to v2 input/output migration and compatibility evidence.\n", encoding="utf-8")
    registry["skills"][0]["contract_migration"] = ".agents/skills/migrations/design-v2.md"
    registry_path.write_text(json.dumps(registry), encoding="utf-8")
    assert validate_evals(root) == []


def test_skill_eval_canary_is_opt_in_and_bounded() -> None:
    import yaml

    workflow = yaml.load(
        (ROOT / ".github/workflows/skill-evals.yml").read_text(encoding="utf-8"),
        Loader=yaml.BaseLoader,
    )
    assert workflow["on"]["schedule"]
    inputs = workflow["on"]["workflow_dispatch"]["inputs"]
    assert inputs["scope"]["options"] == ["smoke", "all"]
    assert inputs["agent"]["options"] == ["codex", "kimi"]
    assert inputs["agent"]["default"] == "codex"
    job = workflow["jobs"]["smoke"]
    assert "RETROSOC_SKILL_EVALS_ENABLED" in job["if"]
    assert "480" in job["timeout-minutes"]
    run = next(step for step in job["steps"] if step["name"] == "Run isolated read-only Skill evaluations")
    assert "--smoke" in run["run"]
    assert "--skill" in run["run"]
    assert "--runner" in run["run"]


def test_kimi_event_parser_normalizes_tools_changes_usage_and_response() -> None:
    from scripts.skill_eval import walk_kimi_events

    events = [
        {"role": "meta", "usage": {"input_tokens": 2}},
        {
            "role": "assistant",
            "content": None,
            "tool_calls": [
                {"id": "skill-1", "function": {"name": "Skill", "arguments": '{"skill":"retrosoc-feature-review"}'}},
                {"id": "write-1", "function": {"name": "Write", "arguments": {"path": "bad.txt"}}},
            ],
        },
        {"role": "tool", "tool_call_id": "skill-1", "is_error": False},
        {"role": "tool", "tool_call_id": "write-1", "is_error": True},
        {"role": "assistant", "content": '```json\n{"invoked_skills":["retrosoc-feature-review"],"verdict":"RUN_GATES","route":"NONE","summary":"NOT_RUN"}\n```'},
    ]
    commands, changes, usage, response = walk_kimi_events(events)
    assert [item["status"] for item in commands] == ["completed", "failed"]
    assert commands[0]["tool"] == "Skill"
    assert commands[1]["exit_code"] == 1
    assert changes == [{"path": "bad.txt"}]
    assert usage == [{"input_tokens": 2}]
    assert response["verdict"] == "RUN_GATES"


def test_kimi_eval_profile_has_no_write_shell_or_delegation_capability() -> None:
    import yaml

    text = (ROOT / ".agents/skill-eval-agent.md").read_text(encoding="utf-8")
    metadata = yaml.safe_load(text.split("---", 2)[1])
    assert set(metadata["tools"]) == {"Read", "Grep", "Glob", "Skill"}
    assert metadata["subagents"] == []
    assert {"Bash", "Write", "Edit", "Agent", "AgentSwarm"} <= set(metadata["disallowedTools"])


def test_kimi_trace_binds_runner_profile(tmp_path: Path, monkeypatch) -> None:
    from scripts.skill_eval import run_kimi

    _, cases = load_cases(ROOT)
    case = next(item for item in cases if item["id"] == "design-03")

    def workspace(root, destination):
        (destination / ".agents").mkdir(parents=True)
        shutil.copy(root / ".agents/skill-eval-agent.md", destination / ".agents/skill-eval-agent.md")

    monkeypatch.setattr("scripts.skill_eval.prepare_workspace", workspace)
    monkeypatch.setattr("scripts.skill_eval.repo_snapshot", lambda root: [])
    monkeypatch.setattr(
        "scripts.skill_eval.git_output",
        lambda root, *args: "b" * 40 if args[-1] == "HEAD^{tree}" else "a" * 40,
    )
    monkeypatch.setattr(subprocess, "check_output", lambda *args, **kwargs: "kimi-test\n")

    def execute(command, **kwargs):
        assert "--agent-file" in command
        assert "--plan" not in command
        response = '{"invoked_skills":["retrosoc-feature-design"],"verdict":"NONE","route":"retrosoc-feature-review","summary":"NOT_RUN"}'
        return subprocess.CompletedProcess(command, 0, stdout=json.dumps({"role": "assistant", "content": response}) + "\n", stderr="")

    monkeypatch.setattr(subprocess, "run", execute)
    trace = run_kimi(ROOT, case, tmp_path, "test-model", 60)
    assert trace["runner"] == "kimi"
    assert trace["runner_version"] == "kimi-test"
    assert trace["runner_agent_sha256"]
    assert trace["response"]["route"] == "retrosoc-feature-review"
    assert trace["error"] is None


def test_prompt_requires_exact_json_and_budget() -> None:
    from scripts.skill_eval import evaluation_prompt, walk_kimi_events

    _, cases = load_cases(ROOT)
    prompt = evaluation_prompt(cases[0], 42)
    assert "at most 42 tool calls" in prompt
    assert "exactly one JSON object" in prompt
    assert "invoked_skills, verdict, route, and summary" in prompt
    assert "never substitute skills_invoked" in prompt
    _, _, _, response = walk_kimi_events(
        [{"role": "assistant", "content": "verdict: FAIL\nskills_invoked: []"}]
    )
    assert response == {}
