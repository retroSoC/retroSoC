#!/usr/bin/env python3
"""Produce revision-bound CI verdicts without crediting stale or unrun evidence."""

from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, git_output, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

TERMINAL_FAILURES = {"failure", "failed", "cancelled", "canceled", "timed_out", "timed-out"}


def parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def collect_results(build_root: Path, root: Path, since: datetime) -> tuple[list[dict[str, Any]], list[str]]:
    results = []
    issues = []
    for path in sorted(build_root.glob("**/result*.json")):
        try:
            data = read_json(path)
        except ValueError as error:
            issues.append(str(error))
            continue
        started = data.get("started_at")
        if not started:
            issues.append(f"result has no started_at and is not accepted: {path}")
            continue
        if parse_time(started) < since:
            continue
        results.append(
            {
                "path": relative(path, root),
                "tool": data.get("tool"),
                "status": data.get("status"),
                "exit_code": data.get("exit_code"),
                "started_at": started,
                "finished_at": data.get("finished_at"),
                "duration_seconds": data.get("duration_seconds"),
                "command": data.get("command"),
                "log": data.get("log"),
            }
        )
    return results, issues


def stage_status(results: list[dict[str, Any]], tokens: tuple[str, ...]) -> str:
    selected = [
        result
        for result in results
        if any(token in result["path"].lower() or token in str(result.get("tool", "")).lower() for token in tokens)
    ]
    if not selected:
        return "NOT_RUN"
    return "FAIL" if any(result["status"] != "passed" or result["exit_code"] != 0 for result in selected) else "PASS"


def behavioral_status(results: list[dict[str, Any]]) -> tuple[str, int]:
    selected = []
    for result in results:
        path = result["path"].lower()
        tool = str(result.get("tool", "")).lower()
        if ("/sim/" in path and "/netl" not in path) or "coremark" in tool or "debug" in tool:
            selected.append(result)
    if not selected:
        return "NOT_RUN", 0
    status = "FAIL" if any(result["status"] != "passed" or result["exit_code"] != 0 for result in selected) else "PASS"
    return status, len(selected)


