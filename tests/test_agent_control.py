from __future__ import annotations

import json
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[1]

from scripts.agent_control import (  # noqa: E402
    JOB_NAMES,
    agent_context,
    classify_files,
    create_plan,
    documentation_issues,
    load_impact,
    render_task_prompt,
    validate_task,
    write_github_outputs,
)


REVISION = "0" * 40


def valid_task() -> dict:
    return {
        "schema_version": 1,
        "task_id": "docs-engineering-control",
        "task_class": "docs",
        "base_revision": REVISION,
        "target_socs": [],
        "scope": {
            "summary": "Document the engineering control plane",
            "allowed_paths": ["docs/engineering.md"],
            "forbidden_paths": ["rtl/**"],
            "non_goals": ["RTL implementation"],
        },
        "acceptance": ["Links and whitespace checks pass"],
        "validation": {
            "risk": "low",
            "mode": "fast",
            "profiles": [],
            "pdks": [],
        },
        "execution": {
            "mode": "read-only",
            "worktree": ".",
            "artifact_root": "build/tasks/docs-engineering-control",
        },
        "status": "planned",
    }


def plan_args(files: list[str], **overrides) -> SimpleNamespace:
    values = {
        "root": ROOT,
        "files": files,
        "files_file": None,
        "base": None,
        "head": "HEAD",
        "mode": "auto",
        "event": "local",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_task_contract_accepts_a_read_only_maintenance_task() -> None:
    assert validate_task(valid_task(), ROOT) == []


def test_feature_write_requires_bound_specification_and_approval() -> None:
    task = valid_task()
    task.update(
        {
            "task_class": "feature",
            "target_socs": ["TINY"],
            "phase": "TINY-P4",
            "specification": {"path": "docs/ip/tiny-soc.md", "revision": REVISION},
        }
    )
    task["execution"]["mode"] = "workspace-write"
    issues = validate_task(task, ROOT)
    assert "feature or high-risk writes require explicit approval" in issues

    task["execution"]["approval"] = {
        "approved_by": "maintainer",
        "reference": "https://github.com/retroSoC/retroSoC/pull/1",
        "plan_sha256": "a" * 64,
    }
    assert validate_task(task, ROOT) == []
    prompt = render_task_prompt(task)
    assert "Target SoCs: TINY" in prompt
    assert "Approved plan SHA-256: " + "a" * 64 in prompt


def test_task_contract_rejects_unknown_fields_and_unsafe_paths() -> None:
    task = valid_task()
    task["unexpected"] = True
    task["scope"]["allowed_paths"] = ["../outside"]
    issues = validate_task(task)
    assert "task unknown fields: unexpected" in issues
    assert "scope.allowed_paths contains an unsafe path" in issues


def test_done_task_requires_evidence() -> None:
    task = valid_task()
    task["status"] = "done"
    assert "done tasks require evidence" in validate_task(task)
    task["evidence"] = [{"kind": "documentation", "uri": "build/result.json", "status": "PASS"}]
    assert validate_task(task) == []


@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("README.md", "documentation"),
        (".agents/skills/retrosoc-feature-design/SKILL.md", "agents"),
        ("publications/build_datasheet.py", "publication"),
        ("tests/test_uart.py", "quality"),
        ("crt/src/hal/gpio.c", "embedded_c"),
        ("rtl/tiny/top/retrosoc_tiny_asic.sv", "tiny_rtl"),
        ("configs/ci/ics55-tiny.mk", "tiny_rtl"),
        ("scripts/regress.py", "full"),
        ("unregistered/file.xyz", "full"),
    ],
)
def test_impact_classifier_uses_conservative_path_rules(path: str, expected: str) -> None:
    policy = load_impact(ROOT)
    classification, matches = classify_files(policy, [path])
    assert classification == expected
    assert matches[0]["file"] == path


def test_highest_risk_change_selects_the_matrix() -> None:
    policy = load_impact(ROOT)
    classification, _ = classify_files(policy, ["README.md", "rtl/tiny/top/retrosoc_tiny_asic.sv"])
    assert classification == "tiny_rtl"
    classification, _ = classify_files(policy, ["rtl/tiny/top/retrosoc_tiny_asic.sv", "scripts/regress.py"])
    assert classification == "full"


