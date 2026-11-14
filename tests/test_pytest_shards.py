from __future__ import annotations

import copy
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

from scripts.pytest_shards import (
    build_plan,
    collect_node_ids,
    duration_history,
    junit_key,
    load_policy,
    run_shard,
    verify_report,
    verify_shards,
)

ROOT = Path(__file__).resolve().parents[1]
IDS = [f"tests/test_example.py::test_case_{index}" for index in range(8)]
IDS.append("tests/test_example.py::TestGroup::test_parametrized[free form\\nvalue]")


def policy(shards: int = 2) -> dict:
    return {
        "schema_version": 1,
        "shards": shards,
        "durations_path": "quality/pytest-durations.json",
        "expected_skips": {IDS[1]: "optional dependency"},
    }


def history() -> dict:
    return {
        "schema_version": 1,
        "source_revision": "a" * 40,
        "default_duration_seconds": 1.0,
        "durations": {IDS[0]: 100.0, IDS[1]: 80.0, IDS[2]: 40.0},
    }


def write_junit(path: Path, node_ids: list[str], skipped: dict[str, str] | None = None) -> None:
    suite = ET.Element("testsuite", tests=str(len(node_ids)), failures="0", errors="0")
    for node_id in node_ids:
        classname, name = junit_key(node_id)
        case = ET.SubElement(suite, "testcase", classname=classname, name=name, time="1.25")
        if skipped and node_id in skipped:
            ET.SubElement(case, "skipped", message=skipped[node_id])
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(path, encoding="utf-8")


def write_shard(root: Path, plan: dict, index: int, node_ids: list[str], skipped: dict[str, str] | None = None) -> Path:
    directory = root / f"shard-{index}"
    directory.mkdir(parents=True)
    selected = copy.deepcopy(plan)
    selected["shards"][index]["node_ids"] = node_ids
    (directory / "plan.json").write_text(json.dumps(selected), encoding="utf-8")
    write_junit(directory / "junit.xml", node_ids, skipped)
    (directory / "run.json").write_text(
        json.dumps(
            {
                "shard_index": index,
                "status": "passed",
                "exit_code": 0,
                "plan_sha256": __import__("hashlib").sha256((directory / "plan.json").read_bytes()).hexdigest(),
                "junit_sha256": __import__("hashlib").sha256((directory / "junit.xml").read_bytes()).hexdigest(),
                "issues": [],
            }
        ),
        encoding="utf-8",
    )
    (directory / "cache.json").write_text(
        json.dumps({"caches": [{"name": "sources", "status": "HIT"}, {"name": "tools", "status": "MISS"}]}),
        encoding="utf-8",
    )
    return directory


def test_lpt_shards_are_deterministic_complete_and_nonempty() -> None:
    plan = build_plan(IDS, policy(), history())
    assert plan == build_plan(list(reversed(IDS)), policy(), history())
    assert [shard["index"] for shard in plan["shards"]] == [0, 1]
    assert sorted(node_id for shard in plan["shards"] for node_id in shard["node_ids"]) == sorted(IDS)
    assert all(shard["node_ids"] == sorted(shard["node_ids"]) for shard in plan["shards"])
    assert sum(shard["estimated_seconds"] for shard in plan["shards"]) == pytest.approx(226.0)


def test_plan_rejects_duplicate_empty_or_unfillable_collections() -> None:
    with pytest.raises(ValueError, match="unique"):
        build_plan([*IDS, IDS[0]], policy(), history())
    with pytest.raises(ValueError, match="non-empty"):
        build_plan([], policy(), history())
    with pytest.raises(ValueError, match="cannot fill"):
        build_plan(IDS[:2], policy(4), history())
    with pytest.raises(ValueError, match="valid"):
        build_plan(["../outside.py::test_escape"], policy(1), history())


def test_junit_mapping_supports_classes_and_parametrized_cases() -> None:
    assert junit_key("tests/test_example.py::TestGroup::test_case[param-1]") == (
        "tests.test_example.TestGroup",
        "test_case[param-1]",
    )
    assert junit_key("tests/test_example.py::test_case[DPkg::Lock::Timeout]") == (
        "tests.test_example",
        "test_case[DPkg::Lock::Timeout]",
    )


def test_report_rejects_missing_duplicate_and_unexpected_skip(tmp_path: Path) -> None:
    plan = build_plan(IDS, policy(), history())
    assigned = plan["shards"][0]["node_ids"]
    report = tmp_path / "junit.xml"
    write_junit(report, assigned, {IDS[1]: "optional dependency unavailable"} if IDS[1] in assigned else None)
    assert verify_report(plan, 0, report, policy())["issues"] == []

    write_junit(report, [*assigned, assigned[0]])
    assert any("duplicate JUnit" in issue for issue in verify_report(plan, 0, report, policy())["issues"])
    write_junit(report, assigned[:-1])
    assert any("coverage differs" in issue for issue in verify_report(plan, 0, report, policy())["issues"])
    write_junit(report, assigned, {assigned[0]: "new environment gap"})
    assert any("unexpected skip" in issue for issue in verify_report(plan, 0, report, policy())["issues"])


