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


def test_hosted_fixture_profile_is_explicit_and_fail_closed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from scripts.agent_control import create_preflight

    task = valid_task()
    task["execution"]["fixture_profile"] = "hosted-pytest"
    assert validate_task(task, ROOT) == []
    assert "Fixture profile: hosted-pytest" in render_task_prompt(task)
    task["execution"]["fixture_profile"] = "all"
    assert "execution.fixture_profile must be hosted-pytest" in validate_task(task, ROOT)
    task["execution"]["fixture_profile"] = "hosted-pytest"
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
    monkeypatch.setattr("scripts.fixture_control.fixture_profile", lambda root, reference: {"profile": "hosted-pytest"})
    monkeypatch.setattr(
        "scripts.fixture_control.doctor",
        lambda root, profile: {"status": "BLOCKED", "issues": ["missing locked source"], "checks": []},
    )
    blocked = create_preflight(args)
    assert blocked["status"] == "BLOCKED"
    assert blocked["fixture"]["status"] == "BLOCKED"
    assert blocked["issues"] == ["fixture: missing locked source"]

    monkeypatch.setattr(
        "scripts.fixture_control.doctor",
        lambda root, profile: {"status": "READY", "issues": [], "checks": []},
    )
    ready = create_preflight(args)
    assert ready["status"] == "READY", ready["issues"]
    assert ready["fixture"]["status"] == "READY"


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


def test_engineering_control_shadow_is_candidate_only_and_escalates() -> None:
    plan = create_plan(
        plan_args(["scripts/pr_delivery.py", "scripts/README.md", "tests/test_pr_delivery.py"])
    )
    shadow = plan["engineering_control_shadow"]
    assert shadow["status"] == "ELIGIBLE"
    assert shadow["authoritative"] is False
    assert shadow["changes_applied"] is False
    assert shadow["candidate_flags"]["quality_fixtures"] is True
    assert set(shadow["would_skip"]) == {
        "regression_smoke",
        "regression_ihp130",
        "regression_gf180",
        "regression_ics55",
        "regression_sky130",
        "development_environment",
    }
    assert plan["flags"]["regression_smoke"] is True
    assert "regression_smoke" in plan["commands"]

    for path in (
        "Makefile",
        "rtl/mini/top/retrosoc.sv",
        "publications/build_datasheet.py",
        "quality/engineering-control-impact.json",
    ):
        candidate = create_plan(plan_args([path]))
        shadow = candidate["engineering_control_shadow"]
        assert shadow["status"] == "FULL_REQUIRED"
        assert shadow["candidate_flags"] == candidate["flags"]
        assert shadow["would_skip"] == []
        assert shadow["changes_applied"] is False

    fragment = create_plan(plan_args(["scripts/mk/agent.mk"]))
    assert fragment["selected_policy"] == "full"
    assert fragment["engineering_control_shadow"]["status"] == "ELIGIBLE"
    assert fragment["flags"]["regression_smoke"] is True


def test_engineering_control_shadow_preserves_already_minimal_plans() -> None:
    plan = create_plan(plan_args([".agents/README.md"]))
    shadow = plan["engineering_control_shadow"]
    assert plan["selected_policy"] == "agents"
    assert shadow["status"] == "NOT_NEEDED"
    assert shadow["candidate_flags"] == plan["flags"]
    assert shadow["would_skip"] == []


def test_engineering_control_shadow_policy_failure_is_fail_closed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import scripts.agent_control as control

    flags = dict(load_impact(ROOT)["job_policy"]["full"], quality_fast=True)
    monkeypatch.setattr(
        control,
        "load_engineering_control_policy",
        lambda root: (_ for _ in ()).throw(OSError("policy unavailable")),
    )
    shadow = control.engineering_control_shadow(ROOT, ["scripts/pr_delivery.py"], flags)
    assert shadow["status"] == "FULL_REQUIRED"
    assert shadow["candidate_flags"] == flags
    assert shadow["would_skip"] == []
    assert shadow["issues"] == ["policy unavailable"]
    assert shadow["changes_applied"] is False