def test_documentation_plan_skips_heavy_jobs() -> None:
    plan = create_plan(plan_args(["README.md"]))
    assert plan["selected_policy"] == "documentation"
    assert plan["flags"]["quality_fast"] is True
    assert all(not plan["flags"][name] for name in JOB_NAMES)
    assert "quality_fixtures" not in plan["commands"]


def test_embedded_c_plan_keeps_ihp130_smoke_and_full_pytest() -> None:
    plan = create_plan(plan_args(["crt/src/hal/gpio.c"]))
    assert plan["flags"]["quality_fixtures"] is True
    assert plan["flags"]["regression_smoke"] is True
    assert plan["flags"]["regression_ihp130"] is True
    assert plan["flags"]["regression_gf180"] is False
    assert plan["flags"]["development_environment"] is False
    assert any("configs/ci/ihp130-tiny.mk" in command for command in plan["commands"]["regression_ihp130"])


def test_tiny_plan_excludes_unsupported_pdks() -> None:
    plan = create_plan(plan_args(["rtl/tiny/top/retrosoc_tiny_asic.sv"]))
    assert plan["flags"]["regression_ihp130"] is True
    assert plan["flags"]["regression_ics55"] is True
    assert plan["flags"]["regression_gf180"] is False
    assert plan["flags"]["regression_sky130"] is False
    assert all("TINY_RUN=" not in command for command in plan["commands"]["regression_ihp130"])
    assert all("TINY_RUN=" not in command for command in plan["commands"]["regression_ics55"])


def test_full_event_and_unknown_paths_fail_closed() -> None:
    full = create_plan(plan_args(["README.md"], event="push"))
    unknown = create_plan(plan_args(["unregistered/file.xyz"]))
    assert any("TINY_RUN=timeout --foreground 14400s" in command for command in full["commands"]["regression_ihp130"])
    for plan in (full, unknown):
        assert plan["selected_policy"] == "full"
        assert plan["flags"]["development_environment"] is True
        assert all(plan["flags"][name] for name in JOB_NAMES if name != "skill_eval")


def test_empty_change_does_not_schedule_heavy_work() -> None:
    plan = create_plan(plan_args([]))
    assert plan["selected_policy"] == "empty"
    assert all(not plan["flags"][name] for name in JOB_NAMES)


def test_github_outputs_and_context_are_machine_readable(tmp_path: Path) -> None:
    output = tmp_path / "github-output"
    plan = create_plan(plan_args(["README.md"]))
    write_github_outputs(plan, output)
    assert "classification=documentation\n" in output.read_text(encoding="utf-8")
    assert "regression_ihp130=false\n" in output.read_text(encoding="utf-8")

    context = agent_context(ROOT)
    assert context["hosted_behavioral_only"] is True
    assert context["metrics_mode"] == "observe"
    assert any(profile["path"] == "configs/ci/ics55-tiny.mk" and profile["soc"] == "TINY" for profile in context["profiles"])
    json.dumps(context)


def test_repository_documentation_links_and_duplicate_blocks() -> None:
    assert documentation_issues(ROOT) == []


