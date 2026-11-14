from __future__ import annotations

import json
import subprocess
from pathlib import Path

from scripts.agent_control import validate_task
from scripts.agent_dag import (
    acquire_lease,
    build_plan,
    graph_issues,
    reconcile_lease,
)

ROOT = Path(__file__).resolve().parents[1]


def task(identifier: str, mode: str = "read-only", parallel: bool = True) -> dict:
    artifact = f"build/tasks/{identifier}"
    execution = {
        "mode": mode,
        "worktree": f"build/agent-worktrees/{identifier}" if mode == "workspace-write" else ".",
        "artifact_root": artifact,
    }
    if mode == "workspace-write":
        execution["approval"] = {
            "approved_by": "@maksyuki",
            "reference": "test approval",
            "plan_sha256": "a" * 64,
        }
    return {
        "schema_version": 1,
        "task_id": identifier,
        "task_class": "tooling",
        "base_revision": "a" * 40,
        "target_socs": [],
        "scope": {
            "summary": f"Task {identifier}",
            "allowed_paths": ["scripts/**", "docs/**", "build/**"],
            "forbidden_paths": ["rtl/**"],
            "non_goals": [],
        },
        "acceptance": ["Preserve evidence"],
        "validation": {"risk": "low", "mode": "affected", "profiles": [], "pdks": []},
        "execution": execution,
        "status": "approved",
        "evidence": [{"kind": "unit", "uri": f"{artifact}/result.json", "status": "PASS"}],
        "coordination": {
            "depends_on": [],
            "inputs": [],
            "outputs": [f"{artifact}/result.json"],
            "write_set": [f"scripts/{identifier}.py", f"{artifact}/**"] if mode == "workspace-write" else [],
            "lease": {"owner": "main-agent", "ttl_seconds": 60},
            "idempotency_key": f"key-{identifier}-0001",
            "budget": {"timeout_seconds": 600, "max_runner_minutes": 30},
            "retry": {"max_attempts": 2, "backoff_seconds": 1, "categories": ["infrastructure_failure"]},
            "attempt": 1,
            "integrator": "main-integrator",
            "allow_parallel": parallel,
        },
    }


def graph(tasks: list[dict], authorized: bool = True) -> dict:
    return {
        "schema_version": 1,
        "graph_id": "demo",
        "integrator": "main-integrator",
        "multi_agent_authorized": authorized,
        "tasks": tasks,
    }


def test_only_authorized_disjoint_tasks_can_run_in_parallel() -> None:
    document = graph([task("read-a"), task("read-b")])
    first = build_plan(document, ROOT)
    assert first["status"] == "READY"
    assert len(first["waves"]) == 1
    assert first["waves"][0]["parallel"] is True
    assert first["subagents_started"] is False
    assert first["integrator"]["mode"] == "serial"
    assert first == build_plan(document, ROOT)

    writes = graph([task("write-a", "workspace-write"), task("write-b", "workspace-write")])
    assert build_plan(writes, ROOT)["waves"][0]["parallel"] is True
    writes["tasks"][1]["coordination"]["allow_parallel"] = False
    groups = build_plan(writes, ROOT)["waves"]
    assert len(groups) == 2
    assert all(not group["parallel"] for group in groups)

    writes["multi_agent_authorized"] = False
    groups = build_plan(writes, ROOT)["waves"]
    assert len(groups) == 2
    assert all(not group["parallel"] for group in groups)


def test_dependency_completion_requires_pass_evidence() -> None:
    dependent = task("dependent")
    dependent["coordination"]["depends_on"] = ["base"]
    document = graph([task("base"), dependent])
    assert build_plan(document, ROOT)["waves"][0]["tasks"][0]["task_id"] == "base"
    assert build_plan(document, ROOT)["waiting"][0]["task_id"] == "dependent"

    document["tasks"][0]["status"] = "done"
    plan = build_plan(document, ROOT)
    assert plan["waves"][0]["tasks"][0]["task_id"] == "dependent"
    assert plan["completed"][0]["task_id"] == "base"
    document["tasks"][0]["evidence"][0]["status"] = "NOT_RUN"
    blocked = build_plan(document, ROOT)
    assert blocked["status"] == "BLOCKED"
    assert any("done requires only PASS evidence" in issue for issue in blocked["issues"])


