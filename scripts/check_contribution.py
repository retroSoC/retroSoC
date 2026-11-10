#!/usr/bin/env python3
"""Enforce contribution metadata, ownership records, and evidence-bound releases."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, git_output, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

TYPES = "feat|fix|docs|test|refactor|build|ci|perf|chore|revert"
SUBJECT_RE = re.compile(rf"^(?:{TYPES})(?:\([a-z0-9][a-z0-9_.-]*\))?: [^\s].*$")
TOPIC_RE = re.compile(rf"^(?:{TYPES})/[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(
    r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)
STAGES = {"behavioral", "synthesis", "netlist_simulation", "sta", "formal", "physical", "silicon"}
REVISION_RE = re.compile(r"^[0-9a-f]{40}$")


def valid_subject(subject: str) -> bool:
    return bool(SUBJECT_RE.fullmatch(subject)) or subject.startswith(("Merge ", "Revert "))


def validate_pull_request(base: str, head: str, title: str, subjects: list[str]) -> list[str]:
    issues = []
    if base not in {"dev", "main"}:
        issues.append("pull requests may target only dev or main")
    if base == "dev":
        if head in {"dev", "main"}:
            issues.append("ordinary contributions require a topic branch")
        elif not TOPIC_RE.fullmatch(head) and not head.startswith("dependabot/"):
            issues.append("topic branch must use <type>/<lowercase-short-topic>")
    elif base == "main" and head != "dev":
        issues.append("main accepts only the controlled dev release-integration branch")
    if not valid_subject(title):
        issues.append("pull request title must use type(scope): summary")
    if not subjects:
        issues.append("pull request has no commits in the selected range")
    for subject in subjects:
        if not valid_subject(subject):
            issues.append(f"invalid commit subject: {subject}")
    return issues


def codeowners(root: Path) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for line in (root / ".github/CODEOWNERS").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        result[fields[0]] = set(fields[1:])
    return result


def validate_ownership(root: Path) -> tuple[list[str], list[str]]:
    issues = []
    warnings = []
    document = read_json(root / "quality/ownership.json")
    if document.get("schema_version") != 1:
        issues.append("ownership schema_version must be 1")
    owners = codeowners(root)
    policy = document.get("review_policy", {})
    if policy.get("mode") not in {"sole_maintainer", "peer_review"}:
        issues.append("review_policy.mode must be sole_maintainer or peer_review")
    if policy.get("agent_approval_allowed") is not True:
        issues.append("review_policy must allow agent merge under the auto_merge policy")
    from scripts.pr_workflow import auto_merge_policy

    try:
        auto_merge_policy(root)
    except RuntimeError as error:
        issues.append(str(error))
    if policy.get("mode") == "sole_maintainer":
        if policy.get("self_approval_allowed") is not True:
            issues.append("sole_maintainer mode must allow maintainer self-approval")
        if policy.get("required_approving_review_count") != 0:
            issues.append("sole_maintainer mode requires zero mandatory peer approvals")
        if policy.get("require_code_owner_reviews") is not False:
            issues.append("sole_maintainer mode cannot require peer CODEOWNERS approval")
    for entry in document.get("entries", []):
        path = entry["path"]
        expected = set(entry["owners"])
        if owners.get(path) != expected:
            issues.append(f"CODEOWNERS mismatch for {path}: expected {sorted(expected)}")
        if not entry.get("backup_owners"):
            warnings.append(f"no backup owner registered for {path}")
        for backup in entry.get("backup_owners", []):
            if backup in expected:
                issues.append(f"backup owner duplicates primary owner for {path}: {backup}")
    return issues, warnings


def gh_runs(repository: str, revision: str) -> list[dict[str, Any]]:
    from scripts.engineering_metrics import gh_json

    document = gh_json(["api", f"repos/{repository}/actions/runs?head_sha={revision}&per_page=100"])
    return document.get("workflow_runs", [])


def gh_approval(repository: str, reference: str) -> dict[str, Any]:
    match = re.fullmatch(r"https://github\.com/([^/]+)/([^/]+)/pull/(\d+)", reference)
    if not match or f"{match.group(1)}/{match.group(2)}" != repository:
        raise ValueError("approval reference must name a pull request in the released repository")
    from scripts.engineering_metrics import gh_json

    return gh_json(
        [
            "pr",
            "view",
            match.group(3),
            "--repo",
            repository,
            "--json",
            "state,mergedAt,mergeCommit,reviewDecision,reviews,url",
        ]
    )


def validate_release(
    root: Path,
    tag: str,
    candidate_path: Path,
    main_ref: str,
    repository: str,
    run_lookup: Callable[[str, str], list[dict[str, Any]]] | None = None,
    approval_lookup: Callable[[str, str], dict[str, Any]] | None = None,
) -> tuple[list[str], list[dict[str, Any]]]:
    issues = []
    verified_runs = []
    if not SEMVER_RE.fullmatch(tag):
        issues.append("release tag must be an immutable vMAJOR.MINOR.PATCH SemVer tag")
    try:
        revision = git_output(root, "rev-list", "-n", "1", tag)
        main_revision = git_output(root, "rev-parse", main_ref)
    except subprocess.CalledProcessError as error:
        return [f"cannot resolve release revisions: {error}"], []
    if revision != main_revision:
        issues.append(f"release tag {revision} does not point to the approved {main_ref} head {main_revision}")
    candidate_path = candidate_path.resolve()
    try:
        relative_candidate = candidate_path.relative_to(root.resolve()).as_posix()
    except ValueError:
        return ["release candidate must be inside the repository"], []
    if not candidate_path.is_file():
        return [f"release candidate is missing: {relative_candidate}"], []
    if git_output(root, "ls-tree", "--name-only", tag, "--", relative_candidate) != relative_candidate:
        issues.append("release candidate must be tracked at the released tag")
    tagged_candidate = git_output(root, "show", f"{tag}:{relative_candidate}")
    if candidate_path.read_text(encoding="utf-8").strip() != tagged_candidate:
        issues.append("release candidate content must match the released tag")
    candidate = read_json(candidate_path)
    if not isinstance(candidate, dict):
        return ["release candidate must be an object"], []
    required = {
        "schema_version",
        "version",
        "release_branch",
        "dependency_lock_sha256",
        "approval",
        "required_stages",
        "checks",
        "accepted_gaps",
    }
    missing = required - set(candidate)
    if missing:
        issues.append(f"release candidate missing fields: {sorted(missing)}")
    unknown = set(candidate) - required - {"artifacts"}
    if unknown:
        issues.append(f"release candidate unknown fields: {sorted(unknown)}")
    if candidate.get("schema_version") != 1:
        issues.append("release candidate schema_version must be 1")
    if candidate.get("version") != tag:
        issues.append("release candidate version does not match the tag")
    release_branch = candidate.get("release_branch")
    if release_branch != "main":
        issues.append("release candidate release_branch must be main")
    if main_ref not in {release_branch, f"origin/{release_branch}"}:
        issues.append("release main_ref does not match the candidate release_branch")
    lock_digest = hashlib.sha256((root / "dependencies/dependencies.lock.json").read_bytes()).hexdigest()
    if candidate.get("dependency_lock_sha256") != lock_digest:
        issues.append("release candidate dependency lock digest is stale")

    approval = candidate.get("approval", {})
    approved_by = approval.get("approved_by", "")
    if not approved_by.startswith("@"):
        issues.append("release approval approved_by must be a GitHub handle")
    reference = approval.get("reference", "")
    if not reference.startswith("https://"):
        issues.append("release approval reference must be an HTTPS pull-request URL")
    lookup_approval = approval_lookup or gh_approval
    if approved_by.startswith("@") and reference.startswith("https://"):
        try:
            decision = lookup_approval(repository, reference)
            if decision.get("state") != "MERGED" or not decision.get("mergedAt"):
                issues.append("release approval pull request is not merged")
            if (decision.get("mergeCommit") or {}).get("oid") != revision:
                issues.append("release approval merge commit does not match the tag")
            policy = read_json(root / "quality/ownership.json").get("review_policy", {})
            if policy.get("mode") == "sole_maintainer":
                owners = {
                    owner
                    for entry in read_json(root / "quality/ownership.json")["entries"]
                    for owner in entry["owners"]
                }
                if approved_by not in owners:
                    issues.append(f"release approver {approved_by} is not a repository CODEOWNER")
                if decision.get("reviewDecision") not in {"", "APPROVED"}:
                    issues.append("sole-maintainer release PR must not have changes requested")
            else:
                if decision.get("reviewDecision") != "APPROVED":
                    issues.append("release approval pull request has no APPROVED review decision")
                reviewers = {
                    (review.get("author") or {}).get("login")
                    for review in decision.get("reviews", [])
                    if review.get("state") == "APPROVED"
                }
                if approved_by[1:] not in reviewers:
                    issues.append(f"release approver {approved_by} has no APPROVED review on the release PR")
        except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
            issues.append(f"cannot verify release approval: {error}")

    required_stages = candidate.get("required_stages", [])
    if not isinstance(required_stages, list) or "behavioral" not in required_stages:
        issues.append("release required_stages must include behavioral")
    if any(stage not in STAGES for stage in required_stages):
        issues.append("release required_stages contains an unknown stage")
    checks = candidate.get("checks", [])
    if not isinstance(checks, list) or not checks:
        issues.append("release requires at least one validation workflow")
        checks = []
    verified_stages = set()
    lookup_run = run_lookup or gh_runs
    try:
        available_runs = lookup_run(repository, revision)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        available_runs = []
        issues.append(f"cannot query release validation runs: {error}")
    for check in checks:
        name = check.get("name")
        stages = check.get("stages", [])
        if not name or not isinstance(name, str):
            issues.append("each release check requires a workflow name")
            continue
        if not isinstance(stages, list) or not stages or any(stage not in STAGES for stage in stages):
            issues.append(f"release check {name} has invalid stages")
            continue
        matches = [
            run
            for run in available_runs
            if run.get("name") == name
            and run.get("head_sha") == revision
            and run.get("status") == "completed"
            and run.get("conclusion") == "success"
        ]
        if not matches:
            issues.append(f"release workflow {name} has no successful run at {revision}")
            continue
        run = sorted(matches, key=lambda item: item.get("id", 0), reverse=True)[0]
        verified_stages.update(stages)
        verified_runs.append(
            {
                "id": run.get("id"),
                "name": name,
                "head_sha": revision,
                "html_url": run.get("html_url"),
                "event": run.get("event"),
                "stages": stages,
            }
        )
    for stage in required_stages:
        if stage not in verified_stages:
            issues.append(f"required release stage has no successful evidence: {stage}")

    for gap in candidate.get("accepted_gaps", []):
        if gap.get("stage") not in STAGES:
            issues.append("accepted gap contains an unknown stage")
        if gap.get("stage") in required_stages:
            issues.append(f"required stage cannot also be an accepted gap: {gap.get('stage')}")
        if not gap.get("reason") or not gap.get("approved_by"):
            issues.append("accepted gaps require a reason and approved_by")

    for artifact in candidate.get("artifacts", []):
        relative = Path(artifact.get("path", ""))
        if relative.is_absolute() or ".." in relative.parts:
            issues.append("release artifact path must be repository-relative")
            continue
        path = root / relative
        if artifact.get("required") and not path.is_file():
            issues.append(f"required release artifact is missing: {relative}")
            continue
        if path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != artifact.get("sha256"):
                issues.append(f"release artifact digest mismatch: {relative}")
    return issues, verified_runs


def emit(document: dict[str, Any], output: Path | None, summary: Path | None) -> None:
    document["output"] = str(output) if output else None
    if output:
        atomic_write(output, dump_json(document))
    else:
        sys.stdout.write(dump_json(document))
    if summary:
        lines = [
            f"## {document['kind']} check",
            "",
            f"Status: **{document['status']}**",
            "",
        ]
        lines.extend(f"- {issue}" for issue in document.get("issues", []))
        lines.extend(f"- WARNING: {warning}" for warning in document.get("warnings", []))
        with summary.open("a", encoding="utf-8") as output_file:
            output_file.write("\n".join(lines) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    pr = subparsers.add_parser("pr")
    pr.add_argument("--root", type=Path, default=ROOT)
    pr.add_argument("--base-ref", required=True)
    pr.add_argument("--head-ref", required=True)
    pr.add_argument("--title", required=True)
    pr.add_argument("--base")
    pr.add_argument("--head", default="HEAD")
    pr.add_argument("--subject", action="append")
    pr.add_argument("--output", type=Path)
    pr.add_argument("--step-summary", type=Path)
    ownership = subparsers.add_parser("ownership")
    ownership.add_argument("--root", type=Path, default=ROOT)
    ownership.add_argument("--output", type=Path)
    ownership.add_argument("--step-summary", type=Path)
    release = subparsers.add_parser("release")
    release.add_argument("--root", type=Path, default=ROOT)
    release.add_argument("--tag", required=True)
    release.add_argument("--candidate", type=Path, required=True)
    release.add_argument("--main-ref", default="origin/main")
    release.add_argument("--repository", required=True)
    release.add_argument("--output", type=Path)
    release.add_argument("--step-summary", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "pr":
            subjects = args.subject
            if subjects is None:
                if not args.base:
                    raise ValueError("--base is required when --subject is not supplied")
                subjects = git_output(args.root.resolve(), "log", "--format=%s", f"{args.base}...{args.head}").splitlines()
            issues = validate_pull_request(args.base_ref, args.head_ref, args.title, subjects)
            document = {"schema_version": 1, "kind": "contribution", "status": "failed" if issues else "passed", "issues": issues}
        elif args.command == "ownership":
            issues, warnings = validate_ownership(args.root.resolve())
            document = {"schema_version": 1, "kind": "ownership", "status": "failed" if issues else "passed", "issues": issues, "warnings": warnings}
        else:
            issues, verified_runs = validate_release(args.root.resolve(), args.tag, args.candidate, args.main_ref, args.repository)
            document = {"schema_version": 1, "kind": "release", "status": "failed" if issues else "passed", "issues": issues, "verified_runs": verified_runs}
        emit(document, args.output, args.step_summary)
        return int(bool(document["issues"]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"contribution check: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
