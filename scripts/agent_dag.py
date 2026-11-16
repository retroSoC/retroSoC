#!/usr/bin/env python3
"""Plan agent task DAGs and reconcile bounded leases without launching agents."""

from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import (  # noqa: E402
    TASK_ID_RE,
    emit_json,
    read_json,
    safe_relative_path,
    validate_task,
)
from scripts.flow_control import Lease, pid_matches  # noqa: E402

COORDINATION_FIELDS = {
    "depends_on",
    "inputs",
    "outputs",
    "write_set",
    "lease",
    "idempotency_key",
    "budget",
    "retry",
    "attempt",
    "integrator",
    "allow_parallel",
}
GRAPH_FIELDS = {"schema_version", "graph_id", "integrator", "multi_agent_authorized", "tasks"}
SUCCESS_STATUSES = {
    "READY",
    "WOULD_ACQUIRE",
    "WOULD_RELEASE",
    "WOULD_HEARTBEAT",
    "ACQUIRED",
    "RELEASED",
    "HEARTBEAT",
}


def string_list(value: Any, label: str, issues: list[str], *, unique: bool = True) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        issues.append(f"{label} must be a list of non-empty strings")
        return []
    if unique and len(set(value)) != len(value):
        issues.append(f"{label} must not contain duplicates")
    return value