def test_graph_rejects_cycles_overlaps_and_shared_mutable_state() -> None:
    first = task("write-a", "workspace-write")
    second = task("write-b", "workspace-write")
    first["coordination"]["depends_on"] = [second["task_id"]]
    second["coordination"]["depends_on"] = [first["task_id"]]
    assert any("dependency cycle" in issue for issue in graph_issues(graph([first, second]), ROOT))

    first = task("write-a", "workspace-write")
    second = task("write-b", "workspace-write")
    first["coordination"]["write_set"][0] = "scripts/shared.py"
    second["coordination"]["write_set"][0] = "scripts/shared.py"
    second["execution"]["worktree"] = first["execution"]["worktree"]
    second["execution"]["artifact_root"] = first["execution"]["artifact_root"]
    second["coordination"]["idempotency_key"] = first["coordination"]["idempotency_key"]
    issues = graph_issues(graph([first, second]), ROOT)
    assert any("overlapping write_sets" in issue for issue in issues)
    assert any("share a mutable Git worktree" in issue for issue in issues)
    assert any("share a mutable artifact root" in issue for issue in issues)
    assert any("duplicate idempotency key" in issue for issue in issues)

    incomplete = graph([task("valid")])
    incomplete["tasks"].append({"task_id": "missing-coordination"})
    blocked = build_plan(incomplete, ROOT)
    assert blocked["status"] == "BLOCKED"
    assert blocked["issues"]


def test_coordination_rejects_unsafe_paths_scopes_and_retries() -> None:
    candidate = task("candidate", "workspace-write")
    candidate["coordination"]["write_set"][0] = "../escape"
    candidate["coordination"]["outputs"][0] = "../outside.json"
    assert validate_task(candidate, ROOT)

    candidate = task("candidate", "workspace-write")
    candidate["scope"]["allowed_paths"] = ["docs/**"]
    assert any("outside scope.allowed_paths" in issue for issue in validate_task(candidate, ROOT))

    candidate = task("candidate")
    candidate["coordination"]["retry"]["categories"] = ["source_or_test_failure"]
    assert any("only infrastructure_failure" in issue for issue in validate_task(candidate, ROOT))
    candidate["coordination"]["retry"]["max_attempts"] = 1
    assert any("require more than one attempt" in issue for issue in validate_task(candidate, ROOT))
    candidate["coordination"]["idempotency_key"] = 42
    assert validate_task(candidate, ROOT)

    legacy = task("legacy")
    del legacy["coordination"]
    assert validate_task(legacy, ROOT) == []
    schema = json.loads((ROOT / ".agents/task.schema.json").read_text(encoding="utf-8"))
    assert "coordination" in schema["properties"]
    assert "resume_from" in schema["properties"]["coordination"]["properties"]
    dag_schema = json.loads((ROOT / ".agents/dag.schema.json").read_text(encoding="utf-8"))
    assert dag_schema["properties"]["tasks"]["items"]["$ref"] == "task.schema.json"


def test_lease_is_dry_run_by_default_and_reconciles_identity(tmp_path: Path) -> None:
    document = graph([task("read-a")])
    dry = acquire_lease(tmp_path, document, "read-a", None, False)
    assert dry["status"] == "WOULD_ACQUIRE"
    assert not (tmp_path / "build/agent-leases/demo/read-a.json").exists()

    acquired = acquire_lease(tmp_path, document, "read-a", None, True)
    assert acquired["status"] == "ACQUIRED"
    path = tmp_path / "build/agent-leases/demo/read-a.json"
    assert path.is_file()
    active = acquire_lease(tmp_path, document, "read-a", None, True)
    assert active["status"] == "BLOCKED"
    assert reconcile_lease(tmp_path, document, "read-a", "wrong", False, False)["status"] == "BLOCKED"
    assert path.is_file()
    assert reconcile_lease(tmp_path, document, "read-a", acquired["lease_id"], False, True)["status"] == "WOULD_HEARTBEAT"
    assert reconcile_lease(tmp_path, document, "read-a", acquired["lease_id"], True, False)["status"] == "RELEASED"
    assert not path.exists()
    replacement = acquire_lease(tmp_path, document, "read-a", None, True)
    assert replacement["lease_id"] != acquired["lease_id"]


