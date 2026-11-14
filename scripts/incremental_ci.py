#!/usr/bin/env python3
"""Evaluate evidence-aware CI reuse without silently skipping required work."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import emit_json, git_output, read_json, safe_relative_path  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402
from scripts.flow_control import digest_json, source_state  # noqa: E402
from scripts.pr_workflow import (  # noqa: E402
    evaluate_checks,
    paginated_check_data,
    required_check_contexts,
)
from scripts.pytest_shards import create_plan  # noqa: E402

REVISION = re.compile(r"^[0-9a-f]{40}$")
MANIFEST_FIELDS = (
    "node_ids_sha256",
    "test_count",
    "pytest_version",
    "tool_inputs_sha256",
    "policy_sha256",
    "durations_sha256",
)


class EvidenceMissing(RuntimeError):
    pass


def load_policy(root: Path) -> dict[str, Any]:
    policy = read_json(root / "quality/incremental-ci.json")
    if policy.get("schema_version") != 1 or policy.get("mode") not in {"shadow", "execute"}:
        raise ValueError("incremental CI requires schema_version=1 and shadow or execute mode")
    if not isinstance(policy.get("enabled"), bool) or not isinstance(policy.get("jobs"), list) or len(policy["jobs"]) != 1:
        raise ValueError("incremental CI requires an enabled flag and exactly one shadow job")
    for job in policy["jobs"]:
        if set(job) != {"id", "required_context", "inputs", "configuration_files", "configuration"}:
            raise ValueError("incremental CI job fields are incomplete")
        if not job["id"] or not job["required_context"] or not isinstance(job["configuration"], dict):
            raise ValueError("incremental CI job identity and configuration are invalid")
        for field in ("inputs", "configuration_files"):
            if not isinstance(job[field], list) or not job[field] or any(
                not isinstance(path, str) or not safe_relative_path(path) for path in job[field]
            ):
                raise ValueError(f"incremental CI {field} contains unsafe paths")
    return policy


def reviewed_source_paths(root: Path) -> list[str]:
    from publications import tiny_reference as tiny

    config = tiny.read(root / tiny.BOOK / "tiny.json")
    collected = tiny.collect(config, check_snapshot=False)
    return sorted(
        path
        for path in collected["source_paths"]
        if not path.startswith("publications/") and path != "dependencies/dependencies.lock.json"
    )


def revision(root: Path, value: str) -> str:
    resolved = git_output(root, "rev-parse", value)
    if not REVISION.fullmatch(resolved):
        raise ValueError(f"invalid revision: {resolved}")
    return resolved


def git_bytes(root: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL)


def input_pathspec(path: str) -> str:
    if path.endswith("/**"):
        return path.removesuffix("/**")
    if any(character in path for character in "*?["):
        return f":(glob){path}"
    return path


def tracked_inputs(root: Path, job: dict[str, Any], source_revision: str) -> list[str]:
    arguments = [
        "ls-tree",
        "-r",
        "-z",
        source_revision,
        "--",
        *(input_pathspec(path) for path in job["inputs"]),
    ]
    paths = set()
    for entry in git_bytes(root, *arguments).split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        if metadata.split()[1] == b"blob":
            paths.add(path.decode("utf-8"))
    for path in reviewed_source_paths(root):
        if not safe_relative_path(path):
            raise ValueError(f"reviewed source path is unsafe: {path}")
        paths.add(path)
    if not paths:
        raise ValueError("incremental CI input closure is empty")
    return sorted(paths)


def file_at_revision(root: Path, source_revision: str, path: str) -> bytes:
    try:
        return git_bytes(root, "show", f"{source_revision}:{path}")
    except subprocess.CalledProcessError as error:
        raise ValueError(f"input is missing at {source_revision}: {path}") from error


def managed_input_bytes(root: Path, source_revision: str, path: str) -> bytes:
    lock = json.loads(file_at_revision(root, source_revision, "dependencies/dependencies.lock.json"))
    sources = sorted(lock.get("sources", {}).values(), key=lambda item: len(item["destination"]), reverse=True)
    for source in sources:
        destination = source["destination"]
        if not safe_relative_path(destination):
            continue
        if path != destination and not path.startswith(destination + "/"):
            continue
        repository = root / destination
        if not (repository / ".git").exists():
            continue
        locked_revision = source["revision"]
        entry = git_bytes(root, "ls-tree", source_revision, "--", destination).decode("utf-8")
        fields = entry.split()
        if len(fields) >= 3 and fields[1] == "commit" and fields[2] != locked_revision:
            raise ValueError(f"managed source gitlink differs from its lock: {destination}")
        relative = path.removeprefix(destination).lstrip("/")
        if not relative:
            raise ValueError(f"managed input is not a file: {path}")
        try:
            return git_bytes(repository, "show", f"{locked_revision}:{relative}")
        except subprocess.CalledProcessError as error:
            raise ValueError(f"managed input is missing at {locked_revision}: {path}") from error
    raise ValueError(f"managed input is unavailable at {source_revision}: {path}")


def input_bytes(root: Path, source_revision: str, path: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), "cat-file", "-t", f"{source_revision}:{path}"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip() == "blob":
        return file_at_revision(root, source_revision, path)
    return managed_input_bytes(root, source_revision, path)


def file_set_digest(root: Path, source_revision: str, paths: list[str]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(input_bytes(root, source_revision, path))
        digest.update(b"\0")
    return digest.hexdigest()


def manifest_from_plan(plan: dict[str, Any]) -> dict[str, Any]:
    fields = {field: plan[field] for field in MANIFEST_FIELDS}
    return {**fields, "test_manifest_sha256": digest_json(fields)}


def manifest_from_evidence(document: dict[str, Any]) -> dict[str, Any]:
    missing = [field for field in MANIFEST_FIELDS if field not in document]
    if missing:
        raise ValueError(f"historical fixture evidence is missing fields: {missing}")
    return manifest_from_plan(document)


def job_fingerprint(
    root: Path,
    job: dict[str, Any],
    source_revision: str,
    manifest: dict[str, Any],
) -> dict[str, Any]:
    inputs = tracked_inputs(root, job, source_revision)
    input_sha256 = file_set_digest(root, source_revision, inputs)
    tool_lock_sha256 = file_set_digest(
        root,
        source_revision,
        [
            "dependencies/dependencies.lock.json",
            "requirements/build.txt",
            "requirements/ci.txt",
        ],
    )
    configuration = {
        "values": job["configuration"],
        "files": {
            path: file_at_revision(root, source_revision, path).decode("utf-8")
            for path in job["configuration_files"]
        },
    }
    config_sha256 = digest_json(configuration)
    return {
        "job_id": job["id"],
        "input_files": inputs,
        "input_sha256": input_sha256,
        "tool_lock_sha256": tool_lock_sha256,
        "config_sha256": config_sha256,
        "test_manifest_sha256": manifest["test_manifest_sha256"],
        "fingerprint": digest_json(
            {
                "job_id": job["id"],
                "input_sha256": input_sha256,
                "tool_lock_sha256": tool_lock_sha256,
                "config_sha256": config_sha256,
                "test_manifest_sha256": manifest["test_manifest_sha256"],
            }
        ),
    }


def changed_inputs(root: Path, base: str, head: str, inputs: set[str]) -> list[str]:
    changed = git_output(root, "diff", "--name-only", "--diff-filter=ACMRD", f"{base}...{head}")
    return sorted(
        path
        for path in changed.splitlines()
        if path in inputs or any(candidate.startswith(path + "/") for candidate in inputs)
    )


def previous_is_green(previous: dict[str, Any], required: list[str]) -> bool:
    if previous.get("status") not in {"PASS", "passed", "success"}:
        return False
    contexts = previous.get("contexts")
    if not isinstance(contexts, list) or not contexts:
        return False
    verdicts = {item.get("name"): item.get("status") for item in contexts}
    return all(verdicts.get(context) == "PASS" for context in required) and all(
        status in {"PASS", "SKIPPED"} for status in verdicts.values()
    )


def validate_historical_identity(
    root: Path,
    previous: dict[str, Any],
    workflow_head: str | None,
    current_run: int | None,
    pr_number: int | None,
) -> bool:
    if previous.get("workflow_head_sha") is None:
        return False
    if workflow_head is None:
        raise ValueError("workflow-bound evidence requires the current workflow head")
    previous_head = revision(root, previous.get("workflow_head_sha", ""))
    if previous_head != previous["workflow_head_sha"]:
        raise ValueError("historical workflow head is not canonical")
    if subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", previous_head, workflow_head],
        check=False,
        capture_output=True,
    ).returncode:
        raise ValueError("historical workflow head is not an ancestor of the current workflow head")
    if previous.get("pr_number") != pr_number or pr_number is None:
        raise ValueError("historical evidence must belong to the current pull request")
    run_id = previous.get("workflow_run_id")
    if not isinstance(run_id, int) or isinstance(run_id, bool) or run_id <= 0:
        raise ValueError("historical workflow run ID is missing")
    if current_run is not None and run_id == current_run:
        raise ValueError("current workflow run cannot be its own historical evidence")
    attempt = previous.get("run_attempt")
    if not isinstance(attempt, int) or isinstance(attempt, bool) or attempt <= 0:
        raise ValueError("historical run attempt is missing")
    return True


def evaluate(
    root: Path,
    base: str,
    head: str,
    previous: dict[str, Any] | None,
    event: str,
    execute: bool,
    required: list[str] | None = None,
    workflow_head: str | None = None,
    workflow_run_id: int | None = None,
    pr_number: int | None = None,
) -> dict[str, Any]:
    policy = load_policy(root)
    if execute and (policy["mode"] != "execute" or policy["enabled"] is not True):
        raise ValueError("incremental CI reuse is disabled; use shadow mode only")
    job = policy["jobs"][0]
    base = revision(root, base)
    head = revision(root, head)
    ancestry = subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", base, head],
        check=False,
        capture_output=True,
    )
    if ancestry.returncode:
        raise ValueError(f"base is not an ancestor of head: {base}...{head}")
    if workflow_head is not None:
        workflow_head = revision(root, workflow_head)
        if subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor", workflow_head, head],
            check=False,
            capture_output=True,
        ).returncode:
            raise ValueError("workflow head is not an ancestor of the evaluated revision")
    current_plan = create_plan(root)
    current_manifest = manifest_from_plan(current_plan)
    current = job_fingerprint(root, job, head, current_manifest)
    result: dict[str, Any] = {
        "schema_version": 1,
        "job_id": job["id"],
        "base_revision": base,
        "source_revision": head,
        "workflow_head_sha": workflow_head,
        "workflow_run_id": workflow_run_id,
        "pr_number": pr_number,
        "event": event,
        "mode": policy["mode"],
        "enabled": policy["enabled"],
        "decision": "RUN_FULL",
        "current": current,
        "previous": None,
        "changed_inputs": [],
        "issues": [],
    }
    if event in {"schedule", "workflow_dispatch", "release"}:
        result["reason"] = "scheduled, manual, and release events always require the full flow"
        return result
    if source_state(root)["source_dirty"]:
        result["reason"] = "worktree contains changes not bound to the evaluated head"
        return result
    if previous is None:
        result["reason"] = "no historical evidence was supplied"
        return result
    source_revision = revision(root, previous.get("source_revision", ""))
    workflow_bound = validate_historical_identity(root, previous, workflow_head, workflow_run_id, pr_number)
    if not workflow_bound and subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", source_revision, head],
        check=False,
        capture_output=True,
    ).returncode:
        raise ValueError("historical evidence is not an ancestor of the evaluated head")
    required = required or previous.get("required_contexts") or [job["required_context"]]
    if not required:
        raise ValueError("required contexts must not be empty")
    if not previous_is_green(previous, required):
        result["reason"] = "historical evidence is not a complete green verdict"
        return result
    previous_manifest = manifest_from_evidence(previous)
    try:
        previous_fingerprint = job_fingerprint(root, job, source_revision, previous_manifest)
    except (subprocess.CalledProcessError, ValueError) as error:
        raise EvidenceMissing("historical evaluated revision or its managed inputs are unavailable") from error
    for field in ("fingerprint", "input_sha256", "tool_lock_sha256", "config_sha256", "test_manifest_sha256"):
        if field in previous and previous[field] != previous_fingerprint[field]:
            raise ValueError(f"historical evidence {field} does not match its own source inputs")
    result["previous"] = {
        "source_revision": source_revision,
        "workflow_head_sha": previous.get("workflow_head_sha"),
        "workflow_run_id": previous.get("workflow_run_id"),
        "run_attempt": previous.get("run_attempt"),
        "pr_number": previous.get("pr_number"),
        **previous_fingerprint,
    }
    inputs = set(current["input_files"]) | set(previous_fingerprint["input_files"])
    changed = changed_inputs(root, base, head, inputs)
    result["changed_inputs"] = changed
    mismatches = [
        field
        for field in ("input_sha256", "tool_lock_sha256", "config_sha256", "test_manifest_sha256")
        if current[field] != previous_fingerprint[field]
    ]
    if mismatches:
        result["reason"] = f"input evidence differs: {', '.join(mismatches)}"
        return result
    if current["fingerprint"] != previous_fingerprint["fingerprint"]:
        result["reason"] = "complete job fingerprint differs"
        return result
    if execute:
        result["decision"] = "REUSE_AUTHORIZED"
    else:
        result["decision"] = "SHADOW_REUSE_CANDIDATE"
    result["reason"] = "source, inputs, tools, configuration, and test manifest are identical"
    return result


def pull_request_matches(run: dict[str, Any], number: int) -> bool:
    pulls = run.get("pull_requests")
    return isinstance(pulls, list) and any(
        isinstance(pull, dict) and pull.get("number") == number for pull in pulls
    )


def run_created_at(run: dict[str, Any]) -> datetime:
    value = run.get("created_at")
    if not isinstance(value, str):
        raise ValueError("workflow run creation time is missing")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def select_previous_quality_run(
    repository: str,
    pr_number: int,
    current_run_id: int,
    expected_head: str | None = None,
) -> dict[str, Any]:
    if pr_number <= 0 or current_run_id <= 0:
        raise ValueError("PR and current workflow run IDs must be positive")
    current = gh_json(["api", f"repos/{repository}/actions/runs/{current_run_id}"])
    if current.get("name") != "quality" or current.get("event") != "pull_request":
        raise ValueError("current run must be a pull_request quality run")
    if not pull_request_matches(current, pr_number):
        raise ValueError("current run does not belong to the requested PR")
    if REVISION.fullmatch(current.get("head_sha", "")) is None:
        raise ValueError("current workflow head is missing")
    if expected_head is not None and current["head_sha"] != expected_head:
        raise ValueError("current workflow head differs from the evaluated PR head")
    current_created = run_created_at(current)
    runs = paginated_check_data(
        f"repos/{repository}/actions/runs?event=pull_request&status=success",
        "workflow_runs",
    )
    candidates = []
    for run in runs:
        if (
            run.get("id") == current_run_id
            or run.get("name") != "quality"
            or run.get("event") != "pull_request"
            or run.get("status") != "completed"
            or run.get("conclusion") != "success"
            or not pull_request_matches(run, pr_number)
        ):
            continue
        if REVISION.fullmatch(run.get("head_sha", "")) is None:
            continue
        if not isinstance(run.get("run_attempt"), int) or run["run_attempt"] <= 0:
            continue
        if run_created_at(run) < current_created:
            candidates.append(run)
    candidates.sort(key=lambda run: (run_created_at(run), run["id"]), reverse=True)
    selected = None
    if candidates:
        if len(candidates) > 1 and run_created_at(candidates[0]) == run_created_at(candidates[1]):
            raise EvidenceMissing("earlier quality runs have ambiguous creation order")
        selected = candidates[0]
    return {
        "pr_number": pr_number,
        "current_run_id": current_run_id,
        "current_head_sha": current["head_sha"],
        "current_created_at": current.get("created_at"),
        "candidate_run_ids": [run["id"] for run in candidates],
        "selected_run_id": selected["id"] if selected else None,
        "selected_head_sha": selected["head_sha"] if selected else None,
        "selected_run_attempt": selected["run_attempt"] if selected else None,
        "selected_created_at": selected.get("created_at") if selected else None,
    }


def evidence_from_run(
    root: Path,
    repository: str,
    base_branch: str,
    source_revision: str,
    run_id: int | None,
    require_workflow_identity: bool = False,
    pr_number: int | None = None,
) -> dict[str, Any]:
    if run_id is None:
        document = gh_json(
            ["api", f"repos/{repository}/actions/runs?head_sha={source_revision}&status=success&per_page=20"]
        )
        candidates = [run for run in document.get("workflow_runs", []) if run.get("name") == "quality"]
        if not candidates:
            raise EvidenceMissing(f"no successful quality run at {source_revision}")
        run = candidates[0]
        run_id = run["id"]
    else:
        run = gh_json(["api", f"repos/{repository}/actions/runs/{run_id}"])
    if run.get("head_sha") != source_revision or run.get("conclusion") != "success" or run.get("name") != "quality":
        raise ValueError("source run is not a successful quality run at the requested revision")
    if require_workflow_identity and (
        pr_number is None or not pull_request_matches(run, pr_number)
    ):
        raise ValueError("source run does not belong to the requested PR")
    required = required_check_contexts(repository, base_branch, root)
    check_runs = paginated_check_data(f"repos/{repository}/commits/{source_revision}/check-runs", "check_runs")
    statuses = paginated_check_data(f"repos/{repository}/commits/{source_revision}/status", "statuses")
    verdict = evaluate_checks(source_revision, required, check_runs, statuses)
    if verdict["status"] != "PASS":
        raise ValueError("source run does not have a complete green required-check verdict")
    destination = root / "build/incremental-ci" / f"source-run-{run_id}"
    if destination.exists():
        raise ValueError(f"source evidence destination already exists: {destination}")
    completed = subprocess.run(
        [
            "gh",
            "run",
            "download",
            str(run_id),
            "--repo",
            repository,
            "--name",
            f"quality-fixture-summary-{run_id}-{run.get('run_attempt', 1)}",
            "--dir",
            str(destination),
        ],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode:
        raise EvidenceMissing(f"fixture evidence is unavailable for run {run_id}: {completed.stderr.strip()}")
    summary_path = destination / "summary.json"
    if not summary_path.is_file():
        raise EvidenceMissing(f"fixture summary is missing for run {run_id}")
    summary = read_json(summary_path)
    if require_workflow_identity:
        for field in ("workflow_head_sha", "workflow_run_id", "run_attempt", "pr_number"):
            if field not in summary:
                raise EvidenceMissing(f"fixture summary lacks workflow identity: {field}")
        if summary["workflow_head_sha"] != source_revision:
            raise ValueError("fixture workflow head differs from the source run head")
        if summary["workflow_run_id"] != run_id or summary["run_attempt"] != run.get("run_attempt", 1):
            raise ValueError("fixture run or attempt differs from the source run")
        if summary["pr_number"] != pr_number:
            raise ValueError("fixture PR differs from the source run")
        evaluated_revision = summary.get("source_revision", "")
        if REVISION.fullmatch(evaluated_revision) is None:
            raise ValueError("fixture evaluated revision is not a full Git revision")
        if subprocess.run(
            ["git", "-C", str(root), "cat-file", "-e", f"{evaluated_revision}^{{commit}}"],
            capture_output=True,
            check=False,
        ).returncode:
            from scripts.setup_helpers import fetch_git_repo

            try:
                fetch_git_repo(
                    root,
                    evaluated_revision,
                    "origin",
                    no_tags=True,
                    no_write_fetch_head=True,
                )
            except subprocess.SubprocessError as error:
                raise EvidenceMissing("historical evaluated revision cannot be restored") from error
        if subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor", source_revision, evaluated_revision],
            capture_output=True,
            check=False,
        ).returncode:
            raise ValueError("fixture evaluated revision does not contain its workflow head")
    elif summary.get("source_revision") != source_revision:
        raise ValueError("fixture summary source revision differs from the source run head")
    summary["contexts"] = verdict["contexts"]
    summary["required_contexts"] = required
    summary["workflow_run_id"] = run_id
    if require_workflow_identity:
        summary["run_attempt"] = run.get("run_attempt", 1)
        summary["pr_number"] = pr_number
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--event", choices=("pull_request", "push", "schedule", "workflow_dispatch", "release"), default="pull_request")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--source-run", type=int)
    parser.add_argument("--auto-previous", action="store_true")
    parser.add_argument("--workflow-head")
    parser.add_argument("--workflow-run", type=int)
    parser.add_argument("--pr-number", type=int)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--base-branch", default="dev")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selection = None
    try:
        if args.evidence and args.source_run is not None:
            raise ValueError("--evidence and --source-run are mutually exclusive")
        if args.auto_previous and (args.evidence or args.source_run is not None):
            raise ValueError("--auto-previous is mutually exclusive with explicit evidence")
        root = args.root.resolve()
        base = revision(root, args.base)
        previous = None
        if args.evidence:
            previous = read_json(args.evidence)
        elif args.source_run is not None:
            previous = evidence_from_run(root, args.repository, args.base_branch, base, args.source_run)
        elif args.auto_previous:
            if args.workflow_head is None or args.workflow_run is None or args.pr_number is None:
                raise ValueError("automatic history requires workflow head, current run, and PR number")
            if args.event != "pull_request":
                selection = {
                    "status": "FULL_REQUIRED",
                    "reason": "only pull_request events may select historical quality evidence",
                }
            else:
                selection = select_previous_quality_run(
                    args.repository,
                    args.pr_number,
                    args.workflow_run,
                    args.workflow_head,
                )
                if selection["selected_run_id"] is not None:
                    previous = evidence_from_run(
                        root,
                        args.repository,
                        args.base_branch,
                        selection["selected_head_sha"],
                        selection["selected_run_id"],
                        require_workflow_identity=True,
                        pr_number=args.pr_number,
                    )
        result = evaluate(
            root,
            base,
            args.head,
            previous,
            args.event,
            args.execute,
            workflow_head=args.workflow_head,
            workflow_run_id=args.workflow_run,
            pr_number=args.pr_number,
        )
        if selection is not None:
            result["history_selection"] = selection
    except EvidenceMissing as error:
        result = {
            "schema_version": 1,
            "decision": "RUN_FULL",
            "reason": str(error),
            "issues": [],
            "history_selection": selection,
        }
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        result = {"schema_version": 1, "decision": "INVALID", "issues": [str(error)]}
        emit_json(result, args.output)
        print(f"incremental CI: {error}", file=sys.stderr)
        return 1
    emit_json(result, args.output)
    return int(result["decision"] == "INVALID")


if __name__ == "__main__":
    raise SystemExit(main())