def test_fan_in_reconciles_all_shards_and_rejects_inconsistent_evidence(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    (root / "quality").mkdir(parents=True)
    (root / "quality/pytest-shards.json").write_text(json.dumps(policy()), encoding="utf-8")
    plan = build_plan(IDS, policy(), history())
    directories = [
        write_shard(root, plan, index, shard["node_ids"])
        for index, shard in enumerate(plan["shards"])
    ]
    result = verify_shards(root, directories)
    assert result["status"] == "passed"
    assert result["test_count"] == len(IDS)
    assert result["shard_count"] == 2
    assert result["cache_hit_count"] == 2
    assert result["cache_miss_count"] == 2

    duplicate = verify_shards(root, [directories[0], directories[0]])
    assert duplicate["status"] == "failed"
    assert any("duplicate shard index" in issue for issue in duplicate["issues"])
    missing = verify_shards(root, directories[:1])
    assert any("expected 2 shard directories" in issue for issue in missing["issues"])

    stale_plan = json.loads((directories[0] / "plan.json").read_text(encoding="utf-8"))
    stale_plan["source_revision"] = "b" * 40
    (directories[0] / "plan.json").write_text(json.dumps(stale_plan), encoding="utf-8")
    stale = verify_shards(root, directories)
    assert stale["status"] == "failed"
    assert any("plan mismatch" in issue or "plan hash" in issue for issue in stale["issues"])


def test_run_executes_exactly_the_assigned_node_ids(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root = tmp_path / "repo"
    (root / "quality").mkdir(parents=True)
    (root / "quality/pytest-shards.json").write_text(json.dumps(policy(1)), encoding="utf-8")
    (root / "quality/pytest-durations.json").write_text(json.dumps(history()), encoding="utf-8")
    (root / "pyproject.toml").write_text("[tool.pytest.ini_options]\n", encoding="utf-8")
    (root / "requirements").mkdir()
    (root / "requirements/ci.txt").write_text("pytest==9.2.0\n", encoding="utf-8")
    monkeypatch.setattr("scripts.pytest_shards.collect_node_ids", lambda _root: IDS)
    monkeypatch.setattr("scripts.pytest_shards.git_output", lambda *args: "c" * 40)
    monkeypatch.setattr("importlib.metadata.version", lambda name: "9.2.0")

    def execute(command: list[str], cwd: Path, check: bool) -> subprocess.CompletedProcess:
        assert cwd == root
        assert check is False
        selected = command[command.index("--durations-min=0.1") + 1 :]
        assert selected == sorted(IDS)
        junit = Path(next(value.split("=", 1)[1] for value in command if value.startswith("--junitxml=")))
        write_junit(junit, selected)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(subprocess, "run", execute)
    result = run_shard(root, 0, tmp_path / "result")
    assert result["status"] == "passed"
    assert result["test_count"] == len(IDS)


def test_repository_collection_matches_duration_history_and_policy() -> None:
    node_ids = collect_node_ids(ROOT)
    assert node_ids == collect_node_ids(ROOT)
    loaded = load_policy(ROOT)
    durations = json.loads((ROOT / loaded["durations_path"]).read_text(encoding="utf-8"))
    assert len(set(node_ids) & set(durations["durations"])) >= 2600
    assert set(loaded["expected_skips"]) <= set(node_ids)
    plan = build_plan(node_ids, loaded, durations)
    assert plan["test_count"] >= 2600
    assert len(plan["shards"]) == 4


def test_duration_import_requires_complete_matching_junit(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("scripts.pytest_shards.collect_node_ids", lambda _root: IDS)
    report = tmp_path / "junit.xml"
    write_junit(report, IDS)
    document = duration_history(ROOT, report, "a" * 40, "12345")
    assert set(document["durations"]) == set(IDS)
    write_junit(report, IDS[:-1])
    subset = duration_history(ROOT, report, "a" * 40, "12345")
    assert set(subset["durations"]) == set(IDS[:-1])
    document = ET.parse(report)
    document.getroot().set("tests", str(len(IDS)))
    document.write(report, encoding="utf-8")
    with pytest.raises(ValueError, match="complete, nonempty, successful"):
        duration_history(ROOT, report, "a" * 40, "12345")


def test_ci_preserves_coverage_and_required_gates() -> None:
    import yaml

    quality = yaml.safe_load((ROOT / ".github/workflows/quality.yml").read_text(encoding="utf-8"))
    fixtures = quality["jobs"]["fixtures"]
    assert fixtures["strategy"]["fail-fast"] is False
    assert fixtures["strategy"]["matrix"]["shard"] == [0, 1, 2, 3]
    fan_in = quality["jobs"]["fixtures-fan-in"]
    assert fan_in["needs"] == ["impact", "fixtures"]
    assert fan_in["if"].startswith("always()")
    assert "fixtures-fan-in" in quality["jobs"]["quality-gate"]["needs"]
    download = next(step for step in fan_in["steps"] if step["name"] == "Download every fixture shard")
    assert download["uses"].startswith("actions/download-artifact@37930b1c")
    assert "quality-fixture-shard-*" in download["with"]["pattern"]

    reusable = yaml.load((ROOT / ".github/workflows/_regression.yml").read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    products = reusable["on"]["workflow_call"]["inputs"]["products"]
    assert products["default"] == '["ALL"]'
    assert reusable["jobs"]["regression"]["strategy"]["fail-fast"] == "false"
    ics55 = yaml.safe_load((ROOT / ".github/workflows/regression-ics55.yml").read_text(encoding="utf-8"))
    caller = ics55["jobs"]["ics55-open-source-flows"]
    assert caller["with"]["products"] == '["MINI", "TINY"]'
    full_flow = (ROOT / ".github/workflows/full-flow.yml").read_text(encoding="utf-8")
    nightly = (ROOT / ".github/workflows/nightly.yml").read_text(encoding="utf-8")
    assert "products:" not in full_flow
    assert "products:" not in nightly
