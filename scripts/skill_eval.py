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
BEHAVIOR_SKILLS = CORE_SKILLS | {
    "retrosoc-datasheet",
    "retrosoc-dependency-maintenance",
    "retrosoc-physical-flow",
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
        enriched["skill_contract_version"] = entries[skill]["contract_version"]
        enriched["skill_entrypoint"] = entries[skill]["entrypoint"]
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
    expected_counts = document.get("skill_case_counts", document.get("core_skill_case_counts", {}))
    for entry in registry["skills"]:
        name = entry["name"]
        selected = [case for case in cases if case["skill"] == name]
        minimum = 10 if name in CORE_SKILLS else 6
        expected = expected_counts.get(name, len(selected))
        if expected is None or len(selected) != expected or not minimum <= expected <= 20:
            issues.append(f"{name} must have {minimum}-20 cases; found {len(selected)}")
        if sum(bool(case.get("smoke")) for case in selected) != 1:
            issues.append(f"{name} must select exactly one smoke case")
    if not any(case["should_trigger"] is False for case in cases):
        issues.append("at least one negative trigger case is required")
    for case in cases:
        for key in ("id", "skill", "source_eval", "should_trigger"):
            if key not in case:
                issues.append(f"{case.get('id', '<unknown>')} missing {key}")
        if case["skill"] not in BEHAVIOR_SKILLS:
            issues.append(f"{case['id']} references an unsupported behavior-eval Skill")
        if not isinstance(case["should_trigger"], bool):
            issues.append(f"{case['id']} should_trigger must be boolean")
        if not case.get("live", True) and case.get("smoke"):
            issues.append(f"{case['id']} cannot be a skipped live smoke case")
    names = [entry["name"] for entry in registry["skills"]]
    if len(set(names)) != len(names):
        issues.append("Skill registry names must be unique")
    for entry in registry["skills"]:
        for field in ("entrypoint", "eval_suite"):
            if not (root / entry[field]).is_file():
                issues.append(f"registry path missing: {entry[field]}")
        if not entry.get("owner", "").startswith("@"):
            issues.append(f"Skill owner must be a GitHub handle: {entry['name']}")
        version = entry.get("contract_version")
        if not isinstance(version, int) or isinstance(version, bool) or version < 1:
            issues.append(f"Skill contract_version must be a positive integer: {entry['name']}")
        if isinstance(version, int) and version > 1:
            migration = Path(entry.get("contract_migration", ""))
            if migration.is_absolute() or ".." in migration.parts or not (root / migration).is_file():
                issues.append(f"Skill contract migration is missing or unsafe: {entry['name']}")
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


def walk_kimi_events(events: list[Any]) -> tuple[list[dict[str, Any]], list[Any], list[Any], dict[str, Any]]:
    commands: list[dict[str, Any]] = []
    changes: list[Any] = []
    usage: list[Any] = []
    text_parts: list[str] = []
    by_id: dict[str, dict[str, Any]] = {}
    for event in events:
        if not isinstance(event, dict):
            continue
        if isinstance(event.get("usage"), dict):
            usage.append(event["usage"])
        if event.get("role") == "assistant":
            content = event.get("content", "")
            if isinstance(content, str) and content.strip():
                text_parts.append(content)
            elif isinstance(content, list):
                text_parts.extend(
                    part["text"]
                    for part in content
                    if isinstance(part, dict) and isinstance(part.get("text"), str)
                )
            for call in event.get("tool_calls", []):
                function = call.get("function", {})
                name = function.get("name", call.get("name", ""))
                arguments = function.get("arguments", call.get("input", {}))
                if isinstance(arguments, str):
                    try:
                        arguments = json.loads(arguments)
                    except json.JSONDecodeError:
                        arguments = {"input": arguments}
                identifier = str(call.get("id", len(commands)))
                command = arguments.get("command") if isinstance(arguments, dict) else None
                record = {
                    "id": identifier,
                    "tool": name,
                    "command": command or json.dumps(arguments, sort_keys=True),
                    "exit_code": None,
                    "status": "called",
                }
                commands.append(record)
                by_id[identifier] = record
                if name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
                    changes.append(arguments)
        elif event.get("role") == "tool":
            identifier = str(event.get("tool_call_id", ""))
            if identifier in by_id:
                by_id[identifier]["status"] = "failed" if event.get("is_error") else "completed"
                by_id[identifier]["exit_code"] = event.get("exit_code", int(event.get("is_error") is True))
    response: dict[str, Any] = {}
    for text in reversed(text_parts):
        candidate = text.strip()
        fenced = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", candidate, re.DOTALL)
        if fenced:
            candidate = fenced.group(1)
        try:
            value = json.loads(candidate)
        except json.JSONDecodeError:
            start = candidate.find("{")
            end = candidate.rfind("}")
            if start < 0 or end <= start:
                continue
            try:
                value = json.loads(candidate[start : end + 1])
            except json.JSONDecodeError:
                continue
        if isinstance(value, dict):
            response = value
            break
    return commands, changes, usage, response


def input_snapshot_sha256(case: dict[str, Any]) -> str:
    fields = {
        key: case[key]
        for key in ("id", "skill", "source_eval", "prompt", "expected_output")
    }
    return hashlib.sha256(json.dumps(fields, sort_keys=True).encode("utf-8")).hexdigest()


def validate_trace_identity(
    root: Path, trace: dict[str, Any], registered_cases: list[dict[str, Any]]
) -> dict[str, Any]:
    if not isinstance(trace, dict) or trace.get("schema_version") != 1:
        raise ValueError("Skill trace requires schema_version=1")
    case = trace.get("case")
    if not isinstance(case, dict) or not isinstance(case.get("id"), str):
        raise ValueError("Skill trace case identity is missing")
    matching = [candidate for candidate in registered_cases if candidate["id"] == case["id"]]
    if len(matching) != 1:
        raise ValueError(f"Skill trace case is not registered in this replay scope: {case['id']}")
    if case.get("skill") != matching[0]["skill"]:
        raise ValueError("Skill trace case and registered Skill differ")
    for field in ("source_revision", "skill_source_revision", "workspace_revision", "workspace_tree"):
        if not isinstance(trace.get(field), str) or re.fullmatch(r"[0-9a-f]{40}", trace[field]) is None:
            raise ValueError(f"Skill trace {field} must be a full Git revision")
    if trace["source_revision"] != trace["skill_source_revision"]:
        raise ValueError("Skill trace source and Skill revisions differ")
    for field in ("skill_entrypoint_sha256", "input_snapshot_sha256"):
        if not isinstance(trace.get(field), str) or re.fullmatch(r"[0-9a-f]{64}", trace[field]) is None:
            raise ValueError(f"Skill trace {field} must be a SHA-256 digest")
    if trace["input_snapshot_sha256"] != input_snapshot_sha256(case):
        raise ValueError("Skill trace input snapshot does not match its frozen case")
    if trace.get("runner") not in {"codex", "kimi"}:
        raise ValueError("Skill trace runner must be explicitly codex or kimi")
    if not isinstance(trace.get("runner_version"), str) or not trace["runner_version"]:
        raise ValueError("Skill trace runner version is missing")
    if not isinstance(trace.get("model"), str) or not trace["model"]:
        raise ValueError("Skill trace model identity is missing")
    if trace["runner"] == "kimi" and re.fullmatch(
        r"[0-9a-f]{64}", trace.get("runner_agent_sha256", "")
    ) is None:
        raise ValueError("Kimi trace must bind the restricted runner profile")
    if type(trace.get("skill_contract_version")) is not int or trace["skill_contract_version"] != case.get("skill_contract_version"):
        raise ValueError("Skill trace contract version differs from its case")
    entrypoint = case.get("skill_entrypoint")
    if not isinstance(entrypoint, str) or Path(entrypoint).is_absolute() or ".." in Path(entrypoint).parts:
        raise ValueError("Skill trace entrypoint is unsafe")
    if entrypoint != matching[0]["skill_entrypoint"]:
        raise ValueError("Skill trace entrypoint differs from the registered case")
    if not isinstance(trace.get("response"), dict) or not isinstance(trace.get("commands"), list):
        raise ValueError("Skill trace response and commands must be structured objects")
    if not isinstance(trace.get("file_changes"), list) or not isinstance(trace.get("repository_delta"), list):
        raise ValueError("Skill trace read-only evidence must be lists")
    if type(trace.get("exit_code")) is not int:
        raise ValueError("Skill trace exit_code must be an integer")
    duration = trace.get("duration_seconds")
    if not isinstance(duration, (int, float)) or isinstance(duration, bool) or duration < 0:
        raise ValueError("Skill trace duration must be non-negative")
    prompt_text = trace.get("evaluation_prompt")
    prompt_digest = trace.get("evaluation_prompt_sha256")
    command_budget = trace.get("command_budget")
    prompt_recorded = prompt_text is not None or prompt_digest is not None or command_budget is not None
    if prompt_recorded:
        if not isinstance(prompt_text, str) or re.fullmatch(r"[0-9a-f]{64}", prompt_digest or "") is None:
            raise ValueError("Skill trace rendered prompt and digest must be recorded together")
        if type(command_budget) is not int or command_budget <= 0:
            raise ValueError("Skill trace command budget must be a positive integer")
        if hashlib.sha256(prompt_text.encode("utf-8")).hexdigest() != prompt_digest:
            raise ValueError("Skill trace rendered prompt digest does not match its content")
    current_entrypoint = root / entrypoint
    return {
        "case_id": case["id"],
        "skill": case["skill"],
        "case_snapshot_status": "current" if case == matching[0] else "historical",
        "skill_matches_current": current_entrypoint.is_file()
        and hashlib.sha256(current_entrypoint.read_bytes()).hexdigest() == trace["skill_entrypoint_sha256"],
        "skill_source_revision": trace["skill_source_revision"],
        "skill_contract_version": trace["skill_contract_version"],
        "skill_entrypoint_sha256": trace["skill_entrypoint_sha256"],
        "runner": trace["runner"],
        "runner_version": trace["runner_version"],
        "model": trace["model"],
        "input_snapshot_sha256": trace["input_snapshot_sha256"],
        "workspace_revision": trace["workspace_revision"],
        "workspace_tree": trace["workspace_tree"],
        "command_count": len(trace["commands"]),
        "rendered_prompt_status": "RECORDED" if prompt_recorded else "NOT_RECORDED",
        "evaluation_prompt_sha256": prompt_digest,
        "command_budget": command_budget,
        "evaluation_prompt_matches_current": evaluation_prompt(case, command_budget) == prompt_text
        if prompt_recorded
        else None,
        "provenance_complete": prompt_recorded,
        "usage": trace.get("usage", []),
    }


def replay_traces(
    root: Path, paths: list[Path], registered_cases: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    document, cases = load_cases(root)
    if registered_cases is None:
        registered_cases = cases
    resolved = [path.absolute() for path in paths]
    if len(set(resolved)) != len(resolved):
        raise ValueError("replay trace paths must be unique")
    records = []
    for path in resolved:
        record = {"trace": str(path)}
        try:
            if path.is_symlink() or not path.is_file():
                raise ValueError("trace must be a regular file")
            trace = read_json(path)
            record["trace_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            identity = validate_trace_identity(root, trace, registered_cases)
            grade = grade_trace(trace, document["defaults"])
            record.update(identity=identity, grade=grade, status="REPLAYED")
        except (OSError, ValueError, KeyError, TypeError) as error:
            record.update(status="INVALID", error=str(error))
        records.append(record)
    invalid = sum(record["status"] == "INVALID" for record in records)
    failed = sum(record.get("grade", {}).get("status") == "failed" for record in records)
    return {
        "schema_version": 1,
        "status": "NOT_RUN" if not records else "INVALID" if invalid else "REPLAYED",
        "evidence_scope": "retained traces only; no new agent behavior was executed",
        "behavior_execution": "NOT_RUN",
        "runner_invocations": 0,
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "source_dirty": bool(git_output(root, "status", "--porcelain", "--untracked-files=all")),
        "trace_count": len(records),
        "invalid_trace_count": invalid,
        "partial_provenance_count": sum(
            record.get("identity", {}).get("provenance_complete") is False for record in records
        ),
        "grade_passed_count": sum(record.get("grade", {}).get("status") == "passed" for record in records),
        "grade_failed_count": failed,
        "records": records,
    }


def evaluation_prompt(case: dict[str, Any], command_budget: int = 80) -> str:
    return (
        case["prompt"]
        + "\n\nEvaluation constraints:\n"
        + "- This is a read-only Skill behavior evaluation. Do not modify files or run EDA/build simulations.\n"
        + "- Follow the repository Skill routing and evidence rules. Preflight/diagnosis may inspect files and dry-run definitions.\n"
        + f"- Use at most {command_budget} tool calls. Resolve the target and relevant files first; avoid broad or repeated exploration.\n"
        + "- invoked_skills must list every Skill consulted through the Skill tool or a direct SKILL.md read, including a Skill that refuses the request.\n"
        + "- Use verdict for the stage verdict or review next action; use NONE when no enumerated verdict applies.\n"
        + "- Use route for a required next repository Skill, or NONE.\n"
        + "- End with exactly one JSON object and no Markdown, YAML, or surrounding prose.\n"
        + "- Required keys are invoked_skills, verdict, route, and summary; never substitute skills_invoked.\n"
        + "- Keep summary concise and retain explicit NOT_RUN labels for missing evidence.\n"
    )


def run_codex(
    root: Path,
    case: dict[str, Any],
    output: Path,
    schema: Path,
    model: str | None,
    timeout: int,
    command_budget: int = 80,
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
    command.append(evaluation_prompt(case, command_budget))
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
        "skill_source_revision": git_output(root, "rev-parse", "HEAD"),
        "skill_contract_version": case["skill_contract_version"],
        "skill_entrypoint_sha256": hashlib.sha256((root / case["skill_entrypoint"]).read_bytes()).hexdigest(),
        "input_snapshot_sha256": input_snapshot_sha256(case),
        "evaluation_prompt": command[-1],
        "evaluation_prompt_sha256": hashlib.sha256(command[-1].encode("utf-8")).hexdigest(),
        "command_budget": command_budget,
        "source_dirty": bool(git_output(root, "status", "--porcelain", "--untracked-files=all")),
        "workspace_revision": git_output(workspace, "rev-parse", "HEAD"),
        "workspace_tree": git_output(workspace, "rev-parse", "HEAD^{tree}"),
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


def run_kimi(
    root: Path,
    case: dict[str, Any],
    output: Path,
    model: str | None,
    timeout: int,
    command_budget: int = 80,
) -> dict[str, Any]:
    output = output.resolve()
    workspace = output / f"{case['id']}-workspace"
    prepare_workspace(root, workspace)
    agent_file = workspace / ".agents/skill-eval-agent.md"
    raw_path = output / f"{case['id']}.jsonl"
    stderr_path = output / f"{case['id']}.stderr.log"
    before = repo_snapshot(workspace)
    command = [
        "kimi",
        "--agent-file",
        str(agent_file),
        "--output-format",
        "stream-json",
        "--skills-dir",
        str(workspace / ".agents/skills"),
    ]
    if model:
        command.extend(("--model", model))
    command.extend(("--prompt", evaluation_prompt(case, command_budget)))
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
        error = None if returncode == 0 else f"runner exited with status {returncode}"
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
    commands, changes, usage, response = walk_kimi_events(parse_jsonl(stdout)) if stdout else ([], [], [], {})
    if not response and returncode == 0:
        error = "runner did not produce a structured response"
    return {
        "schema_version": 1,
        "case": case,
        "runner": "kimi",
        "runner_version": subprocess.check_output(["kimi", "--version"], text=True).strip(),
        "runner_agent_sha256": hashlib.sha256(agent_file.read_bytes()).hexdigest(),
        "model": model or "runner-default",
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "skill_source_revision": git_output(root, "rev-parse", "HEAD"),
        "skill_contract_version": case["skill_contract_version"],
        "skill_entrypoint_sha256": hashlib.sha256((root / case["skill_entrypoint"]).read_bytes()).hexdigest(),
        "input_snapshot_sha256": input_snapshot_sha256(case),
        "evaluation_prompt": command[-1],
        "evaluation_prompt_sha256": hashlib.sha256(command[-1].encode("utf-8")).hexdigest(),
        "command_budget": command_budget,
        "source_dirty": bool(git_output(root, "status", "--porcelain", "--untracked-files=all")),
        "workspace_revision": git_output(workspace, "rev-parse", "HEAD"),
        "workspace_tree": git_output(workspace, "rev-parse", "HEAD^{tree}"),
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
    for name in ("list", "run", "replay"):
        command = subparsers.add_parser(name)
        command.add_argument("--root", type=Path, default=ROOT)
        command.add_argument("--skill", choices=sorted(BEHAVIOR_SKILLS))
        command.add_argument("--case", action="append")
        command.add_argument("--smoke", action="store_true")
        if name == "run":
            command.add_argument("--runner", choices=("codex", "kimi"), default="codex")
            command.add_argument("--model")
            command.add_argument("--timeout", type=int, default=600)
            command.add_argument("--output", type=Path, required=True)
        elif name == "replay":
            command.add_argument("--trace", type=Path, action="append", default=[])
            command.add_argument("--trace-root", type=Path)
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
                "smoke_case_count": sum(bool(case.get("smoke")) for case in cases),
                "source_revision": git_output(args.root.resolve(), "rev-parse", "HEAD"),
                "skill_contracts": {
                    case["skill"]: case["skill_contract_version"]
                    for case in cases
                },
                "input_snapshots": {
                    case["id"]: input_snapshot_sha256(case)
                    for case in cases
                },
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
        if args.command == "replay":
            paths = list(args.trace)
            if args.trace_root:
                if args.trace_root.is_symlink() or not args.trace_root.is_dir():
                    raise ValueError("trace root must be a real directory")
                paths.extend(sorted(args.trace_root.rglob("*.trace.json")))
            result = replay_traces(args.root.resolve(), paths, selected)
            atomic_write(args.output, dump_json(result))
            print(dump_json({key: value for key, value in result.items() if key != "records"}), end="")
            return int(
                result["status"] in {"INVALID", "NOT_RUN"} or result["grade_failed_count"] > 0
            )
        if args.command == "run":
            if args.timeout <= 0:
                raise ValueError("runner timeout must be positive")
            args.output.mkdir(parents=True, exist_ok=False)
            results = []
            runner_versions = []
            for case in selected:
                if not case["live"]:
                    results.append({"case_id": case["id"], "status": "skipped", "reason": "live execution disabled for this fixture"})
                    continue
                print(f"[skill-eval] {case['id']}", flush=True)
                if args.runner == "kimi":
                    trace = run_kimi(
                        args.root.resolve(),
                        case,
                        args.output,
                        args.model,
                        args.timeout,
                        case.get("max_commands", document["defaults"]["max_commands"]),
                    )
                else:
                    trace = run_codex(
                        args.root.resolve(),
                        case,
                        args.output,
                        args.root.resolve() / ".agents/skills/response.schema.json",
                        args.model,
                        args.timeout,
                        case.get("max_commands", document["defaults"]["max_commands"]),
                    )
                runner_versions.append(trace["runner_version"])
                atomic_write(args.output / f"{case['id']}.trace.json", dump_json(trace))
                result = grade_trace(trace, document["defaults"])
                atomic_write(args.output / f"{case['id']}.grade.json", dump_json(result))
                results.append(result)
            executed = [result for result in results if result["status"] != "skipped"]
            summary = {
                "schema_version": 1,
                "status": "passed" if executed and all(result["status"] == "passed" for result in executed) else ("skipped" if not executed else "failed"),
                "source_revision": git_output(args.root.resolve(), "rev-parse", "HEAD"),
                "runner": args.runner,
                "runner_versions": sorted(set(runner_versions)),
                "model": args.model or "runner-default",
                "skill_contracts": {
                    case["skill"]: case["skill_contract_version"]
                    for case in selected
                },
                "input_snapshots": {
                    case["id"]: input_snapshot_sha256(case)
                    for case in selected
                },
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