def validate_coordination(task: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    coordination = task.get("coordination")
    if not isinstance(coordination, dict):
        return ["coordination must be an object"]
    unknown = sorted(set(coordination) - COORDINATION_FIELDS - {"resume_from"})
    missing = sorted(COORDINATION_FIELDS - set(coordination))
    if unknown:
        issues.append(f"coordination has unknown fields: {unknown}")
    if missing:
        issues.append(f"coordination is missing fields: {missing}")
        return issues
    for field in ("depends_on", "inputs", "outputs", "write_set"):
        values = string_list(coordination[field], f"coordination.{field}", issues)
        if not isinstance(coordination[field], list):
            return issues
        if any(not safe_relative_path(item) for item in values):
            issues.append(f"coordination.{field} contains an unsafe path")
    if any(not TASK_ID_RE.fullmatch(item) for item in coordination["depends_on"]):
        issues.append("coordination.depends_on must contain lowercase task IDs")
    if any(not item.startswith("build/") for item in coordination["outputs"]):
        issues.append("coordination.outputs must stay below build/")
    resume_from = coordination.get("resume_from")
    if resume_from is not None and (
        not isinstance(resume_from, str) or not resume_from.startswith("build/") or not safe_relative_path(resume_from)
    ):
        issues.append("coordination.resume_from must be a safe build/ path")
    for field in ("idempotency_key", "integrator"):
        if not isinstance(coordination[field], str) or not coordination[field].strip():
            issues.append(f"coordination.{field} must be non-empty")
    if isinstance(coordination["idempotency_key"], str) and not 8 <= len(coordination["idempotency_key"]) <= 128:
        issues.append("coordination.idempotency_key must contain 8-128 characters")
    if not isinstance(coordination["allow_parallel"], bool):
        issues.append("coordination.allow_parallel must be boolean")

    lease = coordination["lease"]
    if not isinstance(lease, dict) or set(lease) != {"owner", "ttl_seconds"}:
        issues.append("coordination.lease must contain owner and ttl_seconds")
    else:
        if not isinstance(lease["owner"], str) or not lease["owner"].strip():
            issues.append("coordination.lease.owner must be non-empty")
        if not isinstance(lease["ttl_seconds"], int) or isinstance(lease["ttl_seconds"], bool) or not 1 <= lease["ttl_seconds"] <= 86400:
            issues.append("coordination.lease.ttl_seconds must be between 1 and 86400")
    budget = coordination["budget"]
    if not isinstance(budget, dict) or set(budget) != {"timeout_seconds", "max_runner_minutes"}:
        issues.append("coordination.budget must contain timeout_seconds and max_runner_minutes")
    else:
        for field, minimum, maximum in (("timeout_seconds", 60, 86400), ("max_runner_minutes", 1, 10080)):
            value = budget[field]
            if not isinstance(value, int) or isinstance(value, bool) or not minimum <= value <= maximum:
                issues.append(f"coordination.budget.{field} must be between {minimum} and {maximum}")
    retry = coordination["retry"]
    if not isinstance(retry, dict) or set(retry) != {"max_attempts", "backoff_seconds", "categories"}:
        issues.append("coordination.retry must contain max_attempts, backoff_seconds, and categories")
    else:
        attempts = retry["max_attempts"]
        if not isinstance(attempts, int) or isinstance(attempts, bool) or not 1 <= attempts <= 3:
            issues.append("coordination.retry.max_attempts must be between 1 and 3")
        backoff = retry["backoff_seconds"]
        if not isinstance(backoff, int) or isinstance(backoff, bool) or not 0 <= backoff <= 3600:
            issues.append("coordination.retry.backoff_seconds must be between 0 and 3600")
        categories = string_list(retry["categories"], "coordination.retry.categories", issues)
        if any(item != "infrastructure_failure" for item in categories):
            issues.append("coordination.retry allows only infrastructure_failure")
        if isinstance(attempts, int) and not isinstance(attempts, bool):
            if attempts == 1 and categories:
                issues.append("retry categories require more than one attempt")
            if attempts > 1 and not categories:
                issues.append("multiple attempts require an explicit retry category")
        if not isinstance(coordination["attempt"], int) or isinstance(coordination["attempt"], bool) or coordination["attempt"] < 1:
            issues.append("coordination.attempt must be a positive integer")
        elif isinstance(attempts, int) and coordination["attempt"] > attempts:
            issues.append("coordination.attempt exceeds retry.max_attempts")

    mode = task["execution"]["mode"]
    write_set = coordination["write_set"]
    if mode == "workspace-write":
        if not write_set:
            issues.append("workspace-write coordination requires a non-empty write_set")
        if not task["execution"]["worktree"].startswith("build/agent-worktrees/"):
            issues.append("workspace-write coordination requires an isolated canonical worktree")
    elif write_set:
        issues.append("read-only coordination must have an empty write_set")
    allowed = task["scope"]["allowed_paths"]
    forbidden = task["scope"]["forbidden_paths"]
    for path in write_set:
        if allowed and not any(fnmatch.fnmatch(path, pattern) for pattern in allowed):
            issues.append(f"write_set path is outside scope.allowed_paths: {path}")
        if any(fnmatch.fnmatch(path, pattern) for pattern in forbidden):
            issues.append(f"write_set path is forbidden: {path}")
    for path in coordination["outputs"]:
        if write_set and not any(fnmatch.fnmatch(path, pattern) for pattern in write_set):
            issues.append(f"output is outside the declared write_set: {path}")
    return sorted(set(issues))


def depends_on(tasks: dict[str, dict[str, Any]], first: str, second: str) -> bool:
    pending = list(tasks[first]["coordination"]["depends_on"])
    seen = set()
    while pending:
        current = pending.pop()
        if current == second:
            return True
        if current in seen or current not in tasks:
            continue
        seen.add(current)
        pending.extend(tasks[current]["coordination"]["depends_on"])
    return False


def graph_issues(document: Any, root: Path) -> list[str]:
    if not isinstance(document, dict):
        return ["task graph must be an object"]
    issues = []
    unknown = sorted(set(document) - GRAPH_FIELDS - {"description"})
    missing = sorted(GRAPH_FIELDS - set(document))
    if unknown:
        issues.append(f"task graph has unknown fields: {unknown}")
    if missing:
        issues.append(f"task graph is missing fields: {missing}")
        return issues
    if document["schema_version"] != 1:
        issues.append("task graph schema_version must be 1")
    if not isinstance(document["graph_id"], str) or not TASK_ID_RE.fullmatch(document["graph_id"]):
        issues.append("task graph_id must be lowercase kebab-case")
    if not isinstance(document["integrator"], str) or not document["integrator"].strip():
        issues.append("task graph requires exactly one integrator")
    if not isinstance(document["multi_agent_authorized"], bool):
        issues.append("task graph multi_agent_authorized must be boolean")
    raw_tasks = document["tasks"]
    if not isinstance(raw_tasks, list) or not raw_tasks:
        issues.append("task graph requires a non-empty tasks list")
        return issues
    if len(raw_tasks) > 200:
        issues.append("task graph is limited to 200 tasks")
        return issues
    tasks: dict[str, dict[str, Any]] = {}
    idempotency_keys = set()
    output_owners = {}
    for task in raw_tasks:
        if not isinstance(task, dict):
            issues.append("every graph task must be an object")
            continue
        identifier = task.get("task_id", "<unknown>")
        task_errors = validate_task(task, root)
        for issue in task_errors:
            issues.append(f"{identifier}: {issue}")
        if identifier in tasks:
            issues.append(f"duplicate task ID: {identifier}")
            continue
        coordination = task.get("coordination")
        if not isinstance(coordination, dict):
            issues.append(f"{identifier}: coordination is required in a task graph")
        if task_errors or not isinstance(coordination, dict):
            continue
        tasks[identifier] = task
        if coordination.get("integrator") != document["integrator"]:
            issues.append(f"{identifier}: task integrator must match the graph integrator")
        key = coordination.get("idempotency_key")
        if key in idempotency_keys:
            issues.append(f"duplicate idempotency key: {key}")
        idempotency_keys.add(key)
        for output in coordination.get("outputs", []):
            if output in output_owners:
                issues.append(f"output {output} is produced by both {output_owners[output]} and {identifier}")
            output_owners[output] = identifier
    for identifier, task in tasks.items():
        dependencies = task["coordination"]["depends_on"]
        for dependency in dependencies:
            if dependency == identifier or dependency not in tasks:
                issues.append(f"{identifier}: unknown or self dependency: {dependency}")
        if task["status"] == "done" and (
            not task.get("evidence") or any(item["status"] != "PASS" for item in task["evidence"])
        ):
            issues.append(f"{identifier}: done requires only PASS evidence")
        if task["status"] == "blocked":
            issues.append(f"{identifier}: task is explicitly blocked")
    for first, task in tasks.items():
        pending = list(task["coordination"]["depends_on"])
        seen = set()
        while pending:
            current = pending.pop()
            if current == first:
                issues.append(f"dependency cycle includes {first}")
                break
            if current in seen or current not in tasks:
                continue
            seen.add(current)
            pending.extend(tasks[current]["coordination"]["depends_on"])
    write_tasks = [task for task in tasks.values() if task["execution"]["mode"] == "workspace-write"]
    for index, first in enumerate(write_tasks):
        for second in write_tasks[index + 1 :]:
            first_id = first["task_id"]
            second_id = second["task_id"]
            if first["execution"]["worktree"] == second["execution"]["worktree"]:
                issues.append(f"{first_id} and {second_id} share a mutable Git worktree")
            if first["execution"]["artifact_root"] == second["execution"]["artifact_root"]:
                issues.append(f"{first_id} and {second_id} share a mutable artifact root")
            overlap = any(
                fnmatch.fnmatch(left, right) or fnmatch.fnmatch(right, left)
                for left in first["coordination"]["write_set"]
                for right in second["coordination"]["write_set"]
            )
            if overlap and not (
                depends_on(tasks, first_id, second_id) or depends_on(tasks, second_id, first_id)
            ):
                issues.append(f"{first_id} and {second_id} have overlapping write_sets without serialization")
    return sorted(set(issues))


def task_record(task: dict[str, Any], status: str) -> dict[str, Any]:
    coordination = task["coordination"]
    return {
        "task_id": task["task_id"],
        "status": status,
        "mode": task["execution"]["mode"],
        "worktree": task["execution"]["worktree"],
        "artifact_root": task["execution"]["artifact_root"],
        "idempotency_key": coordination["idempotency_key"],
        "attempt": coordination["attempt"],
        "depends_on": coordination["depends_on"],
        "write_set": coordination["write_set"],
        "allow_parallel": coordination["allow_parallel"],
    }


def build_plan(document: dict[str, Any], root: Path) -> dict[str, Any]:
    issues = graph_issues(document, root)
    if issues:
        return {
            "schema_version": 1,
            "graph_id": document.get("graph_id") if isinstance(document, dict) else None,
            "status": "BLOCKED",
            "execution": "plan-only",
            "subagents_started": False,
            "multi_agent_authorized": document.get("multi_agent_authorized") if isinstance(document, dict) else False,
            "integrator": {
                "id": document.get("integrator") if isinstance(document, dict) else None,
                "mode": "serial",
            },
            "source_revisions": sorted(
                {
                    task["base_revision"]
                    for task in document.get("tasks", [])
                    if isinstance(task, dict) and isinstance(task.get("base_revision"), str)
                }
            ) if isinstance(document, dict) else [],
            "waves": [],
            "waiting": [],
            "completed": [],
            "issues": issues,
        }
    tasks = {task["task_id"]: task for task in document["tasks"]}
    done = {identifier for identifier, task in tasks.items() if task["status"] == "done"}
    ready = [
        tasks[identifier]
        for identifier in sorted(tasks)
        if identifier not in done
        and tasks[identifier]["status"] in {"approved", "in_progress"}
        and set(tasks[identifier]["coordination"]["depends_on"]) <= done
    ]
    ready_ids = {task["task_id"] for task in ready}
    waiting = [
        task_record(
            tasks[identifier],
            "WAITING_DEPENDENCY"
            if not set(tasks[identifier]["coordination"]["depends_on"]) <= done
            else "WAITING_APPROVAL"
            if tasks[identifier]["status"] == "planned"
            else "REVIEW"
            if tasks[identifier]["status"] == "review"
            else "BLOCKED",
        )
        for identifier in sorted(tasks)
        if identifier not in done and identifier not in ready_ids
    ]
    candidates = [
        task
        for task in ready
        if document["multi_agent_authorized"]
        and (task["execution"]["mode"] == "read-only" or task["coordination"]["allow_parallel"])
    ]
    candidate_ids = {task["task_id"] for task in candidates}
    groups = []
    if candidates:
        groups.append({"parallel": len(candidates) > 1, "tasks": [task_record(task, "READY") for task in candidates]})
    for task in ready:
        if task["task_id"] not in candidate_ids:
            groups.append({"parallel": False, "tasks": [task_record(task, "READY")]})
    return {
        "schema_version": 1,
        "graph_id": document["graph_id"],
        "status": "BLOCKED" if issues else "READY",
        "execution": "plan-only",
        "subagents_started": False,
        "multi_agent_authorized": document["multi_agent_authorized"],
        "integrator": {"id": document["integrator"], "mode": "serial"},
        "source_revisions": sorted({task["base_revision"] for task in tasks.values()}),
        "waves": groups,
        "waiting": waiting,
        "completed": [task_record(tasks[identifier], "DONE") for identifier in sorted(done)],
        "issues": issues,
    }


def graph_task(document: dict[str, Any], task_id: str, root: Path) -> dict[str, Any]:
    plan = build_plan(document, root)
    if plan["issues"]:
        raise ValueError("; ".join(plan["issues"]))
    tasks = {task["task_id"]: task for task in document["tasks"]}
    if task_id not in tasks:
        raise ValueError(f"unknown task: {task_id}")
    return tasks[task_id]


def lease_path(root: Path, document: dict[str, Any], task_id: str) -> Path:
    return root / "build/agent-leases" / document["graph_id"] / f"{task_id}.json"


def lease_expiry(document: dict[str, Any]) -> datetime:
    try:
        expiry = datetime.fromisoformat(document["expires_at"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("lease has an invalid expires_at") from error
    if expiry.tzinfo is None:
        raise ValueError("lease expiry must include a timezone")
    return expiry.astimezone(timezone.utc)


def current_lease(root: Path, document: dict[str, Any], task_id: str) -> dict[str, Any] | None:
    path = lease_path(root, document, task_id)
    if not path.is_file():
        return None
    current = read_json(path)
    expiry = lease_expiry(current)
    return {**current, "expired": expiry <= datetime.now(timezone.utc)}


def lease_gate(document: dict[str, Any], task: dict[str, Any], execute: bool) -> dict[str, Any] | None:
    if execute and not document["multi_agent_authorized"]:
        return {"status": "BLOCKED", "issues": ["multi-agent execution is not authorized by the graph"]
        }
    if task["status"] not in {"approved", "in_progress"}:
        return {"status": "BLOCKED", "issues": [f"task status {task['status']} cannot acquire a lease"]}
    if any(
        next(item for item in document["tasks"] if item["task_id"] == dependency)["status"] != "done"
        for dependency in task["coordination"]["depends_on"]
    ):
        return {"status": "WAITING_DEPENDENCY", "issues": ["task dependencies are not complete"]}
    return None


def acquire_lease(
    root: Path,
    document: dict[str, Any],
    task_id: str,
    owner: str | None,
    execute: bool,
) -> dict[str, Any]:
    task = graph_task(document, task_id, root)
    gate = lease_gate(document, task, execute)
    if gate:
        return gate
    coordination = task["coordination"]
    expected_owner = coordination["lease"]["owner"]
    if owner is not None and owner != expected_owner:
        raise ValueError(f"lease owner must be {expected_owner}")
    path = lease_path(root, document, task_id)
    current = current_lease(root, document, task_id)
    active = current and not current["expired"] and pid_matches(
        current.get("parent_pid"), current.get("parent_start_ticks")
    )
    if active:
        return {"status": "BLOCKED", "issues": ["an active lease already exists"], "lease_id": current["lease_id"], "path": str(path)}
    if not execute:
        return {"status": "WOULD_ACQUIRE", "task_id": task_id, "owner": expected_owner, "path": str(path)}
    if current and current["expired"]:
        os.replace(path, path.with_name(f"{path.name}.{current['lease_id']}.expired"))
    expires_at = (datetime.now(timezone.utc) + timedelta(seconds=coordination["lease"]["ttl_seconds"])).isoformat()
    lease = Lease(
        path,
        {
            "schema_version": 1,
            "graph_id": document["graph_id"],
            "task_id": task_id,
            "integrator": document["integrator"],
            "owner": expected_owner,
            "idempotency_key": coordination["idempotency_key"],
            "attempt": coordination["attempt"],
            "expires_at": expires_at,
        },
    ).acquire()
    return {
        "status": "ACQUIRED",
        "task_id": task_id,
        "owner": expected_owner,
        "lease_id": lease.lease_id,
        "attempt": coordination["attempt"],
        "idempotency_key": coordination["idempotency_key"],
        "expires_at": expires_at,
        "path": str(path),
    }


def reconcile_lease(
    root: Path,
    document: dict[str, Any],
    task_id: str,
    lease_id: str,
    execute: bool,
    heartbeat: bool,
) -> dict[str, Any]:
    task = graph_task(document, task_id, root)
    if execute and not document["multi_agent_authorized"]:
        return {"status": "BLOCKED", "issues": ["multi-agent execution is not authorized by the graph"]}
    path = lease_path(root, document, task_id)
    current = current_lease(root, document, task_id)
    if current is None:
        return {"status": "NOT_FOUND", "issues": ["lease does not exist"]}
    if current["lease_id"] != lease_id:
        return {"status": "BLOCKED", "issues": ["lease identity does not match"], "lease_id": current["lease_id"]}
    if current["owner"] != task["coordination"]["lease"]["owner"]:
        return {"status": "BLOCKED", "issues": ["lease owner does not match the task contract"]}
    if current["expired"]:
        return {"status": "BLOCKED", "issues": ["lease has expired"], "lease_id": lease_id}
    action = "HEARTBEAT" if heartbeat else "RELEASE"
    if not execute:
        return {"status": f"WOULD_{action}", "task_id": task_id, "lease_id": lease_id}
    lease = Lease(path, {})
    lease.lease_id = lease_id
    if heartbeat:
        lease.heartbeat()
    else:
        lease.release()
    return {"status": action if heartbeat else "RELEASED", "task_id": task_id, "lease_id": lease_id, "path": str(path)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan")
    plan.add_argument("--graph", type=Path, required=True)
    plan.add_argument("--output", type=Path)
    for name in ("acquire", "release", "heartbeat"):
        command = subparsers.add_parser(name)
        command.add_argument("--graph", type=Path, required=True)
        command.add_argument("--task", required=True)
        command.add_argument("--output", type=Path)
        if name == "acquire":
            command.add_argument("--owner")
        else:
            command.add_argument("--lease-id", required=True)
        command.add_argument("--execute", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = args.root.resolve()
        document = read_json(args.graph)
        if args.command == "plan":
            result = build_plan(document, root)
        elif args.command == "acquire":
            result = acquire_lease(root, document, args.task, args.owner, args.execute)
        else:
            result = reconcile_lease(
                root,
                document,
                args.task,
                args.lease_id,
                args.execute,
                heartbeat=args.command == "heartbeat",
            )
        emit_json(result, args.output)
        return int(result["status"] not in SUCCESS_STATUSES)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"agent dag: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