def test_engineering_control_policy_rejects_wildcards_and_quality_reduction(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import scripts.agent_control as control

    policy = {
        "schema_version": 1,
        "mode": "shadow",
        "allowed_paths": ["scripts/**"],
        "preserved_flags": ["quality_fast", "quality_fixtures", "skill_eval"],
        "disabled_flags": sorted(control.ENGINEERING_CONTROL_DISABLED),
    }
    monkeypatch.setattr(control, "read_json", lambda path: policy)
    with pytest.raises(ValueError, match="unique exact safe paths"):
        control.load_engineering_control_policy(ROOT)
    policy["allowed_paths"] = ["scripts/pr_delivery.py"]
    policy["preserved_flags"] = ["quality_fast"]
    with pytest.raises(ValueError, match="must preserve quality"):
        control.load_engineering_control_policy(ROOT)


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
    for event in ("push", "schedule", "workflow_dispatch"):
        plan = create_plan(plan_args(["README.md"], event=event))
        assert all("TINY_RUN=" not in command for command in plan["commands"]["regression_ihp130"])
        assert all("TINY_RUN=" not in command for command in plan["commands"]["regression_ics55"])
    full_mode = create_plan(plan_args(["README.md"], mode="full"))
    assert all("TINY_RUN=" not in command for command in full_mode["commands"]["regression_ihp130"])
    assert all("TINY_RUN=" not in command for command in full_mode["commands"]["regression_ics55"])
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
        lambda config, check_snapshot, layout: {
            "source_paths": ["docs/engineering.md", "publications/tiny_reference.py", "dependencies/dependencies.lock.json"]
        },
    )
    monkeypatch.setattr(control, "git_output", lambda root, *arguments: "docs/engineering.md")
    drift = control.tiny_snapshot_status(ROOT)
    assert drift["status"] == "FAIL"
    assert drift["changed_files"] == ["docs/engineering.md"]

    monkeypatch.setattr(control, "git_output", lambda root, *arguments: "")
    assert control.tiny_snapshot_status(ROOT)["status"] == "PASS"


def test_mini_snapshot_uses_real_reviewed_control_and_ci_metadata() -> None:
    from scripts.agent_control import mini_snapshot_status

    result = mini_snapshot_status(ROOT, required=True)
    assert result["status"] == "PASS", result
    assert len(result["source_revision"]) == 40
    assert result["ci_checked_at"]
    assert result["ci_run_count"] >= 1
    assert result["fixture_restore"] == "NOT_RUN"
    assert result["managed_inputs"] == "NOT_REQUESTED"
    assert mini_snapshot_status(ROOT, required=False)["status"] == "NOT_REQUESTED"


