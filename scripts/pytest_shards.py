#!/usr/bin/env python3
"""Collect, schedule, execute, and reconcile deterministic Pytest shards."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, git_output, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

NODE_ID = re.compile(r"^tests/[^\s]+\.py::.+$")
REVISION = re.compile(r"^[0-9a-f]{40}$")


def digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document_digest(document: Any) -> str:
    return digest_text(json.dumps(document, sort_keys=True, separators=(",", ":")))


def load_policy(root: Path) -> dict[str, Any]:
    policy = read_json(root / "quality/pytest-shards.json")
    if policy.get("schema_version") != 1 or not isinstance(policy.get("shards"), int):
        raise ValueError("Pytest shard policy requires schema_version=1 and an integer shard count")
    if not 1 <= policy["shards"] <= 16:
        raise ValueError("Pytest shard count must be between 1 and 16")
    durations_path = Path(policy.get("durations_path", ""))
    if durations_path.is_absolute() or ".." in durations_path.parts:
        raise ValueError("duration history path must remain repository-relative")
    expected = policy.get("expected_skips", {})
    if not isinstance(expected, dict) or any(
        not NODE_ID.fullmatch(node_id) or not isinstance(reason, str) or not reason
        for node_id, reason in expected.items()
    ):
        raise ValueError("expected skips must map exact test node IDs to non-empty reasons")
    return policy


def collect_node_ids(root: Path) -> list[str]:
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", "-p", "no:cacheprovider"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    lines = [line.strip() for line in result.stdout.splitlines()]
    node_ids = [line for line in lines if NODE_ID.fullmatch(line)]
    if result.returncode or not node_ids:
        raise RuntimeError(
            f"Pytest collection failed ({result.returncode}): "
            f"{result.stdout[-2000:]}\n{result.stderr[-2000:]}"
        )
    if len(node_ids) != len(set(node_ids)):
        raise ValueError("Pytest collection returned duplicate node IDs")
    return sorted(node_ids)


def load_durations(root: Path, policy: dict[str, Any]) -> dict[str, Any]:
    history = read_json(root / policy["durations_path"])
    if history.get("schema_version") != 1 or not REVISION.fullmatch(history.get("source_revision", "")):
        raise ValueError("duration history must identify its source revision")
    durations = history.get("durations")
    if not isinstance(durations, dict) or any(
        not NODE_ID.fullmatch(node_id) or not isinstance(seconds, (int, float))
        or isinstance(seconds, bool) or seconds < 0
        for node_id, seconds in durations.items()
    ):
        raise ValueError("duration history contains invalid node IDs or durations")
    default = history.get("default_duration_seconds")
    if not isinstance(default, (int, float)) or isinstance(default, bool) or default <= 0:
        raise ValueError("duration history requires a positive default duration")
    return history


def build_plan(
    node_ids: list[str],
    policy: dict[str, Any],
    history: dict[str, Any],
    source_revision: str = "0" * 40,
) -> dict[str, Any]:
    if not node_ids or len(node_ids) != len(set(node_ids)) or any(not NODE_ID.fullmatch(item) for item in node_ids):
        raise ValueError("shard planning requires unique, valid, non-empty test node IDs")
    if len(node_ids) < policy["shards"]:
        raise ValueError("test count cannot fill every requested shard")
    ordered = sorted(node_ids)
    weights = history["durations"]
    default = history["default_duration_seconds"]
    shards = [{"index": index, "node_ids": [], "estimated_seconds": 0.0} for index in range(policy["shards"])]
    for node_id in sorted(ordered, key=lambda item: (-float(weights.get(item, default)), item)):
        shard = min(shards, key=lambda item: (item["estimated_seconds"], item["index"]))
        shard["node_ids"].append(node_id)
        shard["estimated_seconds"] = round(shard["estimated_seconds"] + float(weights.get(node_id, default)), 3)
    for shard in shards:
        shard["node_ids"].sort()
        if not shard["node_ids"]:
            raise ValueError("deterministic scheduling produced an empty shard")
    return {
        "schema_version": 1,
        "source_revision": source_revision,
        "shard_count": len(shards),
        "test_count": len(ordered),
        "node_ids": ordered,
        "node_ids_sha256": digest_text("\n".join(ordered)),
        "policy_sha256": document_digest(policy),
        "durations_sha256": document_digest(history),
        "shards": shards,
    }


def create_plan(root: Path) -> dict[str, Any]:
    policy = load_policy(root)
    history = load_durations(root, policy)
    plan = build_plan(collect_node_ids(root), policy, history, git_output(root, "rev-parse", "HEAD"))
    plan["pytest_version"] = importlib.metadata.version("pytest")
    plan["tool_inputs_sha256"] = digest_text(
        "\n".join(file_digest(root / path) for path in ("pyproject.toml", "requirements/ci.txt"))
    )
    return plan


def junit_key(node_id: str) -> tuple[str, str]:
    filename, remainder = node_id.split("::", 1)
    qualified, bracket, parameters = remainder.partition("[")
    parts = qualified.split("::")
    module = filename.removesuffix(".py").replace("/", ".")
    return ".".join([module, *parts[:-1]]), parts[-1] + bracket + parameters


def junit_records(
    path: Path,
    expected_ids: list[str],
    allow_unexpected: bool = False,
) -> tuple[list[dict[str, Any]], list[str]]:
    try:
        tree = ET.parse(path)
    except (OSError, ET.ParseError) as error:
        return [], [f"cannot parse JUnit report {path}: {error}"]
    expected = {junit_key(node_id): node_id for node_id in expected_ids}
    if len(expected) != len(expected_ids):
        return [], ["JUnit node-id mapping is ambiguous"]
    records = []
    issues = []
    seen = set()
    for case in tree.getroot().findall(".//testcase"):
        key = (case.get("classname", ""), case.get("name", ""))
        node_id = expected.get(key)
        if node_id is None:
            if not allow_unexpected:
                issues.append(f"unexpected JUnit testcase: {key[0]}::{key[1]}")
            continue
        if node_id in seen:
            issues.append(f"duplicate JUnit testcase: {node_id}")
            continue
        seen.add(node_id)
        skipped = case.find("skipped")
        failure = case.find("failure")
        error = case.find("error")
        status = "skipped" if skipped is not None else "failed" if failure is not None or error is not None else "passed"
        records.append(
            {
                "node_id": node_id,
                "status": status,
                "duration_seconds": float(case.get("time", "0")),
                "skip_reason": skipped.get("message", "") if skipped is not None else None,
            }
        )
    return records, issues


def verify_report(
    plan: dict[str, Any],
    shard_index: int,
    report: Path,
    policy: dict[str, Any],
) -> dict[str, Any]:
    shards = [item for item in plan["shards"] if item["index"] == shard_index]
    if len(shards) != 1:
        return {"issues": [f"unknown or duplicate shard index: {shard_index}"], "records": []}
    assigned = shards[0]["node_ids"]
    records, issues = junit_records(report, plan["node_ids"])
    actual = [record["node_id"] for record in records]
    if set(actual) != set(assigned):
        issues.append(
            f"shard {shard_index} JUnit coverage differs: "
            f"missing={sorted(set(assigned) - set(actual))}, unexpected={sorted(set(actual) - set(assigned))}"
        )
    skipped = []
    for record in records:
        if record["status"] == "failed":
            issues.append(f"failed testcase: {record['node_id']}")
        if record["status"] != "skipped":
            continue
        skipped.append(record["node_id"])
        reason = policy["expected_skips"].get(record["node_id"])
        if reason is None:
            issues.append(f"unexpected skip: {record['node_id']}: {record['skip_reason']}")
        elif reason not in (record["skip_reason"] or ""):
            issues.append(f"skip reason changed: {record['node_id']}: {record['skip_reason']}")
    return {
        "records": records,
        "issues": issues,
        "test_count": len(records),
        "passed_count": sum(record["status"] == "passed" for record in records),
        "failed_count": sum(record["status"] == "failed" for record in records),
        "skipped_count": len(skipped),
        "skipped_tests": skipped,
        "duration_seconds": round(sum(record["duration_seconds"] for record in records), 3),
    }


def run_shard(root: Path, index: int, output: Path) -> dict[str, Any]:
    policy = load_policy(root)
    plan = create_plan(root)
    if not 0 <= index < plan["shard_count"]:
        raise ValueError(f"shard index must be between 0 and {plan['shard_count'] - 1}")
    output.mkdir(parents=True, exist_ok=True)
    plan_path = output / "plan.json"
    atomic_write(plan_path, dump_json(plan))
    junit_path = output / "junit.xml"
    assigned = plan["shards"][index]["node_ids"]
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "-q",
            "-p",
            "no:cacheprovider",
            f"--junitxml={junit_path}",
            "--durations=25",
            "--durations-min=0.1",
            *assigned,
        ],
        cwd=root,
        check=False,
    )
    verdict = verify_report(plan, index, junit_path, policy)
    issues = list(verdict["issues"])
    if completed.returncode:
        issues.append(f"Pytest exited with status {completed.returncode}")
    result = {
        key: value
        for key, value in verdict.items()
        if key not in {"records", "issues"}
    }
    result.update(
        schema_version=1,
        source_revision=plan["source_revision"],
        shard_index=index,
        plan_sha256=file_digest(plan_path),
        junit_sha256=file_digest(junit_path) if junit_path.is_file() else None,
        exit_code=completed.returncode,
        status="passed" if not issues else "failed",
        issues=issues,
    )
    atomic_write(output / "run.json", dump_json(result))
    if result["status"] == "passed":
        print("PYTEST_SHARD_PASS")
    return result


def bind_workflow_identity(
    document: dict[str, Any], root: Path, identity: dict[str, Any]
) -> dict[str, Any]:
    if not isinstance(document, dict) or not isinstance(identity, dict):
        raise ValueError("workflow identity and evidence must be objects")
    if set(identity) != {"workflow_head_sha", "workflow_run_id", "run_attempt", "pr_number"}:
        raise ValueError("workflow identity fields are incomplete")
    revisions = (identity["workflow_head_sha"], document.get("source_revision"))
    if any(not isinstance(value, str) or REVISION.fullmatch(value) is None for value in revisions):
        raise ValueError("workflow and evaluated revisions must be full Git revisions")
    for field in ("workflow_run_id", "run_attempt", "pr_number"):
        if not isinstance(identity[field], int) or isinstance(identity[field], bool) or identity[field] <= 0:
            raise ValueError(f"{field} must be a positive integer")
    if subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", identity["workflow_head_sha"], document["source_revision"]],
        capture_output=True,
        check=False,
    ).returncode:
        raise ValueError("workflow head is not an ancestor of the evaluated revision")
    document.update(identity)
    return document


def verify_shards(
    root: Path, directories: list[Path], workflow_identity: dict[str, Any] | None = None
) -> dict[str, Any]:
    policy = load_policy(root)
    issues = []
    records = []
    summaries = []
    cache_observations = []
    first_plan: dict[str, Any] | None = None
    seen_ids: dict[str, int] = {}
    seen_indices = set()
    if len(directories) != policy["shards"]:
        issues.append(f"expected {policy['shards']} shard directories, found {len(directories)}")
    for directory in sorted(directories, key=lambda path: str(path)):
        try:
            plan = read_json(directory / "plan.json")
            run = read_json(directory / "run.json")
            if first_plan is None:
                first_plan = plan
            for field in (
                "source_revision",
                "node_ids",
                "node_ids_sha256",
                "policy_sha256",
                "durations_sha256",
                "shard_count",
                "pytest_version",
                "tool_inputs_sha256",
            ):
                if first_plan is not None and plan.get(field) != first_plan.get(field):
                    issues.append(f"plan mismatch in {directory}: {field}")
            if plan.get("policy_sha256") != document_digest(policy):
                issues.append(f"current shard policy does not match {directory}")
            if plan.get("node_ids_sha256") != digest_text("\n".join(plan.get("node_ids", []))):
                issues.append(f"collection digest does not match {directory}")
            index = run.get("shard_index")
            if not isinstance(index, int) or index in seen_indices:
                issues.append(f"missing or duplicate shard index in {directory}: {index}")
                continue
            seen_indices.add(index)
            if run.get("status") != "passed" or run.get("exit_code") != 0:
                issues.append(f"shard {index} did not pass: {run.get('issues', [])}")
            if run.get("plan_sha256") != file_digest(directory / "plan.json"):
                issues.append(f"shard {index} plan hash does not match its run")
            verdict = verify_report(plan, index, directory / "junit.xml", policy)
            issues.extend(verdict["issues"])
            if run.get("junit_sha256") != file_digest(directory / "junit.xml"):
                issues.append(f"shard {index} JUnit hash does not match its run")
            for record in verdict["records"]:
                if record["node_id"] in seen_ids:
                    issues.append(f"testcase appears in multiple shards: {record['node_id']}")
                seen_ids[record["node_id"]] = index
            cache_path = directory / "cache.json"
            caches = read_json(cache_path).get("caches", []) if cache_path.is_file() else []
            cache_observations.append({"shard_index": index, "caches": caches})
            summaries.append({key: value for key, value in run.items() if key != "issues"})
            records.extend(verdict["records"])
        except (OSError, ValueError) as error:
            issues.append(f"invalid shard evidence {directory}: {error}")
    if first_plan is not None:
        missing = sorted(set(first_plan.get("node_ids", [])) - set(seen_ids))
        if missing:
            issues.append(f"complete collection is missing testcases: {missing}")
    if seen_indices != set(range(policy["shards"])):
        issues.append(f"shard indices are incomplete: {sorted(seen_indices)}")
    cache_states = [cache.get("status") for item in cache_observations for cache in item["caches"]]
    result = {
        "schema_version": 1,
        "source_revision": first_plan.get("source_revision") if first_plan else None,
        "node_ids_sha256": first_plan.get("node_ids_sha256") if first_plan else None,
        "pytest_version": first_plan.get("pytest_version") if first_plan else None,
        "tool_inputs_sha256": first_plan.get("tool_inputs_sha256") if first_plan else None,
        "policy_sha256": first_plan.get("policy_sha256") if first_plan else None,
        "durations_sha256": first_plan.get("durations_sha256") if first_plan else None,
        "status": "passed" if first_plan is not None and not issues else "failed",
        "shard_count": len(summaries),
        "test_count": len(records),
        "passed_count": sum(record["status"] == "passed" for record in records),
        "failed_count": sum(record["status"] == "failed" for record in records),
        "skipped_count": sum(record["status"] == "skipped" for record in records),
        "duration_seconds": round(sum(record["duration_seconds"] for record in records), 3),
        "cache_observations": cache_observations,
        "cache_hit_count": cache_states.count("HIT"),
        "cache_miss_count": cache_states.count("MISS"),
        "cache_not_run_count": cache_states.count("NOT_RUN"),
        "shards": summaries,
        "issues": issues,
    }
    if workflow_identity is not None:
        bind_workflow_identity(result, root, workflow_identity)
    return result


def duration_history(root: Path, junit: Path, source_revision: str, run_id: str) -> dict[str, Any]:
    if not REVISION.fullmatch(source_revision) or not run_id.isdigit():
        raise ValueError("duration history requires a full source SHA and numeric workflow run ID")
    try:
        document = ET.parse(junit)
        root_element = document.getroot()
        suites = [root_element] if root_element.tag == "testsuite" else root_element.findall("testsuite")
        if not suites:
            raise ValueError("JUnit report has no testsuite")
        reported = sum(int(suite.get("tests", "-1")) for suite in suites)
        failures = sum(int(suite.get("failures", "0")) + int(suite.get("errors", "0")) for suite in suites)
        cases = root_element.findall(".//testcase")
    except (OSError, ET.ParseError, ValueError) as error:
        raise ValueError(f"invalid duration history JUnit report: {error}") from error
    if reported != len(cases) or failures or not cases:
        raise ValueError("duration history requires a complete, nonempty, successful JUnit report")
    node_ids = collect_node_ids(root)
    records, issues = junit_records(junit, node_ids, allow_unexpected=True)
    if issues or not records or any(record["status"] == "failed" for record in records):
        raise ValueError(f"duration history cannot be matched to current tests: {issues}")
    return {
        "schema_version": 1,
        "source_revision": source_revision,
        "workflow_run_id": run_id,
        "default_duration_seconds": 1.0,
        "durations": {record["node_id"]: record["duration_seconds"] for record in sorted(records, key=lambda item: item["node_id"])},
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("plan", "run", "verify", "durations"):
        command = subparsers.add_parser(name)
        command.add_argument("--root", type=Path, default=ROOT)
        if name == "plan":
            command.add_argument("--output", type=Path, required=True)
        elif name == "run":
            command.add_argument("--shard", type=int, required=True)
            command.add_argument("--output", type=Path, required=True)
        elif name == "verify":
            command.add_argument("--shard-dir", type=Path, action="append", required=True)
            command.add_argument("--workflow-head")
            command.add_argument("--workflow-run", type=int)
            command.add_argument("--run-attempt", type=int)
            command.add_argument("--pr-number", type=int)
            command.add_argument("--output", type=Path, required=True)
        else:
            command.add_argument("--junit", type=Path, required=True)
            command.add_argument("--source-revision", required=True)
            command.add_argument("--workflow-run", required=True)
            command.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "plan":
            result = create_plan(args.root.resolve())
            atomic_write(args.output, dump_json(result))
        elif args.command == "run":
            result = run_shard(args.root.resolve(), args.shard, args.output)
        elif args.command == "verify":
            values = (args.workflow_head, args.workflow_run, args.run_attempt, args.pr_number)
            if any(value is not None for value in values) and any(value is None for value in values):
                raise ValueError("workflow identity requires head, run, attempt, and PR together")
            identity = None
            if args.workflow_head is not None:
                identity = {
                    "workflow_head_sha": args.workflow_head,
                    "workflow_run_id": args.workflow_run,
                    "run_attempt": args.run_attempt,
                    "pr_number": args.pr_number,
                }
            result = verify_shards(args.root.resolve(), args.shard_dir, identity)
            atomic_write(args.output, dump_json(result))
        else:
            result = duration_history(args.root.resolve(), args.junit, args.source_revision, args.workflow_run)
            atomic_write(args.output, dump_json(result))
        if args.command != "run":
            print(json.dumps({key: value for key, value in result.items() if key not in {"node_ids", "shards", "durations"}}, indent=2, sort_keys=True))
        return int(result.get("status", "passed") != "passed")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"pytest shards: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
