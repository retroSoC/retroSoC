from __future__ import annotations

import json
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