def collect_coverage(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve()
    since = parse_time(args.since)
    results, issues = collect_results(args.build_root.resolve(), root, since)
    run_status = args.run_status.lower()
    results_passed = bool(results) and all(
        result["status"] == "passed" and result["exit_code"] == 0 for result in results
    )
    if run_status in TERMINAL_FAILURES:
        overall = "FAIL"
    elif run_status == "skipped":
        overall = "SKIPPED"
    elif run_status in {"success", "passed"} and results_passed:
        overall = "PASS"
    else:
        overall = "FAIL"
    behavioral, behavioral_count = behavioral_status(results)
    coverage = [
        {
            "stage": "behavioral",
            "status": behavioral,
            "evidence_count": behavioral_count,
        }
    ]
    for stage, tokens, reason in (
        ("synthesis", ("syn/yosys", "result-synth"), "filtered by --behavioral-only"),
        ("netlist_simulation", ("/netl", "netsim"), "filtered by --behavioral-only"),
        ("sta", ("sta/opensta", "result-sta"), "filtered by --behavioral-only"),
    ):
        status = "NOT_RUN" if args.behavioral_only else stage_status(results, tokens)
        coverage.append(
            {
                "stage": stage,
                "status": status,
                "reason": reason if args.behavioral_only else "no current matching result" if status == "NOT_RUN" else None,
            }
        )
    formal_status = stage_status(results, ("formal-sby-",)) if args.executed_formal else "NOT_RUN"
    coverage.append(
        {
            "stage": "formal",
            "status": formal_status,
            "reason": "no current proof result" if args.executed_formal else "formal-doctor checks the environment but does not execute proofs",
        }
    )
    required = set()
    if args.require_full_flow:
        required.update(("synthesis", "netlist_simulation", "sta"))
    if args.require_formal:
        required.add("formal")
    if any(item["stage"] in required and item["status"] != "PASS" for item in coverage):
        overall = "FAIL"
    return {
        "schema_version": 1,
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "since": since.isoformat(),
        "label": args.label,
        "profile": args.profile,
        "pdk": args.pdk,
        "suite": args.suite,
        "behavioral_only": args.behavioral_only,
        "run_status": args.run_status,
        "overall_status": overall,
        "coverage": coverage,
        "results": results,
        "issues": issues,
    }


def write_step_summary(document: dict[str, Any], path: Path) -> None:
    lines = [
        f"## CI evidence: {document.get('label', 'quality gate')}",
        "",
        f"- Overall: **{document['overall_status']}**",
        f"- Source revision: `{document['source_revision']}`",
    ]
    if document.get("profile"):
        lines.append(f"- Profile / PDK: `{document['profile']}` / `{document['pdk']}`")
    lines.extend(["", "| Stage or job | Verdict | Detail |", "| --- | --- | --- |"])
    if "coverage" in document:
        for item in document["coverage"]:
            detail = item.get("reason") or f"evidence={item.get('evidence_count', 'see JSON')}"
            lines.append(f"| `{item['stage']}` | {item['status']} | {detail} |")
    for item in document.get("jobs", []):
        lines.append(f"| `{item['name']}` | {item['result']} | required={item['required']} |")
    lines.extend(["", f"Machine-readable result: `{document.get('output', 'ci-summary.json')}`", ""])
    with path.open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def gate(results: list[str], allow_skip: set[str], label: str) -> dict[str, Any]:
    jobs = []
    failures = []
    for item in results:
        name, separator, result = item.partition("=")
        if not separator or not name or result not in {"success", "failure", "skipped", "cancelled"}:
            raise ValueError(f"invalid job result: {item}; expected name=success|failure|skipped|cancelled")
        required = name not in allow_skip
        jobs.append({"name": name, "result": result, "required": required})
        if result in TERMINAL_FAILURES or (result == "skipped" and required):
            failures.append(name)
    return {
        "schema_version": 1,
        "source_revision": None,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "label": label,
        "overall_status": "FAIL" if failures else "PASS",
        "failed_jobs": failures,
        "jobs": jobs,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    collect = subparsers.add_parser("collect")
    collect.add_argument("--root", type=Path, default=ROOT)
    collect.add_argument("--build-root", type=Path, required=True)
    collect.add_argument("--since", required=True)
    collect.add_argument("--label", required=True)
    collect.add_argument("--profile")
    collect.add_argument("--pdk")
    collect.add_argument("--suite")
    collect.add_argument("--behavioral-only", action="store_true")
    collect.add_argument("--require-full-flow", action="store_true")
    collect.add_argument("--executed-formal", action="store_true")
    collect.add_argument("--require-formal", action="store_true")
    collect.add_argument("--run-status", required=True)
    collect.add_argument("--output", type=Path, required=True)
    collect.add_argument("--step-summary", type=Path)
    gate_parser = subparsers.add_parser("gate")
    gate_parser.add_argument("--root", type=Path, default=ROOT)
    gate_parser.add_argument("--job", action="append", required=True)
    gate_parser.add_argument("--allow-skip", action="append", default=[])
    gate_parser.add_argument("--label", default="quality gate")
    gate_parser.add_argument("--output", type=Path, required=True)
    gate_parser.add_argument("--step-summary", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "collect":
            document = collect_coverage(args)
        else:
            document = gate(args.job, set(args.allow_skip), args.label)
            document["source_revision"] = git_output(args.root.resolve(), "rev-parse", "HEAD")
        document["output"] = str(args.output)
        atomic_write(args.output, dump_json(document))
        if args.step_summary:
            write_step_summary(document, args.step_summary)
        print(f"CI summary: {document['overall_status']}: {args.output.resolve()}")
        return int(document["overall_status"] == "FAIL")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"CI summary: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
