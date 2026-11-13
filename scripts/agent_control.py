#!/usr/bin/env python3
"""Deterministic task, change-impact, context, and documentation controls."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import regress  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

TASK_CLASSES = {"feature", "fix", "docs", "tooling", "dependency", "review", "release"}
TASK_STATUSES = {"planned", "approved", "in_progress", "blocked", "review", "done"}
SOCS = {"TINY", "MINI", "STD", "PRO"}
PDKS = {"IHP130", "ICS55", "GF180", "SKY130"}
RANK = {
    "documentation": 0,
    "agents": 10,
    "publication": 20,
    "quality": 20,
    "embedded_c": 30,
    "tiny_rtl": 40,
    "full": 50,
}
JOB_NAMES = (
    "quality_fixtures",
    "skill_eval",
    "regression_smoke",
    "regression_ihp130",
    "regression_gf180",
    "regression_ics55",
    "regression_sky130",
    "development_environment",
)
REVISION_RE = re.compile(r"^[0-9a-f]{40}$")
TASK_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
LINK_RE = re.compile(r"\[[^\]\n]+\]\(([^)\n]+)\)")


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read JSON {path}: {error}") from error


def dump_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def emit_json(data: Any, output: Path | None) -> None:
    text = dump_json(data)
    if output is None:
        sys.stdout.write(text)
    else:
        atomic_write(output, text)
        print(f"result: {output.resolve()}")


def git_output(root: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *arguments], text=True, stderr=subprocess.STDOUT
    ).strip()


def safe_relative_path(value: str) -> bool:
    path = Path(value)
    return bool(value) and not path.is_absolute() and ".." not in path.parts


def check_keys(
    value: Any, label: str, required: set[str], optional: set[str], issues: list[str]
) -> dict[str, Any]:
    if not isinstance(value, dict):
        issues.append(f"{label} must be an object")
        return {}
    missing = sorted(required - set(value))
    unknown = sorted(set(value) - required - optional)
    if missing:
        issues.append(f"{label} missing fields: {', '.join(missing)}")
    if unknown:
        issues.append(f"{label} unknown fields: {', '.join(unknown)}")
    return value


def string_list(value: Any, label: str, issues: list[str], *, nonempty: bool = False) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        issues.append(f"{label} must be a list of non-empty strings")
        return []
    if nonempty and not value:
        issues.append(f"{label} must not be empty")
    return value


def validate_task(task: Any, root: Path | None = None) -> list[str]:
    issues: list[str] = []
    required = {
        "schema_version",
        "task_id",
        "task_class",
        "base_revision",
        "scope",
        "acceptance",
        "validation",
        "execution",
        "status",
    }
    optional = {"target_socs", "specification", "phase", "evidence", "resolves_gaps"}
    task = check_keys(task, "task", required, optional, issues)
    if not task:
        return issues
    if task.get("schema_version") != 1:
        issues.append("schema_version must be 1")
    if not isinstance(task.get("task_id"), str) or not TASK_ID_RE.fullmatch(task["task_id"]):
        issues.append("task_id must be lowercase kebab-case")
    if task.get("task_class") not in TASK_CLASSES:
        issues.append(f"task_class must be one of {sorted(TASK_CLASSES)}")
    if not isinstance(task.get("base_revision"), str) or not REVISION_RE.fullmatch(
        task["base_revision"]
    ):
        issues.append("base_revision must be a full lowercase Git revision")
    if task.get("status") not in TASK_STATUSES:
        issues.append(f"status must be one of {sorted(TASK_STATUSES)}")

    targets = task.get("target_socs", [])
    string_list(targets, "target_socs", issues)
    if any(target not in SOCS for target in targets):
        issues.append("target_socs contains an unsupported SoC")
    if len(set(targets)) != len(targets):
        issues.append("target_socs must not contain duplicates")
    resolving = string_list(task.get("resolves_gaps", []), "resolves_gaps", issues)
    if any(not TASK_ID_RE.fullmatch(item) for item in resolving):
        issues.append("resolves_gaps must contain lowercase kebab-case IDs")

    specification = task.get("specification")
    if specification is not None:
        specification = check_keys(
            specification, "specification", {"path", "revision"}, set(), issues
        )
        if specification:
            if not safe_relative_path(specification["path"]):
                issues.append("specification.path must be repository-relative")
            if not REVISION_RE.fullmatch(specification["revision"]):
                issues.append("specification.revision must be a full Git revision")
            if root is not None and not (root / specification["path"]).is_file():
                issues.append(f"specification.path does not exist: {specification['path']}")

    scope = check_keys(
        task.get("scope"),
        "scope",
        {"summary", "allowed_paths", "forbidden_paths", "non_goals"},
        set(),
        issues,
    )
    if scope:
        if not isinstance(scope["summary"], str) or not scope["summary"].strip():
            issues.append("scope.summary must be non-empty")
        for field in ("allowed_paths", "forbidden_paths"):
            paths = string_list(scope[field], f"scope.{field}", issues)
            if any(not safe_relative_path(path) for path in paths):
                issues.append(f"scope.{field} contains an unsafe path")
        string_list(scope["non_goals"], "scope.non_goals", issues)

    acceptance = string_list(task.get("acceptance"), "acceptance", issues, nonempty=True)
    if any(not item.strip() for item in acceptance):
        issues.append("acceptance entries must be non-empty")

    validation = check_keys(
        task.get("validation"), "validation", {"risk", "mode", "profiles", "pdks"}, set(), issues
    )
    risk = None
    if validation:
        risk = validation["risk"]
        if risk not in {"low", "medium", "high"}:
            issues.append("validation.risk must be low, medium, or high")
        if validation["mode"] not in {"fast", "affected", "full"}:
            issues.append("validation.mode must be fast, affected, or full")
        profiles = string_list(validation["profiles"], "validation.profiles", issues)
        if any(not safe_relative_path(path) or not path.endswith(".mk") for path in profiles):
            issues.append("validation.profiles must contain repository-relative .mk paths")
        if root is not None:
            for profile in profiles:
                if not (root / profile).is_file():
                    issues.append(f"validation profile does not exist: {profile}")
        pdks = string_list(validation["pdks"], "validation.pdks", issues)
        if any(pdk not in PDKS for pdk in pdks):
            issues.append("validation.pdks contains an unsupported PDK")
        if len(set(pdks)) != len(pdks):
            issues.append("validation.pdks must not contain duplicates")

    execution = check_keys(
        task.get("execution"),
        "execution",
        {"mode", "worktree", "artifact_root"},
        {"approval"},
        issues,
    )
    approval = None
    if execution:
        if execution["mode"] not in {"read-only", "workspace-write"}:
            issues.append("execution.mode must be read-only or workspace-write")
        if not isinstance(execution["worktree"], str) or not execution["worktree"]:
            issues.append("execution.worktree must be non-empty")
        artifact_root = execution["artifact_root"]
        if not isinstance(artifact_root, str) or not artifact_root.startswith("build/"):
            issues.append("execution.artifact_root must be below build/")
        elif not safe_relative_path(artifact_root):
            issues.append("execution.artifact_root must be repository-relative")
        approval = execution.get("approval")
        if approval is not None:
            approval = check_keys(
                approval,
                "execution.approval",
                {"approved_by", "reference", "plan_sha256"},
                set(),
                issues,
            )
            if approval:
                for field in ("approved_by", "reference"):
                    if not isinstance(approval[field], str) or not approval[field].strip():
                        issues.append(f"execution.approval.{field} must be non-empty")
                if not re.fullmatch(r"[0-9a-f]{64}", approval["plan_sha256"]):
                    issues.append("execution.approval.plan_sha256 must be a SHA-256 digest")

    if task.get("task_class") == "feature":
        if not targets:
            issues.append("feature tasks require target_socs")
        if specification is None:
            issues.append("feature tasks require specification")
        if not isinstance(task.get("phase"), str) or not task["phase"].strip():
            issues.append("feature tasks require phase")
    if execution and execution.get("mode") == "workspace-write":
        if (task.get("task_class") == "feature" or risk == "high") and approval is None:
            issues.append("feature or high-risk writes require explicit approval")
    if task.get("status") == "approved" and execution and execution.get("mode") == "workspace-write":
        if approval is None:
            issues.append("approved write tasks require an approval record")
    evidence = task.get("evidence", [])
    if not isinstance(evidence, list):
        issues.append("evidence must be a list")
        evidence = []
    for index, item in enumerate(evidence):
        item = check_keys(item, f"evidence[{index}]", {"kind", "uri", "status"}, set(), issues)
        if item and item["status"] not in {"PASS", "FAIL", "SKIPPED", "NOT_RUN"}:
            issues.append(f"evidence[{index}].status is invalid")
    if task.get("status") == "done" and not evidence:
        issues.append("done tasks require evidence")
    return issues


def render_task_prompt(task: dict[str, Any]) -> str:
    issues = validate_task(task)
    if issues:
        raise ValueError("cannot render an invalid task: " + "; ".join(issues))
    lines = [
        f"Task: {task['task_id']}",
        f"Class: {task['task_class']}",
        f"Base revision: {task['base_revision']}",
        f"Target SoCs: {', '.join(task.get('target_socs', [])) or 'N/A'}",
        f"Phase: {task.get('phase', 'N/A')}",
        f"Scope: {task['scope']['summary']}",
        f"Allowed paths: {', '.join(task['scope']['allowed_paths']) or 'N/A'}",
        f"Forbidden paths: {', '.join(task['scope']['forbidden_paths']) or 'N/A'}",
        f"Non-goals: {', '.join(task['scope']['non_goals']) or 'N/A'}",
        f"Execution: {task['execution']['mode']}",
        f"Validation: {task['validation']['mode']} / {task['validation']['risk']}",
        f"Profiles: {', '.join(task['validation']['profiles']) or 'N/A'}",
        f"PDKs: {', '.join(task['validation']['pdks']) or 'N/A'}",
        "Acceptance:",
    ]
    lines.extend(f"- {item}" for item in task["acceptance"])
    approval = task["execution"].get("approval")
    if approval:
        lines.append(f"Approved preflight source: {approval['reference']}")
        lines.append(f"Approved plan SHA-256: {approval['plan_sha256']}")
    return "\n".join(lines) + "\n"


def normalize_file(path: str) -> str:
    path = path.strip().replace("\\", "/")
    if not safe_relative_path(path):
        raise ValueError(f"changed path must be repository-relative: {path}")
    return path


def changed_files(root: Path, base: str | None, head: str) -> list[str]:
    if base:
        output = git_output(root, "diff", "--name-only", "--diff-filter=ACMRD", f"{base}...{head}")
        return sorted({normalize_file(line) for line in output.splitlines() if line})
    tracked = git_output(root, "diff", "--name-only", "--diff-filter=ACMRD", "HEAD")
    untracked = git_output(root, "ls-files", "--others", "--exclude-standard")
    return sorted(
        {normalize_file(line) for line in (*tracked.splitlines(), *untracked.splitlines()) if line}
    )


def load_impact(root: Path) -> dict[str, Any]:
    policy = read_json(root / "quality/change_impact.json")
    if policy.get("schema_version") != 1:
        raise ValueError("change impact schema_version must be 1")
    names = {item["name"] for item in policy["classes"]}
    if names != set(RANK):
        raise ValueError(f"change impact classes must be exactly {sorted(RANK)}")
    if set(policy["job_policy"]) != set(RANK):
        raise ValueError("job_policy must define every classification")
    for name, jobs in policy["job_policy"].items():
        if set(jobs) != set(JOB_NAMES) or any(not isinstance(value, bool) for value in jobs.values()):
            raise ValueError(f"job_policy.{name} must define boolean {JOB_NAMES}")
    return policy


def classify_files(policy: dict[str, Any], files: list[str]) -> tuple[str, list[dict[str, str]]]:
    classification = "documentation"
    matches: list[dict[str, str]] = []
    for path in files:
        selected = "full"
        pattern = None
        for candidate in policy["classes"]:
            for candidate_pattern in candidate["patterns"]:
                if fnmatch.fnmatchcase(path, candidate_pattern):
                    selected = candidate["name"]
                    pattern = candidate_pattern
                    break
            if pattern is not None:
                break
        matches.append({"file": path, "classification": selected, "pattern": pattern or "<default>"})
        if RANK[selected] > RANK[classification]:
            classification = selected
    return classification, matches


def regression_commands(pdk: str, include_long: bool = False) -> list[str]:
    commands, _ = regress.select_regression("pr", pdk)
    commands = regress.select_tiny_p7_iverilog(commands, "include" if include_long else "exclude")
    commands = regress.behavioral_only(commands)
    return [shlex.join(["make", f"CONFIG={profile}", *values]) for profile, values in commands]


def create_plan(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve()
    policy = load_impact(root)
    if args.files is not None:
        files = sorted({normalize_file(path) for path in args.files})
    elif args.files_file is not None:
        files = sorted(
            {
                normalize_file(line)
                for line in args.files_file.read_text(encoding="utf-8").splitlines()
                if line.strip()
            }
        )
    else:
        files = changed_files(root, args.base, args.head)
    classification, matches = classify_files(policy, files)
    forced_full = args.mode == "full" or args.event in {"push", "schedule", "workflow_dispatch"}
    selected = "full" if forced_full else classification
    flags = dict(policy["job_policy"][selected])
    flags["quality_fast"] = True
    if not files and not forced_full:
        flags = {name: False for name in JOB_NAMES}
        flags["quality_fast"] = True
        selected = "empty"
    commands: dict[str, list[str]] = {
        "quality_fast": [
            "make check-fast",
            "ruff check .",
            "yamllint .github .yamllint.yml",
            "actionlint",
        ]
    }
    if flags["quality_fixtures"]:
        commands["quality_fixtures"] = ["python3 -m pytest -q"]
    if flags["skill_eval"]:
        commands["skill_eval"] = ["python3 scripts/skill_eval.py validate --root ."]
    for pdk in sorted(PDKS):
        key = f"regression_{pdk.lower()}"
        if flags[key]:
            commands[key] = regression_commands(pdk, include_long=forced_full)
    if flags["regression_smoke"]:
        commands["regression_smoke"] = [
            shlex.join(["make", f"CONFIG={profile}", *values])
            for profile, values in regress.SMOKE_COMMANDS
        ]
    if flags["development_environment"]:
        commands["development_environment"] = [
            "python3 scripts/regress.py --root . --suite pr --pdk IHP130 --behavioral-only "
            "(in Docker and Nix)"
        ]
    return {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_revision": git_output(root, "rev-parse", args.head),
        "base": args.base,
        "event": args.event,
        "mode": args.mode,
        "classification": classification,
        "selected_policy": selected,
        "selection_reason": "full event or explicit override" if forced_full else "changed paths",
        "changed_files": files,
        "matched_rules": matches,
        "flags": flags,
        "commands": commands,
        "coverage": {
            "hosted_behavioral_only": True,
            "synthesis_netlist_sta": "NOT_RUN in behavioral jobs; use explicit full-flow evidence"
        },
    }


def write_github_outputs(plan: dict[str, Any], path: Path) -> None:
    with path.open("a", encoding="utf-8") as output:
        output.write(f"classification={plan['selected_policy']}\n")
        output.write(f"changed_files_count={len(plan['changed_files'])}\n")
        for name, value in plan["flags"].items():
            output.write(f"{name}={str(value).lower()}\n")


def write_step_summary(plan: dict[str, Any], path: Path) -> None:
    lines = [
        "## Change impact plan",
        "",
        f"- Policy: `{plan['selected_policy']}` ({plan['selection_reason']})",
        f"- Changed files: {len(plan['changed_files'])}",
        f"- Source revision: `{plan['source_revision']}`",
        "",
        "| Job | Decision |",
        "| --- | --- |",
    ]
    for name, value in plan["flags"].items():
        lines.append(f"| `{name}` | {'RUN' if value else 'SKIP'} |")
    lines.extend(["", "Synthesis, netlist and STA remain NOT_RUN in behavioral-only jobs.", ""])
    with path.open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def agent_context(root: Path) -> dict[str, Any]:
    profiles = []
    for path in sorted((root / "configs").glob("*/*.mk")):
        values: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"^([A-Z][A-Z0-9_]+)\s*(?::=|\?=|=)\s*([^#\s]+)", line)
            if match:
                values[match.group(1)] = match.group(2)
        profiles.append(
            {
                "path": path.relative_to(root).as_posix(),
                "soc": values.get("SOC", "MINI"),
                "pdk": values.get("PDK", "IHP130"),
                "app": values.get("APP", "bringup"),
            }
        )
    reusable = (root / ".github/workflows/_regression.yml").read_text(encoding="utf-8")
    return {
        "schema_version": 1,
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "dependency_lock_sha256": hashlib.sha256(
            (root / "dependencies/dependencies.lock.json").read_bytes()
        ).hexdigest(),
        "profiles": profiles,
        "regression_pdk_profiles": regress.PDK_PR_PROFILES,
        "tiny_profiles": regress.TINY_PROFILES,
        "hosted_behavioral_only": "--behavioral-only" in reusable,
        "metrics_mode": read_json(root / "quality/metrics/policy.json")["mode"],
        "task_contract": ".agents/task.schema.json",
        "change_impact": "quality/change_impact.json",
    }


def markdown_files(root: Path) -> list[Path]:
    output = git_output(root, "ls-files", "*.md")
    return [Path(path) for path in output.splitlines() if path]


GENERATED_INPUT_PREFIXES = (
    "build/",
    "dist/",
    ".cache/",
    ".sw_build/",
    "rtl/managed/",
    "physical/pdk/",
    "app/coremark/coremark-main/",
    "app/fatfs/ff16/",
    "app/lvgl/lvgl-main/",
)


def is_generated_input(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in GENERATED_INPUT_PREFIXES)


def documentation_issues(root: Path) -> list[str]:
    issues: list[str] = []
    for relative in markdown_files(root):
        path = root / relative
        text = path.read_text(encoding="utf-8")
        for target in LINK_RE.findall(text):
            target = target.strip().strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or not parsed.path:
                continue
            if parsed.path.startswith("/"):
                destination = root / unquote(parsed.path).lstrip("/")
            else:
                destination = path.parent / unquote(parsed.path)
            try:
                relative_destination = destination.resolve().relative_to(root.resolve())
            except ValueError:
                issues.append(f"{relative}: link leaves repository: {target}")
                continue
            if not destination.exists() and not is_generated_input(relative_destination.as_posix()):
                issues.append(f"{relative}: broken local link: {target}")
        paragraphs = re.split(r"\n\s*\n", text)
        previous = ""
        for paragraph in paragraphs:
            normalized = " ".join(paragraph.strip().split())
            if len(normalized) >= 80 and normalized == previous:
                issues.append(f"{relative}: consecutive duplicate paragraph: {normalized[:80]}...")
            previous = normalized
            lines = paragraph.splitlines()
            for size in range(1, min(6, len(lines) // 2 + 1)):
                for index in range(len(lines) - 2 * size + 1):
                    first = lines[index : index + size]
                    second = lines[index + size : index + 2 * size]
                    repeated = " ".join(" ".join(first).split())
                    if first == second and len(repeated) >= 80:
                        issues.append(f"{relative}: consecutive duplicate text: {repeated[:80]}...")
    return sorted(set(issues))


def scope_issues(task: dict[str, Any], files: list[str]) -> list[str]:
    scope = task.get("scope", {})
    allowed = scope.get("allowed_paths", [])
    forbidden = scope.get("forbidden_paths", [])
    issues = []
    for path in files:
        if any(fnmatch.fnmatchcase(path, pattern) for pattern in forbidden):
            issues.append(f"path is forbidden by task scope: {path}")
        if allowed and not any(fnmatch.fnmatchcase(path, pattern) for pattern in allowed):
            issues.append(f"path is outside the task scope: {path}")
    return sorted(set(issues))


def tiny_snapshot_status(root: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "schema_version": 1,
        "inventory": "publications/datasheets/tiny/tiny.json",
        "status": "BLOCKED",
        "issues": [],
    }
    try:
        from publications import tiny_reference as tiny

        config = tiny.read(root / tiny.BOOK / "tiny.json")
        source_revision = config["source_revision"]
        if not REVISION_RE.fullmatch(source_revision):
            raise ValueError("Tiny source_revision must be a complete reviewed SHA")
        collected = tiny.collect(config, check_snapshot=False)
        technical = sorted(
            path
            for path in collected["source_paths"]
            if not path.startswith("publications/") and path != "dependencies/dependencies.lock.json"
        )
        changed = git_output(root, "diff", "--name-only", source_revision, "--", *technical)
        changed_files = sorted(path for path in changed.splitlines() if path)
        result.update(
            source_revision=source_revision,
            technical_source_count=len(technical),
            changed_files=changed_files,
            status="FAIL" if changed_files else "PASS",
            validation=(
                "python3 -m pytest -q tests/test_publication_tiny_refresh.py "
                "tests/test_publication_tiny_alignment.py"
            ),
        )
    except (ImportError, KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        result["issues"].append(str(error))
    return result


def github_preflight(root: Path, args: argparse.Namespace) -> dict[str, Any]:
    if not args.online:
        return {"status": "NOT_RUN", "repository": args.repository, "base": args.base_branch}
    try:
        from scripts.pr_workflow import checks_report, required_check_contexts

        required = required_check_contexts(args.repository, args.base_branch, root)
        result: dict[str, Any] = {
            "status": "PASS",
            "repository": args.repository,
            "base": args.base_branch,
            "required_contexts": required,
        }
        if args.pr is not None:
            report = checks_report(root, args.pr, args.repository, required)
            result.update(status=report["status"], head_sha=report["head_sha"], report=report)
        return result
    except (OSError, RuntimeError) as error:
        return {
            "status": "BLOCKED",
            "repository": args.repository,
            "base": args.base_branch,
            "issues": [str(error)],
        }


def local_tool_status(online: bool) -> list[dict[str, str]]:
    tools = [
        {"name": "git", "status": "PASS" if shutil.which("git") else "BLOCKED"},
        {"name": "python3", "status": "PASS" if shutil.which("python3") else "BLOCKED"},
    ]
    if online:
        tools.append({"name": "gh", "status": "PASS" if shutil.which("gh") else "BLOCKED"})
    return tools


def create_preflight(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve()
    task = read_json(args.task)
    issues = validate_task(task, root)
    tools = local_tool_status(args.online)
    issues.extend(f"required local tool is unavailable: {tool['name']}" for tool in tools if tool["status"] != "PASS")
    base = args.base or task.get("base_revision")
    plan = create_plan(
        argparse.Namespace(
            root=root,
            base=base,
            head=args.head,
            files=None,
            files_file=None,
            mode="full" if task.get("validation", {}).get("mode") == "full" else args.mode,
            event=args.event,
        )
    )
    issues.extend(scope_issues(task, plan["changed_files"]))
    if isinstance(base, str) and REVISION_RE.fullmatch(base):
        ancestor = subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor", base, args.head],
            capture_output=True,
            check=False,
        )
        if ancestor.returncode:
            issues.append(f"task base_revision is not an ancestor of {args.head}: {base}")
    worktree = {
        "root": str(root),
        "git_root": git_output(root, "rev-parse", "--show-toplevel"),
        "clean": not git_output(root, "status", "--porcelain", "--untracked-files=all"),
    }
    if worktree["git_root"] != str(root):
        issues.append(f"task root is not the Git worktree root: {root}")
    if task.get("execution", {}).get("mode") == "workspace-write" and not worktree["clean"]:
        issues.append("workspace-write preflight requires a clean worktree before execution")
    snapshot = tiny_snapshot_status(root)
    if snapshot["status"] != "PASS":
        issues.append(f"Tiny reviewed-source snapshot is {snapshot['status']}")
    github = github_preflight(root, args)
    if github["status"] not in {"PASS", "NOT_RUN"}:
        issues.append(f"GitHub preflight is {github['status']}")
    issues.extend(f"github: {issue}" for issue in github.get("issues", []))
    gaps = gap_status(task, root)
    issues.extend(gaps["issues"])
    return {
        "schema_version": 1,
        "task_id": task.get("task_id"),
        "status": "BLOCKED" if issues else "READY",
        "issues": sorted(set(issues)),
        "dependency_lock_sha256": hashlib.sha256((root / "dependencies/dependencies.lock.json").read_bytes()).hexdigest(),
        "tools": tools,
        "worktree": worktree,
        "validation_plan": plan,
        "reviewed_source_snapshot": snapshot,
        "github": github,
        "known_gaps": gaps["known_gaps"],
        "resolving_gaps": gaps["resolving_gaps"],
    }


def gap_status(task: dict[str, Any], root: Path) -> dict[str, Any]:
    try:
        from scripts.validation_gaps import load_gaps, relevant_gaps

        all_gaps = load_gaps(root)
        selected = relevant_gaps(task, all_gaps)
        resolved = set(task.get("resolves_gaps", []))
        known = {gap["id"] for gap in all_gaps}
        unknown = sorted(resolved - known)
        result: dict[str, Any] = {
            "status": "BLOCKED" if unknown else "PASS",
            "issues": [f"unknown validation gap IDs: {', '.join(unknown)}"] if unknown else [],
            "known_gaps": [
                {
                    "id": gap["id"],
                    "status": gap["status"],
                    "scope": gap["scope"],
                    "blocked_stages": gap["blocked_stages"],
                    "review_by": gap["review_by"],
                    "prohibited_claims": gap["prohibited_claims"],
                }
                for gap in selected
            ],
            "resolving_gaps": sorted(resolved & known),
        }
        text = " ".join([task["scope"]["summary"], *task["acceptance"]]).lower().replace("_", " ")
        for gap in selected:
            targets = set(task.get("target_socs", []))
            pdks = set(task.get("validation", {}).get("pdks", []))
            profiles = set(task.get("validation", {}).get("profiles", []))
            if not (targets or pdks or profiles):
                continue
            if profiles and gap["scope"]["profile"] not in profiles:
                continue
            for stage in gap["blocked_stages"]:
                normalized = stage.replace("_", " ")
                if normalized in text or normalized.split()[0] in text:
                    result["issues"].append(
                        f"validation gap {gap['id']} blocks {stage}; declare resolves_gaps only for an explicit resolution task"
                    )
        if result["issues"]:
            result["status"] = "BLOCKED"
        return result
    except (ImportError, KeyError, OSError, ValueError) as error:
        return {"status": "BLOCKED", "issues": [str(error)], "known_gaps": [], "resolving_gaps": []}


def artifact_evidence(root: Path, task: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    artifact_root = root / task["execution"]["artifact_root"]
    records = []
    issues = []
    for path in sorted(artifact_root.rglob("*.json")):
        relative = path.relative_to(root).as_posix()
        record: dict[str, Any] = {"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        try:
            data = read_json(path)
            if isinstance(data, dict):
                for key in (
                    "status",
                    "flow_status",
                    "source_revision",
                    "run_id",
                    "task_id",
                    "attempt",
                    "started_at",
                    "finished_at",
                    "child_pid",
                    "child_cleanup_pending",
                    "log",
                    "output_sha256",
                    "error",
                ):
                    if key in data:
                        record[key] = data[key]
                if data.get("source_revision") and data["source_revision"] != git_output(root, "rev-parse", "HEAD"):
                    issues.append(f"artifact source revision differs from HEAD: {relative}")
            else:
                record["status"] = "UNKNOWN"
        except (ValueError, OSError) as error:
            issues.append(f"cannot read artifact {relative}: {error}")
            record["status"] = "UNKNOWN"
        records.append(record)
    return records, issues


def build_handoff(task: dict[str, Any], root: Path, next_action: str) -> dict[str, Any]:
    if not next_action.strip():
        raise ValueError("handoff requires a non-empty next action")
    issues = validate_task(task, root)
    artifacts, artifact_issues = artifact_evidence(root, task)
    issues.extend(artifact_issues)
    gaps = gap_status(task, root)
    issues.extend(gaps["issues"])
    evidence = task.get("evidence", [])
    counts = {status: sum(item["status"] == status for item in evidence) for status in ("PASS", "FAIL", "SKIPPED", "NOT_RUN")}
    if counts["FAIL"]:
        issues.append("handoff contains failed evidence")
    status = "blocked" if issues else task["status"]
    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "task_id": task["task_id"],
        "base_revision": task["base_revision"],
        "source_revision": git_output(root, "rev-parse", "HEAD"),
        "task_status": task["status"],
        "status": status,
        "issues": sorted(set(issues)),
        "next_action": next_action,
        "worktree": {
            "path": task["execution"]["worktree"],
            "clean": not git_output(root, "status", "--porcelain", "--untracked-files=all"),
        },
        "artifact_root": task["execution"]["artifact_root"],
        "acceptance": task["acceptance"],
        "evidence": evidence,
        "evidence_counts": counts,
        "artifacts": artifacts,
        "processes": [item for item in artifacts if "child_pid" in item or "run_id" in item],
        "known_gaps": gaps["known_gaps"],
        "resolving_gaps": gaps["resolving_gaps"],
        "prohibited_actions": [
            "Do not rerun passing evidence merely because the session resumed",
            "Do not claim SKIPPED or NOT_RUN evidence as PASS",
            "Do not delete retained artifacts or worktrees outside the cleanup contract",
            *task["scope"]["non_goals"],
        ],
    }


def write_handoff_markdown(document: dict[str, Any], path: Path, root: Path) -> None:
    try:
        path.resolve().relative_to((root / "build").resolve())
    except ValueError as error:
        raise ValueError("handoff Markdown must remain below the build artifact root") from error
    lines = [
        f"# Agent handoff: {document['task_id']}",
        "",
        f"- Status: `{document['status']}`",
        f"- Source: `{document['source_revision']}`",
        f"- Next action: {document['next_action']}",
        "",
        "## Evidence",
        "",
        "| Kind | Status | URI |",
        "| --- | --- | --- |",
    ]
    lines.extend(f"| {item['kind']} | {item['status']} | `{item['uri']}` |" for item in document["evidence"])
    lines.extend(["", "## Artifacts", ""])
    lines.extend(f"- `{item['path']}` (`{item['sha256']}`)" for item in document["artifacts"])
    lines.extend(["", "## Prohibited actions", ""])
    lines.extend(f"- {item}" for item in document["prohibited_actions"])
    atomic_write(path, "\n".join(lines) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    task = subparsers.add_parser("task")
    task_subparsers = task.add_subparsers(dest="task_command", required=True)
    for name in ("validate", "render"):
        task_parser = task_subparsers.add_parser(name)
        task_parser.add_argument("--task", type=Path, required=True)
        task_parser.add_argument("--root", type=Path, default=ROOT)
    handoff = task_subparsers.add_parser("handoff")
    handoff.add_argument("--task", type=Path, required=True)
    handoff.add_argument("--root", type=Path, default=ROOT)
    handoff.add_argument("--next", required=True)
    handoff.add_argument("--output", type=Path)
    handoff.add_argument("--markdown", type=Path)

    plan = subparsers.add_parser("plan")
    plan.add_argument("--root", type=Path, default=ROOT)
    plan.add_argument("--base")
    plan.add_argument("--head", default="HEAD")
    plan.add_argument("--files", nargs="*")
    plan.add_argument("--files-file", type=Path)
    plan.add_argument("--mode", choices=("auto", "full"), default="auto")
    plan.add_argument(
        "--event",
        choices=("local", "pull_request", "push", "schedule", "workflow_dispatch"),
        default="local",
    )
    plan.add_argument("--output", type=Path)
    plan.add_argument("--github-output", type=Path)
    plan.add_argument("--step-summary", type=Path)

    context = subparsers.add_parser("context")
    context.add_argument("--root", type=Path, default=ROOT)
    context.add_argument("--output", type=Path)

    docs = subparsers.add_parser("docs")
    docs.add_argument("--root", type=Path, default=ROOT)
    docs.add_argument("--output", type=Path)

    snapshot = subparsers.add_parser("snapshot")
    snapshot.add_argument("--root", type=Path, default=ROOT)
    snapshot.add_argument("--output", type=Path)

    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("--root", type=Path, default=ROOT)
    preflight.add_argument("--task", type=Path, required=True)
    preflight.add_argument("--base")
    preflight.add_argument("--head", default="HEAD")
    preflight.add_argument("--mode", choices=("auto", "full"), default="auto")
    preflight.add_argument("--event", choices=("local", "pull_request"), default="local")
    preflight.add_argument("--repository", default="retroSoC/retroSoC")
    preflight.add_argument("--base-branch", default="dev")
    preflight.add_argument("--pr", type=int)
    preflight.add_argument("--online", action="store_true")
    preflight.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "task":
            task = read_json(args.task)
            issues = validate_task(task, args.root.resolve())
            if args.task_command == "handoff":
                document = build_handoff(task, args.root.resolve(), args.next)
                if args.markdown:
                    write_handoff_markdown(document, args.markdown, args.root.resolve())
                emit_json(document, args.output)
                return int(document["status"] == "blocked")
            if args.task_command == "render":
                if issues:
                    for issue in issues:
                        print(f"task: {issue}", file=sys.stderr)
                    return 1
                sys.stdout.write(render_task_prompt(task))
                return 0
            result = {"schema_version": 1, "task": str(args.task), "valid": not issues, "issues": issues}
            emit_json(result, None)
            return int(bool(issues))
        if args.command == "plan":
            plan = create_plan(args)
            emit_json(plan, args.output)
            if args.github_output:
                write_github_outputs(plan, args.github_output)
            if args.step_summary:
                write_step_summary(plan, args.step_summary)
            return 0
        if args.command == "context":
            emit_json(agent_context(args.root.resolve()), args.output)
            return 0
        if args.command == "docs":
            issues = documentation_issues(args.root.resolve())
            result = {
                "schema_version": 1,
                "status": "failed" if issues else "passed",
                "issues": issues,
            }
            emit_json(result, args.output)
            for issue in issues:
                print(f"documentation: {issue}", file=sys.stderr)
            return int(bool(issues))
        if args.command == "snapshot":
            result = tiny_snapshot_status(args.root.resolve())
            emit_json(result, args.output)
            for issue in result["issues"]:
                print(f"snapshot: {issue}", file=sys.stderr)
            return int(result["status"] != "PASS")
        if args.command == "preflight":
            result = create_preflight(args)
            emit_json(result, args.output)
            for issue in result["issues"]:
                print(f"preflight: {issue}", file=sys.stderr)
            return int(result["status"] != "READY")
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"agent control: {error}", file=sys.stderr)
        return 2
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