def test_documentation_checker_exempts_only_generated_inputs(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs/guide.md").write_text(
        "[build](../build/artifact.json)\n"
        "[managed](../rtl/managed/mpw/ip/user.sv)\n"
        "[missing](missing.md)\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "-C", str(tmp_path), "add", "docs/guide.md"], check=True)
    issues = documentation_issues(tmp_path)
    assert len(issues) == 1
    assert "missing.md" in issues[0]
    assert "build/artifact.json" not in issues[0]
    assert "managed/mpw" not in issues[0]


def test_scope_issues_enforce_allowed_and_forbidden_paths() -> None:
    from scripts.agent_control import scope_issues

    task = valid_task()
    assert scope_issues(task, ["docs/engineering.md"]) == []
    issues = scope_issues(task, ["rtl/tiny/top/tiny_sram.sv", "scripts/regress.py"])
    assert issues == [
        "path is forbidden by task scope: rtl/tiny/top/tiny_sram.sv",
        "path is outside the task scope: rtl/tiny/top/tiny_sram.sv",
        "path is outside the task scope: scripts/regress.py",
    ]


def test_tiny_snapshot_uses_real_reviewed_inventory() -> None:
    from scripts.agent_control import tiny_snapshot_status

    result = tiny_snapshot_status(ROOT)
    assert result["status"] == "PASS", result
    assert result["technical_source_count"] > 250
    assert result["changed_files"] == []


def test_tiny_snapshot_reports_drift_and_recovery(monkeypatch: pytest.MonkeyPatch) -> None:
    import scripts.agent_control as control

    monkeypatch.setattr(
        "publications.tiny_reference.collect",
        lambda config, check_snapshot: {
            "source_paths": ["docs/engineering.md", "publications/tiny_reference.py", "dependencies/dependencies.lock.json"]
        },
    )
    monkeypatch.setattr(control, "git_output", lambda root, *arguments: "docs/engineering.md")
    drift = control.tiny_snapshot_status(ROOT)
    assert drift["status"] == "FAIL"
    assert drift["changed_files"] == ["docs/engineering.md"]

    monkeypatch.setattr(control, "git_output", lambda root, *arguments: "")
    assert control.tiny_snapshot_status(ROOT)["status"] == "PASS"


def test_preflight_binds_task_plan_and_optional_github_probe(tmp_path: Path) -> None:
    from scripts.agent_control import create_preflight

    task = valid_task()
    task["base_revision"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    task["scope"]["allowed_paths"] = []
    packet = tmp_path / "task.json"
    packet.write_text(json.dumps(task), encoding="utf-8")
    args = SimpleNamespace(
        root=ROOT,
        task=packet,
        base=None,
        head="HEAD",
        mode="auto",
        event="local",
        online=False,
        repository="retroSoC/retroSoC",
        base_branch="dev",
        pr=None,
    )
    result = create_preflight(args)
    assert result["status"] == "READY", result["issues"]
    assert result["task_id"] == task["task_id"]
    assert result["validation_plan"]["base"] == task["base_revision"]
    assert result["reviewed_source_snapshot"]["status"] == "PASS"
    assert result["github"]["status"] == "NOT_RUN"
    assert len(result["dependency_lock_sha256"]) == 64
    assert result["tools"] == [{"name": "git", "status": "PASS"}, {"name": "python3", "status": "PASS"}]


def test_github_preflight_is_explicit_about_pending_and_permissions(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.agent_control import github_preflight

    args = SimpleNamespace(online=True, repository="retroSoC/retroSoC", base_branch="dev", pr=None)
    monkeypatch.setattr("scripts.pr_workflow.required_check_contexts", lambda repository, base, root: ["quality-gate"])
    assert github_preflight(ROOT, args)["status"] == "PASS"

    args.pr = 239
    monkeypatch.setattr(
        "scripts.pr_workflow.checks_report",
        lambda root, number, repository, required: {"status": "PENDING", "head_sha": "b" * 40},
    )
    pending = github_preflight(ROOT, args)
    assert pending["status"] == "PENDING"
    assert pending["head_sha"] == "b" * 40

    monkeypatch.setattr(
        "scripts.pr_workflow.required_check_contexts",
        lambda repository, base, root: (_ for _ in ()).throw(RuntimeError("HTTP 403")),
    )
    blocked = github_preflight(ROOT, args)
    assert blocked["status"] == "BLOCKED"
    assert blocked["issues"] == ["HTTP 403"]

    monkeypatch.setattr(
        "scripts.pr_workflow.required_check_contexts",
        lambda repository, base, root: (_ for _ in ()).throw(OSError("gh is unavailable")),
    )
    assert github_preflight(ROOT, args)["issues"] == ["gh is unavailable"]


def test_preflight_rejects_dirty_workspace_write(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import scripts.agent_control as control

    task = valid_task()
    task["base_revision"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    task["scope"]["allowed_paths"] = []
    task["execution"]["mode"] = "workspace-write"
    packet = tmp_path / "task.json"
    packet.write_text(json.dumps(task), encoding="utf-8")
    args = SimpleNamespace(
        root=ROOT,
        task=packet,
        base=None,
        head="HEAD",
        mode="auto",
        event="local",
        online=False,
        repository="retroSoC/retroSoC",
        base_branch="dev",
        pr=None,
    )
    real_git_output = control.git_output

    def dirty_status(root: Path, *arguments: str) -> str:
        if arguments[0] == "status":
            return " M scripts/example.py"
        return real_git_output(root, *arguments)

    monkeypatch.setattr(control, "git_output", dirty_status)
    result = control.create_preflight(args)
    assert result["status"] == "BLOCKED"
    assert "workspace-write preflight requires a clean worktree before execution" in result["issues"]


def test_local_tool_probe_requires_gh_only_for_online_checks(monkeypatch: pytest.MonkeyPatch) -> None:
    import scripts.agent_control as control

    monkeypatch.setattr(control.shutil, "which", lambda name: None if name == "gh" else f"/usr/bin/{name}")
    assert control.local_tool_status(False) == [
        {"name": "git", "status": "PASS"},
        {"name": "python3", "status": "PASS"},
    ]
    assert control.local_tool_status(True)[-1] == {"name": "gh", "status": "BLOCKED"}


def test_handoff_preserves_evidence_process_state_and_next_action(tmp_path: Path) -> None:
    from scripts.agent_control import build_handoff, write_handoff_markdown

    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "handoff@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "Handoff"], check=True)
    (tmp_path / "README.md").write_text("initial\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(tmp_path), "add", "README.md"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "initial"], check=True)
    (tmp_path / "quality").mkdir()
    (tmp_path / "quality/validation-gaps.json").write_text('{"schema_version": 1, "gaps": []}\n', encoding="utf-8")
    revision = subprocess.check_output(["git", "-C", str(tmp_path), "rev-parse", "HEAD"], text=True).strip()
    task = valid_task()
    task["base_revision"] = revision
    task["status"] = "review"
    task["evidence"] = [
        {"kind": "unit", "uri": "build/tasks/docs-engineering-control/result.json", "status": "PASS"},
        {"kind": "netlist", "uri": "build/tasks/docs-engineering-control/netlist.json", "status": "NOT_RUN"},
    ]
    result = tmp_path / task["execution"]["artifact_root"] / "result.json"
    result.parent.mkdir(parents=True)
    result.write_text(
        json.dumps({"status": "passed", "source_revision": revision, "run_id": "run-1", "child_cleanup_pending": False}),
        encoding="utf-8",
    )
    document = build_handoff(task, tmp_path, "Continue with the missing netlist evidence")
    assert document["status"] == "review"
    assert document["evidence_counts"] == {"PASS": 1, "FAIL": 0, "SKIPPED": 0, "NOT_RUN": 1}
    assert document["next_action"] == "Continue with the missing netlist evidence"
    assert document["artifacts"][0]["source_revision"] == revision
    assert document["processes"][0]["child_cleanup_pending"] is False
    assert document["known_gaps"] == []
    markdown = tmp_path / "build/handoff.md"
    write_handoff_markdown(document, markdown, tmp_path)
    assert "NOT_RUN" in markdown.read_text(encoding="utf-8")

    task["evidence"].append({"kind": "failed", "uri": "build/failed.json", "status": "FAIL"})
    blocked = build_handoff(task, tmp_path, "Diagnose the failed evidence")
    assert blocked["status"] == "blocked"
    assert "handoff contains failed evidence" in blocked["issues"]


def test_gap_resolution_requires_an_explicit_task_declaration(tmp_path: Path) -> None:
    from scripts.agent_control import create_preflight

    task = valid_task()
    task["base_revision"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    task["target_socs"] = ["MINI"]
    task["validation"]["pdks"] = ["IHP130"]
    task["acceptance"] = ["Complete synthesis and netlist evidence"]
    task["scope"]["allowed_paths"] = []
    packet = tmp_path / "task.json"
    args = SimpleNamespace(
        root=ROOT,
        task=packet,
        base=None,
        head="HEAD",
        mode="auto",
        event="local",
        online=False,
        repository="retroSoC/retroSoC",
        base_branch="dev",
        pr=None,
    )
    packet.write_text(json.dumps(task), encoding="utf-8")
    blocked = create_preflight(args)
    assert blocked["status"] == "BLOCKED"
    assert any("mini-yosys-backend" in issue for issue in blocked["issues"])

    task["resolves_gaps"] = ["mini-yosys-backend"]
    packet.write_text(json.dumps(task), encoding="utf-8")
    resolving = create_preflight(args)
    assert resolving["status"] == "READY", resolving["issues"]
    assert resolving["resolving_gaps"] == ["mini-yosys-backend"]
