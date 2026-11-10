#!/usr/bin/env python3
"""Validate and execute repository Skill behavior evaluations with traced evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, git_output, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

CORE_SKILLS = {
    "retrosoc-feature-design",
    "retrosoc-feature-implementation",
    "retrosoc-feature-review",
}


def load_registry(root: Path) -> dict[str, Any]:
    registry = read_json(root / ".agents/skills/registry.json")
    if registry.get("schema_version") != 1:
        raise ValueError("Skill registry schema_version must be 1")
    return registry


def load_cases(root: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    registry = load_registry(root)
    document = read_json(root / registry["behavior_evals"])
    entries = {entry["name"]: entry for entry in registry["skills"]}
    cases: list[dict[str, Any]] = []
    for case in document["cases"]:
        skill = case["skill"]
        source = read_json(root / entries[skill]["eval_suite"])
        prompts = {item["id"]: item for item in source["evals"]}
        enriched = dict(case)
        enriched["prompt"] = prompts[case["source_eval"]]["prompt"]
        enriched["expected_output"] = prompts[case["source_eval"]]["expected_output"]
        enriched["live"] = case.get("live", True)
        cases.append(enriched)
    return document, cases


def validate_evals(root: Path) -> list[str]:
    issues: list[str] = []
    try:
        registry = load_registry(root)
        document, cases = load_cases(root)
    except (KeyError, ValueError) as error:
        return [str(error)]
    if document.get("schema_version") != 1:
        issues.append("behavior eval schema_version must be 1")
    defaults = document.get("defaults", {})
    if defaults.get("read_only") is not True:
        issues.append("behavior eval defaults must require read_only=true")
    if not isinstance(defaults.get("max_commands"), int) or defaults["max_commands"] <= 0:
        issues.append("behavior eval max_commands must be positive")
    identifiers = [case["id"] for case in cases]
    if len(set(identifiers)) != len(identifiers):
        issues.append("behavior eval case identifiers must be unique")
    for name, expected_count in document["core_skill_case_counts"].items():
        selected = [case for case in cases if case["skill"] == name]
        if len(selected) != expected_count or not 10 <= expected_count <= 20:
            issues.append(f"{name} must have 10-20 cases; found {len(selected)}")
        if sum(bool(case.get("smoke")) for case in selected) != 1:
            issues.append(f"{name} must select exactly one smoke case")
    if not any(case["should_trigger"] is False for case in cases):
        issues.append("at least one negative trigger case is required")
    for case in cases:
        for key in ("id", "skill", "source_eval", "should_trigger"):
            if key not in case:
                issues.append(f"{case.get('id', '<unknown>')} missing {key}")
        if case["skill"] not in CORE_SKILLS:
            issues.append(f"{case['id']} references an unsupported behavior-eval Skill")
        if not isinstance(case["should_trigger"], bool):
            issues.append(f"{case['id']} should_trigger must be boolean")
        if not case.get("live", True) and case.get("smoke"):
            issues.append(f"{case['id']} cannot be a skipped live smoke case")
    for entry in registry["skills"]:
        for field in ("entrypoint", "eval_suite"):
            if not (root / entry[field]).is_file():
                issues.append(f"registry path missing: {entry[field]}")
        if not entry.get("owner", "").startswith("@"):
            issues.append(f"Skill owner must be a GitHub handle: {entry['name']}")
    return issues


def prepare_workspace(root: Path, workspace: Path) -> None:
    """Create an isolated Git snapshot while reusing read-only managed inputs."""
    listing = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
    )
    for raw in listing.split(b"\0"):
        if not raw:
            continue
        relative = Path(raw.decode("utf-8"))
        source = root / relative
        destination = workspace / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            destination.symlink_to(source.readlink())
        elif source.is_file():
            shutil.copy2(source, destination)
    managed_links = (
        ".cache",
        "physical/pdk/IHP-Open-PDK",
        "physical/pdk/gf180mcu-pdk",
        "physical/pdk/icsprout55-pdk",
        "physical/pdk/skywater-pdk",
        "rtl/managed/clusterip",
        "rtl/managed/hazard3",
        "rtl/managed/third_party",
        "rtl/managed/mpw",
        "app/coremark/coremark-main",
        "app/fatfs/ff16",
        "app/lvgl/lvgl-main",
    )
    for name in managed_links:
        source = root / name
        destination = workspace / name
        if source.exists() and not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(source, target_is_directory=True)
    subprocess.run(["git", "init", "-q", str(workspace)], check=True)
    subprocess.run(["git", "-C", str(workspace), "config", "user.email", "skill-eval@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(workspace), "config", "user.name", "Skill Eval"], check=True)
    subprocess.run(["git", "-C", str(workspace), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(workspace), "commit", "-qm", "isolated skill evaluation"], check=True)
    subprocess.run(["git", "-C", str(workspace), "checkout", "-qb", "dev"], check=True)
    subprocess.run(["git", "-C", str(workspace), "branch", "main"], check=True)


def repo_snapshot(root: Path) -> list[str]:
    output = git_output(root, "status", "--porcelain", "--untracked-files=all")
    snapshot = [line for line in output.splitlines() if line]
    diff = git_output(root, "diff", "--binary", "HEAD").encode("utf-8")
    snapshot.append("tracked-diff-sha256:" + hashlib.sha256(diff).hexdigest())
    untracked = git_output(root, "ls-files", "--others", "--exclude-standard")
    for name in untracked.splitlines():
        path = root / name
        if path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            snapshot.append(f"untracked:{name}:{digest}")
    return sorted(snapshot)


def walk_events(value: Any, commands: list[dict[str, Any]], changes: list[Any], usage: list[Any]) -> None:
    if isinstance(value, dict):
        if value.get("type") == "item.completed":
            item = value.get("item", {})
            if item.get("type") == "command_execution":
                commands.append(
                    {
                        "command": item.get("command", ""),
                        "exit_code": item.get("exit_code"),
                        "status": item.get("status"),
                    }
                )
            if item.get("type") == "file_change":
                changes.append(item.get("changes", item))
        if value.get("type") == "turn.completed" and "usage" in value:
            usage.append(value["usage"])
        for child in value.values():
            walk_events(child, commands, changes, usage)
    elif isinstance(value, list):
        for child in value:
            walk_events(child, commands, changes, usage)


def parse_jsonl(text: str) -> list[Any]:
    events = []
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid runner JSONL at line {number}: {error}") from error
    return events


def evaluation_prompt(case: dict[str, Any]) -> str:
    return (
        case["prompt"]
        + "\n\nEvaluation constraints:\n"
        + "- This is a read-only Skill behavior evaluation. Do not modify files or run EDA/build simulations.\n"
        + "- Follow the repository Skill routing and evidence rules. Preflight/diagnosis may inspect files and dry-run definitions.\n"
        + "- In the final structured response, list every repository Skill actually invoked.\n"
        + "- Use verdict for the stage verdict or review next action; use NONE when no enumerated verdict applies.\n"
        + "- Use route for a required next repository Skill, or NONE.\n"
        + "- Keep summary concise and retain explicit NOT_RUN labels for missing evidence.\n"
    )


def run_codex(
    root: Path,
    case: dict[str, Any],
    output: Path,
    schema: Path,
    model: str | None,
    timeout: int,
) -> dict[str, Any]:
    output = output.resolve()
    workspace = output / f"{case['id']}-workspace"
    prepare_workspace(root, workspace)
    raw_path = output / f"{case['id']}.jsonl"
    response_path = output / f"{case['id']}.response.json"
    stderr_path = output / f"{case['id']}.stderr.log"
    before = repo_snapshot(workspace)
    command = [
        "codex",
        "exec",
        "--sandbox",
        "read-only",
        "--json",
        "--ephemeral",
        "--color",
        "never",
        "--cd",
        str(workspace),
        "--output-schema",
        str(schema),
        "--output-last-message",
        str(response_path),
    ]
    if model:
        command.extend(("--model", model))
    command.append(evaluation_prompt(case))
    started = datetime.now(timezone.utc)
    start_clock = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=workspace,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        returncode = result.returncode
        stdout = result.stdout
        stderr = result.stderr
        error = None
    except subprocess.TimeoutExpired as error_value:
        returncode = 124
        stdout = error_value.stdout or ""
        stderr = error_value.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        error = f"runner timed out after {timeout} seconds"
    atomic_write(raw_path, stdout)
    atomic_write(stderr_path, stderr)
    after = repo_snapshot(workspace)
    commands: list[dict[str, Any]] = []
    changes: list[Any] = []
    usage: list[Any] = []
    if stdout:
        walk_events(parse_jsonl(stdout), commands, changes, usage)
    response = {}
    if response_path.is_file():
        try:
            response = json.loads(response_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error_value:
            error = f"invalid structured response: {error_value}"
    elif returncode == 0:
        error = "runner did not produce a structured response"
    return {
        "schema_version": 1,
        "case": case,
        "runner": "codex",
        "runner_version": subprocess.check_output(["codex", "--version"], text=True).strip(),
        "model": model or "runner-default",
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "workspace_revision": git_output(workspace, "rev-parse", "HEAD"),
        "workspace": str(workspace),
        "started_at": started.isoformat(),
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "duration_seconds": round(time.monotonic() - start_clock, 3),
        "exit_code": returncode,
        "error": error,
        "response": response,
        "commands": commands,
        "file_changes": changes,
        "usage": usage,
        "repository_before": before,
        "repository_after": after,
        "repository_delta": sorted(set(after) - set(before)),
        "raw_trace": str(raw_path),
        "stderr": str(stderr_path),
    }


def check(checks: list[dict[str, Any]], identifier: str, passed: bool, details: Any) -> None:
    checks.append({"id": identifier, "pass": bool(passed), "details": details})


def grade_trace(trace: dict[str, Any], defaults: dict[str, Any]) -> dict[str, Any]:
    case = trace["case"]
    response = trace.get("response", {})
    checks: list[dict[str, Any]] = []
    invoked = response.get("invoked_skills", [])
    expected_skill = case["skill"]
    if case["should_trigger"]:
        check(checks, "skill-trigger", expected_skill in invoked, invoked)
    else:
        check(checks, "skill-negative-trigger", expected_skill not in invoked, invoked)
    check(checks, "runner-exit", trace["exit_code"] == 0, trace["exit_code"])
    check(checks, "runner-error", trace.get("error") is None, trace.get("error"))
    verdict = str(response.get("verdict", "")).upper()
    if "allowed_verdicts" in case:
        check(checks, "verdict", verdict in case["allowed_verdicts"], verdict)
    if "allowed_next_actions" in case:
        check(checks, "next-action", verdict in case["allowed_next_actions"], verdict)
    if "expected_route" in case:
        check(checks, "route", response.get("route") == case["expected_route"], response.get("route"))
    response_text = json.dumps(response, sort_keys=True).lower()
    for term in case.get("required_terms", []):
        check(checks, f"term:{term}", term.lower() in response_text, term)
    commands = trace.get("commands", [])
    command_text = "\n".join(str(item.get("command", "")) for item in commands)
    for pattern in case.get("required_command_patterns", []):
        check(checks, f"command:{pattern}", re.search(pattern, command_text) is not None, pattern)
    for pattern in defaults.get("forbidden_command_patterns", []):
        check(checks, f"forbidden-command:{pattern}", re.search(pattern, command_text) is None, pattern)
    maximum = case.get("max_commands", defaults["max_commands"])
    check(checks, "command-budget", len(commands) <= maximum, len(commands))
    if case.get("read_only", defaults["read_only"]):
        check(checks, "trace-file-changes", not trace.get("file_changes"), trace.get("file_changes"))
        check(checks, "repository-read-only", not trace.get("repository_delta"), trace.get("repository_delta"))
    return {
        "schema_version": 1,
        "case_id": case["id"],
        "status": "passed" if all(item["pass"] for item in checks) else "failed",
        "checks": checks,
        "duration_seconds": trace.get("duration_seconds"),
        "command_count": len(commands),
        "usage": trace.get("usage", []),
    }


def selected_cases(cases: list[dict[str, Any]], args: argparse.Namespace) -> list[dict[str, Any]]:
    selected = cases
    if args.skill:
        selected = [case for case in selected if case["skill"] == args.skill]
    if args.smoke:
        selected = [case for case in selected if case.get("smoke")]
    if args.case:
        requested = set(args.case)
        selected = [case for case in selected if case["id"] in requested]
        missing = requested - {case["id"] for case in selected}
        if missing:
            raise ValueError(f"unknown eval cases: {', '.join(sorted(missing))}")
    return selected


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--root", type=Path, default=ROOT)
    validate.add_argument("--output", type=Path)
    for name in ("list", "run"):
        command = subparsers.add_parser(name)
        command.add_argument("--root", type=Path, default=ROOT)
        command.add_argument("--skill", choices=sorted(CORE_SKILLS))
        command.add_argument("--case", action="append")
        command.add_argument("--smoke", action="store_true")
        if name == "run":
            command.add_argument("--runner", choices=("codex",), default="codex")
            command.add_argument("--model")
            command.add_argument("--timeout", type=int, default=600)
            command.add_argument("--output", type=Path, required=True)
    grade = subparsers.add_parser("grade")
    grade.add_argument("--root", type=Path, default=ROOT)
    grade.add_argument("--trace", type=Path, required=True)
    grade.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        document, cases = load_cases(args.root.resolve())
        if args.command == "validate":
            issues = validate_evals(args.root.resolve())
            result = {
                "schema_version": 1,
                "status": "failed" if issues else "passed",
                "case_count": len(cases),
                "issues": issues,
                "behavior_execution": "not run by validate",
            }
            text = dump_json(result)
            if args.output:
                atomic_write(args.output, text)
            else:
                sys.stdout.write(text)
            return int(bool(issues))
        selected = selected_cases(cases, args)
        if args.command == "list":
            sys.stdout.write(dump_json({"cases": selected, "execution": "not run"}))
            return 0
        if args.command == "grade":
            trace = read_json(args.trace)
            result = grade_trace(trace, document["defaults"])
            if args.output:
                atomic_write(args.output, dump_json(result))
            else:
                sys.stdout.write(dump_json(result))
            return int(result["status"] != "passed")
        if args.command == "run":
            if args.timeout <= 0:
                raise ValueError("runner timeout must be positive")
            args.output.mkdir(parents=True, exist_ok=False)
            results = []
            for case in selected:
                if not case["live"]:
                    results.append({"case_id": case["id"], "status": "skipped", "reason": "live execution disabled for this fixture"})
                    continue
                print(f"[skill-eval] {case['id']}", flush=True)
                trace = run_codex(
                    args.root.resolve(),
                    case,
                    args.output,
                    args.root.resolve() / ".agents/skills/response.schema.json",
                    args.model,
                    args.timeout,
                )
                atomic_write(args.output / f"{case['id']}.trace.json", dump_json(trace))
                result = grade_trace(trace, document["defaults"])
                atomic_write(args.output / f"{case['id']}.grade.json", dump_json(result))
                results.append(result)
            executed = [result for result in results if result["status"] != "skipped"]
            summary = {
                "schema_version": 1,
                "status": "passed" if executed and all(result["status"] == "passed" for result in executed) else ("skipped" if not executed else "failed"),
                "runner": args.runner,
                "model": args.model or "runner-default",
                "case_count": len(results),
                "executed_count": len(executed),
                "passed_count": sum(result["status"] == "passed" for result in results),
                "failed_count": sum(result["status"] == "failed" for result in results),
                "skipped_count": sum(result["status"] == "skipped" for result in results),
                "results": results,
            }
            atomic_write(args.output / "summary.json", dump_json(summary))
            print(dump_json({key: value for key, value in summary.items() if key != "results"}), end="")
            return 0 if summary["status"] == "passed" else 2
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"skill eval: {error}", file=sys.stderr)
        return 2
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