def test_lease_requires_authorization_and_completed_dependencies(tmp_path: Path) -> None:
    dependent = task("dependent")
    dependent["coordination"]["depends_on"] = ["base"]
    document = graph([task("base"), dependent])
    waiting = acquire_lease(tmp_path, document, "dependent", None, False)
    assert waiting["status"] == "WAITING_DEPENDENCY"
    document["tasks"][0]["status"] = "done"
    assert acquire_lease(tmp_path, document, "dependent", None, True)["status"] == "ACQUIRED"

    unauthorized = graph([task("read-a")], authorized=False)
    blocked = acquire_lease(tmp_path, unauthorized, "read-a", None, True)
    assert blocked["status"] == "BLOCKED"
    assert any("not authorized" in issue for issue in blocked["issues"])
    planned = graph([task("read-a")])
    planned["tasks"][0]["status"] = "planned"
    assert acquire_lease(tmp_path, planned, "read-a", None, False)["status"] == "BLOCKED"


def test_expired_lease_is_retained_and_replaced(tmp_path: Path) -> None:
    document = graph([task("read-a")])
    original = acquire_lease(tmp_path, document, "read-a", None, True)
    path = tmp_path / "build/agent-leases/demo/read-a.json"
    current = json.loads(path.read_text(encoding="utf-8"))
    current["expires_at"] = "2000-01-01T00:00:00+00:00"
    path.write_text(json.dumps(current), encoding="utf-8")
    assert reconcile_lease(tmp_path, document, "read-a", original["lease_id"], False, True)["status"] == "BLOCKED"
    replacement = acquire_lease(tmp_path, document, "read-a", None, True)
    assert replacement["status"] == "ACQUIRED"
    assert replacement["lease_id"] != original["lease_id"]
    expired = list(path.parent.glob("*.expired"))
    assert len(expired) == 1
    assert json.loads(expired[0].read_text(encoding="utf-8"))["lease_id"] == original["lease_id"]


def test_cli_emits_plan_without_starting_agents(tmp_path: Path) -> None:
    packet = tmp_path / "graph.json"
    packet.write_text(json.dumps(graph([task("read-a"), task("read-b")])), encoding="utf-8")
    completed = subprocess.run(
        ["python3", str(ROOT / "scripts/agent_dag.py"), "plan", "--graph", str(packet)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    result = json.loads(completed.stdout)
    assert result["execution"] == "plan-only"
    assert result["subagents_started"] is False
    assert result["waves"][0]["parallel"] is True


def test_plan_does_not_dispatch_unapproved_review_or_blocked_tasks() -> None:
    approved = task("approved")
    planned = task("planned")
    planned["status"] = "planned"
    review = task("review")
    review["status"] = "review"
    blocked = task("blocked")
    blocked["status"] = "blocked"
    document = graph([approved, planned, review, blocked])
    plan = build_plan(document, ROOT)
    assert plan["status"] == "BLOCKED"
    assert plan["waves"] == []
    document["tasks"].pop()
    recovered = build_plan(document, ROOT)
    assert recovered["status"] == "READY"
    assert [item["task_id"] for wave in recovered["waves"] for item in wave["tasks"]] == ["approved"]
    assert {item["task_id"]: item["status"] for item in recovered["waiting"]} == {
        "planned": "WAITING_APPROVAL",
        "review": "REVIEW",
    }