def test_mini_snapshot_rejects_stale_control_without_repair(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.agent_control import mini_snapshot_status

    monkeypatch.setattr(
        "publications.build_datasheet.validate_source_snapshot",
        lambda config: (_ for _ in ()).throw(ValueError("Makefile differs from the explicit build-control review")),
    )
    result = mini_snapshot_status(ROOT, required=True)
    assert result["status"] == "FAIL"
    assert result["issues"] == ["Makefile differs from the explicit build-control review"]
    assert result["fixture_restore"] == "NOT_RUN"


def test_mini_snapshot_rejects_mismatched_ci_evidence(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.agent_control import mini_snapshot_status

    monkeypatch.setattr("publications.build_datasheet.validate_source_snapshot", lambda config: None)
    monkeypatch.setattr(
        "publications.dev_reference.validate_ci_snapshot",
        lambda snapshot, revision: (_ for _ in ()).throw(ValueError("CI snapshot must identify the reviewed revision")),
    )
    result = mini_snapshot_status(ROOT, required=True)
    assert result["status"] == "FAIL"
    assert result["issues"] == ["CI snapshot must identify the reviewed revision"]


def test_mini_snapshot_reports_unavailable_metadata(monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.agent_control import mini_snapshot_status

    monkeypatch.setattr(
        "publications.build_datasheet.read_json",
        lambda path: (_ for _ in ()).throw(OSError("Mini metadata unavailable")),
    )
    result = mini_snapshot_status(ROOT, required=True)
    assert result["status"] == "BLOCKED"
    assert result["issues"] == ["Mini metadata unavailable"]


def test_preflight_applies_mini_check_only_to_selected_fixtures(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import scripts.agent_control as control

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
    selected = {"value": True}
    required_values = []
    monkeypatch.setattr(
        control,
        "create_plan",
        lambda arguments: {"changed_files": [], "flags": {"quality_fixtures": selected["value"]}},
    )

    def mini_result(root: Path, required: bool) -> dict:
        required_values.append(required)
        return {
            "status": "FAIL" if required else "NOT_REQUESTED",
            "issues": ["stale Mini control"] if required else [],
        }

    monkeypatch.setattr(control, "mini_snapshot_status", mini_result)
    blocked = control.create_preflight(args)
    assert blocked["status"] == "BLOCKED"
    assert blocked["mini_source_snapshot"]["status"] == "FAIL"
    assert "mini: stale Mini control" in blocked["issues"]

    selected["value"] = False
    ready = control.create_preflight(args)
    assert ready["status"] == "READY", ready["issues"]
    assert ready["mini_source_snapshot"]["status"] == "NOT_REQUESTED"
    assert required_values == [True, False]


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


def test_preflight_merge_conflicts_block_delivery(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import scripts.agent_control as control

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
        merge_check=True,
        merge_ref="origin/dev",
    )
    monkeypatch.setattr(
        "scripts.merge_preflight.merge_conflict_scan",
        lambda root, reference: {
            "status": "CONFLICT",
            "merge_ref": reference,
            "merge_revision": "b" * 40,
            "unmerged_paths": ["scripts/example.py"],
            "worktree_removed": True,
            "merge_commit_created": False,
        },
    )
    real_git_output = control.git_output
    monkeypatch.setattr(
        control,
        "git_output",
        lambda root, *arguments: "" if arguments[0] == "status" else real_git_output(root, *arguments),
    )

    result = control.create_preflight(args)

    assert result["status"] == "BLOCKED"
    assert result["merge_check"]["unmerged_paths"] == ["scripts/example.py"]
    assert result["issues"] == ["merge check conflicts with origin/dev: scripts/example.py"]


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

    handoff_path = tmp_path / task["execution"]["artifact_root"] / "handoff.json"
    handoff_path.write_text(json.dumps(document), encoding="utf-8")
    repeated = build_handoff(task, tmp_path, "Repeat only the required handoff", exclude_paths={handoff_path})
    assert repeated["status"] == "review"
    assert all(item["path"] != handoff_path.relative_to(tmp_path).as_posix() for item in repeated["artifacts"])

    result.write_text(json.dumps({"status": "passed", "source_revision": "0" * 40}), encoding="utf-8")
    stale = build_handoff(task, tmp_path, "Reject stale passing evidence")
    assert stale["status"] == "blocked"
    assert any("different source revision" in issue for issue in stale["issues"])

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


def scope_git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def scope_repository(root: Path) -> str:
    subprocess.run(["git", "init", "-q", "-b", "dev", str(root)], check=True)
    scope_git(root, "config", "user.email", "scope@example.invalid")
    scope_git(root, "config", "user.name", "Scope Check")
    (root / ".gitignore").write_text("build/\n", encoding="utf-8")
    (root / "docs").mkdir()
    (root / "docs/engineering.md").write_text("initial\n", encoding="utf-8")
    (root / "scripts").mkdir()
    (root / "scripts/tool.py").write_text("initial = True\n", encoding="utf-8")
    (root / "rtl/tiny/top").mkdir(parents=True)
    (root / "rtl/tiny/top/tiny_sram.sv").write_text("initial\n", encoding="utf-8")
    scope_git(root, "add", ".gitignore", "docs/engineering.md", "scripts/tool.py", "rtl/tiny/top/tiny_sram.sv")
    scope_git(root, "commit", "-qm", "initial")
    return scope_git(root, "rev-parse", "HEAD").stdout.strip()


def scope_packet(root: Path, revision: str, allowed: list[str]) -> Path:
    task = valid_task()
    task["task_id"] = "staged-scope-test"
    task["base_revision"] = revision
    task["scope"]["allowed_paths"] = allowed
    packet = root / "build/tasks/staged-scope-test/task.json"
    packet.parent.mkdir(parents=True, exist_ok=True)
    packet.write_text(json.dumps(task), encoding="utf-8")
    return packet


def test_staged_scope_check_uses_index_only_and_rejects_out_of_scope(tmp_path: Path) -> None:
    from scripts.agent_control import staged_scope_check

    root = tmp_path / "repo"
    revision = scope_repository(root)
    packet = scope_packet(root, revision, ["docs/engineering.md"])
    (root / "docs/engineering.md").write_text("staged\n", encoding="utf-8")
    (root / "scripts/tool.py").write_text("staged = True\n", encoding="utf-8")
    scope_git(root, "add", "docs/engineering.md")

    ready = staged_scope_check(root, packet)
    assert ready["status"] == "READY"
    assert ready["staged_files"] == ["docs/engineering.md"]
    assert ready["diff_base"] == "HEAD"
    assert ready["read_only"] is True
    assert ready["merge_check"] == "NOT_RUN"
    assert ready["fixture_restore"] == "NOT_RUN"

    scope_git(root, "add", "scripts/tool.py")
    blocked = staged_scope_check(root, packet)
    assert blocked["status"] == "BLOCKED"
    assert blocked["staged_files"] == ["docs/engineering.md", "scripts/tool.py"]
    assert blocked["issues"] == ["path is outside the task scope: scripts/tool.py"]


def test_staged_scope_check_uses_merge_base_for_explicit_base(tmp_path: Path) -> None:
    from scripts.agent_control import staged_scope_check

    root = tmp_path / "repo"
    revision = scope_repository(root)
    scope_git(root, "switch", "-qc", "ci/staged")
    (root / "docs/engineering.md").write_text("topic\n", encoding="utf-8")
    scope_git(root, "add", "docs/engineering.md")
    scope_git(root, "commit", "-qm", "topic")
    scope_git(root, "switch", "-q", "dev")
    (root / "rtl/upstream.sv").write_text("upstream\n", encoding="utf-8")
    scope_git(root, "add", "rtl/upstream.sv")
    scope_git(root, "commit", "-qm", "upstream")
    scope_git(root, "update-ref", "refs/remotes/origin/dev", "refs/heads/dev")
    scope_git(root, "switch", "-q", "ci/staged")
    (root / "scripts/tool.py").write_text("staged = True\n", encoding="utf-8")
    scope_git(root, "add", "scripts/tool.py")
    packet = scope_packet(root, revision, ["docs/**", "scripts/**"])

    result = staged_scope_check(root, packet, base="origin/dev")

    assert result["status"] == "READY"
    assert result["base"] == "origin/dev"
    assert result["diff_base"] == revision
    assert result["staged_files"] == ["docs/engineering.md", "scripts/tool.py"]
    assert "rtl/upstream.sv" not in result["staged_files"]


def test_staged_scope_check_rejects_forbidden_unmerged_and_invalid_inputs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import scripts.agent_control as control

    root = tmp_path / "repo"
    revision = scope_repository(root)
    packet = scope_packet(root, revision, [])
    (root / "rtl/tiny/top/tiny_sram.sv").write_text("changed\n", encoding="utf-8")
    scope_git(root, "add", "rtl/tiny/top/tiny_sram.sv")
    forbidden = control.staged_scope_check(root, packet)
    assert forbidden["status"] == "BLOCKED"
    assert forbidden["issues"] == ["path is forbidden by task scope: rtl/tiny/top/tiny_sram.sv"]

    task = json.loads(packet.read_text(encoding="utf-8"))
    task["scope"]["allowed_paths"] = ["rtl/**"]
    task["scope"]["forbidden_paths"] = []
    packet.write_text(json.dumps(task), encoding="utf-8")
    real_git_output = control.git_output

    def unmerged(root: Path, *arguments: str) -> str:
        if arguments[:3] == ("diff", "--name-only", "--diff-filter=U"):
            return "rtl/conflict.sv\n"
        return real_git_output(root, *arguments)

    monkeypatch.setattr(control, "git_output", unmerged)
    conflict = control.staged_scope_check(root, packet)
    assert conflict["status"] == "BLOCKED"
    assert conflict["unmerged_paths"] == ["rtl/conflict.sv"]
    assert conflict["issues"] == ["staged scope check has unmerged paths: rtl/conflict.sv"]

    with pytest.raises(ValueError, match="must not be empty or an option"):
        control.staged_scope_check(root, packet, base="--help")
    outside = control.staged_scope_check(root / "docs", packet)
    assert outside["status"] == "BLOCKED"
    assert outside["staged_files"] == []
    assert outside["diff_base"] is None


def test_staged_scope_check_is_empty_for_unstaged_files_and_never_calls_heavy_operations(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from scripts.agent_control import staged_scope_check

    root = tmp_path / "repo"
    revision = scope_repository(root)
    packet = scope_packet(root, revision, ["docs/engineering.md"])
    (root / "scripts/untracked.py").write_text("untracked = True\n", encoding="utf-8")
    monkeypatch.setattr(
        "scripts.merge_preflight.merge_conflict_scan",
        lambda *args: pytest.fail("staged scope check must not run a merge dry-run"),
    )
    monkeypatch.setattr(
        "scripts.fixture_control.restore",
        lambda *args: pytest.fail("staged scope check must not restore fixtures"),
    )

    result = staged_scope_check(root, packet)

    assert result["status"] == "READY"
    assert result["staged_files"] == []


def test_make_agent_scope_check_is_explicit_and_read_only() -> None:
    completed = subprocess.run(
        ["make", "-s", "-n", "agent-scope-check", "TASK=build/tasks/example/task.json", "BASE=origin/dev"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    assert "agent_control.py scope-check" in completed.stdout
    assert "--base origin/dev" in completed.stdout
    assert "--merge-check" not in completed.stdout
    assert "fixture_control.py restore" not in completed.stdout
