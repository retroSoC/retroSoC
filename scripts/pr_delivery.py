#!/usr/bin/env python3
"""Enable native merge-commit auto-merge early and reconcile cleanup safely."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, read_json  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402
from scripts.flow_control import file_digest, utc_now  # noqa: E402
from scripts.pr_workflow import (  # noqa: E402
    auto_merge_policy,
    checks_report,
    cleanup_merged_branch,
    merge_pr,
    native_auto_merge_enabled,
    required_check_contexts,
    view_pr,
    worktree_main_root,
)
from scripts.setup_helpers import atomic_write  # noqa: E402

REVISION = re.compile(r"^[0-9a-f]{40}$")


def delivery_preflight(root: Path, repository: str, number: int) -> dict[str, Any]:
    auto_merge_policy(root)
    issues = []
    metadata = gh_json(["api", f"repos/{repository}"])
    for capability in ("allow_auto_merge", "allow_merge_commit", "delete_branch_on_merge"):
        if metadata.get(capability) is not True:
            issues.append(f"repository capability is not enabled: {capability}")
    if metadata.get("permissions", {}).get("push") is not True:
        issues.append("GitHub credential does not have the repository push capability required for delivery")
    pull = view_pr(repository, number, root)
    if pull.get("state") != "OPEN":
        issues.append(f"PR state must be OPEN for delivery, found {pull.get('state')}")
    if pull.get("baseRefName") != "dev":
        issues.append("automatic delivery is supported only for PRs targeting dev")
    if pull.get("headRepository", {}).get("name") != "retroSoC" or pull.get("headRepositoryOwner", {}).get("login") != "retroSoC":
        issues.append("automatic delivery requires the canonical head repository")
    head_sha = pull.get("headRefOid", "")
    if not REVISION.fullmatch(head_sha):
        issues.append("PR has no full head revision")
    required = required_check_contexts(repository, pull.get("baseRefName", "dev"), root)
    return {
        "schema_version": 1,
        "repository": repository,
        "pr": number,
        "status": "READY" if not issues else "BLOCKED",
        "issues": issues,
        "head_sha": head_sha,
        "base": pull.get("baseRefName"),
        "branch": pull.get("headRefName"),
        "required_contexts": required,
        "repository_capabilities": {
            capability: metadata.get(capability)
            for capability in ("allow_auto_merge", "allow_merge_commit", "delete_branch_on_merge")
        },
        "push_capability": metadata.get("permissions", {}).get("push") is True,
        "checked_at": utc_now(),
    }


def enable_delivery(
    root: Path,
    repository: str,
    number: int,
    preflight: dict[str, Any],
    require_existing_auto_merge: bool = False,
) -> dict[str, Any]:
    if preflight["status"] != "READY":
        return preflight
    if native_auto_merge_enabled(repository, number, root):
        status = "AUTO_MERGE_ALREADY_ENABLED"
    else:
        if require_existing_auto_merge:
            raise RuntimeError("delivery resume requires native auto-merge to remain enabled")
        pull = view_pr(repository, number, root)
        if pull.get("headRefOid") != preflight["head_sha"]:
            raise RuntimeError("PR head changed between preflight and auto-merge")
        merge_pr(repository, number, root, pull)
        status = "AUTO_MERGE_ENABLED"
    return {
        **preflight,
        "status": status,
        "auto_merge": True,
        "merge_method": "MERGE",
        "cleanup": "PENDING",
        "enabled_at": utc_now(),
    }


def delivery_evidence(root: Path, pull: dict[str, Any]) -> dict[str, Any]:
    branch = pull.get("headRefName")
    head = pull.get("headRefOid")
    if not isinstance(branch, str) or not branch or not isinstance(head, str) or REVISION.fullmatch(head) is None:
        raise ValueError("delivery evidence requires a valid branch and HEAD revision")
    main_root = worktree_main_root(root).resolve()
    registry_relative = f"build/agent-worktrees/{branch.replace('/', '-')}-cleanup.json"
    registry_path = main_root / registry_relative
    result = {"evidence_manifest": None, "cleanup_registry": None, "evidence_status": "NOT_AVAILABLE"}
    if registry_path.is_symlink():
        raise ValueError("cleanup registry must not be a symlink")
    if not registry_path.is_file():
        return result
    registry = read_json(registry_path)
    actions = registry.get("actions")
    if registry.get("schema_version") != 1 or not isinstance(actions, list) or any(
        not isinstance(action, dict) for action in actions
    ):
        raise ValueError("cleanup registry has an invalid schema")
    matching = [action for action in actions if action.get("branch") == branch]
    if len(matching) != 1 or matching[0].get("status") != "CLEANED":
        raise ValueError("cleanup registry does not contain one cleaned action for the delivery branch")
    result["cleanup_registry"] = registry_relative
    preserved = matching[0].get("preserved_artifacts")
    if preserved is None:
        return result
    if not isinstance(preserved, str) or not preserved:
        raise ValueError("preserved artifact destination is invalid")
    manifest_path = Path(preserved) / "artifact-manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError("artifact manifest is missing or is not a regular file")
    artifact_root = main_root / "build/agent-artifacts"
    if artifact_root.is_symlink() or not manifest_path.resolve().is_relative_to(artifact_root.resolve()):
        raise ValueError("artifact manifest is outside the retained artifact root")
    manifest = read_json(manifest_path)
    identity = manifest.get("artifact_identity")
    if (
        manifest.get("schema_version") != 1
        or manifest.get("status") != "PRESERVED"
        or not isinstance(identity, dict)
        or identity.get("branch") != branch
        or identity.get("source_revision") != head
    ):
        raise ValueError("artifact identity does not match the delivery branch or HEAD")
    destination = manifest.get("destination")
    if not isinstance(destination, str) or Path(destination).resolve() != manifest_path.parent.resolve():
        raise ValueError("artifact manifest destination does not match its location")
    retained = manifest.get("retained_files")
    if not isinstance(retained, list):
        raise ValueError("artifact manifest has no retained-file inventory")
    for item in retained:
        if not isinstance(item, dict):
            raise ValueError("artifact retained-file entry is invalid")
        relative = item.get("path")
        if not isinstance(relative, str) or not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise ValueError("artifact retained-file path is unsafe")
        target = manifest_path.parent / relative
        if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(manifest_path.parent.resolve()):
            raise ValueError(f"retained evidence file is missing or unsafe: {relative}")
        if file_digest(target) != item.get("sha256"):
            raise ValueError(f"retained evidence digest mismatch: {relative}")
    result.update(evidence_manifest=manifest_path.relative_to(main_root).as_posix(), evidence_status="READY")
    return result


def resume_recovery(previous: dict[str, Any], preflight: dict[str, Any], reason: str | None) -> dict[str, Any]:
    if preflight.get("status") != "READY":
        raise ValueError("delivery resume requires a fresh READY preflight")
    if reason is None or not reason.strip():
        raise ValueError("delivery resume requires a non-empty recovery reason")
    if (
        previous.get("schema_version") != 1
        or previous.get("pr") != preflight.get("pr")
        or previous.get("repository") != preflight.get("repository")
    ):
        raise ValueError("delivery resume record identity mismatch")
    if previous.get("status") not in {"FAILED", "ATTENTION"}:
        raise ValueError("delivery resume requires an existing FAILED or ATTENTION record")
    if previous.get("auto_merge") is not True:
        raise ValueError("delivery resume requires an originally enabled native auto-merge")
    for field in ("branch", "base"):
        if previous.get(field) != preflight.get(field):
            raise ValueError(f"delivery resume {field} differs from the existing record")
    previous_head = previous.get("head_sha", "")
    current_head = preflight.get("head_sha", "")
    if REVISION.fullmatch(previous_head) is None or REVISION.fullmatch(current_head) is None:
        raise ValueError("delivery resume requires complete previous and current HEAD revisions")
    if previous_head == current_head:
        raise ValueError("delivery resume requires a changed HEAD; same-head retries belong to CI recovery")
    return {
        "from_status": previous["status"],
        "to_status": "READY",
        "previous_head_sha": previous_head,
        "previous_checked_at": previous.get("checked_at"),
        "previous_last_check_status": previous.get("last_check_status"),
        "reason": reason.strip(),
        "recovered_at": utc_now(),
    }


def merged_check_evidence(root: Path, repository: str, number: int, expected_head: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "schema_version": 1,
        "status": "NOT_AVAILABLE",
        "head_sha": expected_head,
        "observed_at": utc_now(),
        "issues": [],
    }
    try:
        if REVISION.fullmatch(expected_head) is None:
            raise ValueError("merged-head check evidence requires a complete HEAD revision")
        required = required_check_contexts(repository, "dev", root)
        if not required or any(not isinstance(item, str) or not item for item in required):
            raise ValueError("merged-head check evidence requires valid required contexts")
        report = checks_report(root, number, repository, required, allow_empty=True)
        if report.get("head_sha") != expected_head:
            raise ValueError("merged-head check report differs from the merged PR HEAD")
        if report.get("status") not in {"PASS", "PENDING", "FAIL"}:
            raise ValueError("merged-head check report has an invalid status")
        result.update(status=report["status"], required_contexts=required, report=report)
    except (KeyError, OSError, RuntimeError, TypeError, ValueError, subprocess.SubprocessError) as error:
        result["issues"].append(str(error))
    return result


def reconcile_delivery(
    root: Path,
    repository: str,
    number: int,
    cleanup: bool,
    delete_remote: bool,
) -> dict[str, Any]:
    auto_merge_policy(root)
    pull = view_pr(repository, number, root)
    final_checks = merged_check_evidence(root, repository, number, pull.get("headRefOid", ""))
    cleanup_warnings = cleanup_merged_branch(root, pull, delete_remote=delete_remote) if cleanup else ["cleanup was not requested"]
    if not cleanup:
        evidence = {"evidence_manifest": None, "cleanup_registry": None, "evidence_status": "NOT_REQUESTED"}
    elif cleanup_warnings:
        evidence = {"evidence_manifest": None, "cleanup_registry": None, "evidence_status": "NOT_AVAILABLE"}
    else:
        evidence = delivery_evidence(root, pull)
    warnings = list(cleanup_warnings)
    if final_checks["status"] != "PASS":
        warnings.append(f"merged-head final checks are {final_checks['status']}")
    return {
        **evidence,
        "schema_version": 1,
        "repository": repository,
        "pr": number,
        "status": "MERGED" if not warnings else "MERGED_WITH_WARNINGS",
        "head_sha": pull.get("headRefOid"),
        "branch": pull.get("headRefName"),
        "merge_commit": pull.get("mergeCommit", {}).get("oid"),
        "cleanup": "COMPLETE" if cleanup and not cleanup_warnings else "WARNING",
        "final_checks": final_checks,
        "warnings": warnings,
        "reconciled_at": utc_now(),
    }


def deliver(
    root: Path,
    repository: str,
    number: int,
    interval: int,
    watch: bool,
    cleanup: bool = True,
    delete_remote: bool = True,
    checkpoint: Any = None,
    delivery_dir: Path | None = None,
    coordinator_output: Path | None = None,
    resume: bool = False,
    resume_reason: str | None = None,
) -> dict[str, Any]:
    if interval <= 0:
        raise ValueError("interval must be positive")
    if watch and delivery_dir is None:
        raise ValueError("watched delivery requires a checkpoint directory")
    if resume and delivery_dir is None:
        raise ValueError("delivery resume requires an existing checkpoint directory")
    started = time.monotonic()

    def save(result: dict[str, Any]) -> None:
        if checkpoint is not None:
            checkpoint(result)

    preflight = delivery_preflight(root, repository, number)
    recovery = None
    if resume:
        from scripts.delivery_controller import record_path

        previous_path = record_path(delivery_dir, number)
        if previous_path.is_symlink() or not previous_path.is_file():
            raise ValueError("delivery resume requires a regular existing delivery record")
        recovery = resume_recovery(read_json(previous_path), preflight, resume_reason)
    document = enable_delivery(
        root,
        repository,
        number,
        preflight,
        require_existing_auto_merge=resume,
    )
    if recovery is not None:
        document["recovery"] = recovery
    save(document)
    if document["status"] == "BLOCKED" or not watch:
        return document

    from scripts.delivery_controller import coordinate, record_path

    path = record_path(delivery_dir, number)
    atomic_write(path, dump_json(document))
    summary_path = coordinator_output or delivery_dir / f"pr-{number}-controller.json"
    summary = coordinate(
        root,
        repository,
        [number],
        delivery_dir,
        interval,
        True,
        summary_path,
        cleanup=cleanup,
        delete_remote=delete_remote,
    )
    result = read_json(path)
    result["watch_seconds"] = round(time.monotonic() - started, 3)
    result["coordinator_summary"] = str(summary_path)
    atomic_write(path, dump_json(result))
    save(result)
    if summary["status"] == "FAILED":
        raise RuntimeError(
            f"PR #{number} checks failed at {result.get('last_check_head_sha') or result['head_sha']}; "
            "GitHub will not auto-merge"
        )
    if summary["status"] == "ATTENTION" and result.get("status") != "MERGED_WITH_WARNINGS":
        if result.get("status") == "ATTENTION" and any(
            "auto-merge is disabled" in str(warning) for warning in result.get("warnings", [])
        ):
            raise RuntimeError(f"PR #{number} native auto-merge was disabled; reconcile manually after review")
        raise RuntimeError(f"PR #{number} delivery requires attention: {result.get('status')}")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--watch", action="store_true", help="coordinate polling from durable checkpoints")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--reconcile-only", action="store_true")
    parser.add_argument("--resume", action="store_true", help="resume a diagnosed failed delivery at a changed HEAD")
    parser.add_argument("--resume-reason", help="evidence-backed reason for the explicit delivery resume")
    parser.add_argument("--no-cleanup", action="store_true")
    parser.add_argument("--no-remote-delete", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.preflight_only and args.reconcile_only:
        print("pr delivery: --preflight-only and --reconcile-only are mutually exclusive", file=sys.stderr)
        return 2
    if args.resume and (args.preflight_only or args.reconcile_only):
        print("pr delivery: --resume cannot be combined with --preflight-only or --reconcile-only", file=sys.stderr)
        return 2
    if args.resume_reason is not None and not args.resume:
        print("pr delivery: --resume-reason requires --resume", file=sys.stderr)
        return 2
    if args.resume and (args.resume_reason is None or not args.resume_reason.strip()):
        print("pr delivery: --resume requires a non-empty --resume-reason", file=sys.stderr)
        return 2
    try:
        root = args.root.resolve()
        output = args.output or worktree_main_root(root) / "build/engineering" / f"pr-{args.pr}-delivery.json"
        if args.reconcile_only:
            result = reconcile_delivery(
                root,
                args.repository,
                args.pr,
                cleanup=not args.no_cleanup,
                delete_remote=not args.no_remote_delete,
            )
        else:
            if args.preflight_only:
                result = delivery_preflight(root, args.repository, args.pr)
            else:
                from scripts.delivery_controller import record_path

                delivery_output = record_path(output.parent, args.pr)
                result = deliver(
                    root,
                    args.repository,
                    args.pr,
                    args.interval,
                    args.watch,
                    cleanup=not args.no_cleanup,
                    delete_remote=not args.no_remote_delete,
                    checkpoint=lambda result: atomic_write(delivery_output, dump_json(result)),
                    delivery_dir=delivery_output.parent,
                    coordinator_output=output.parent / f"pr-{args.pr}-controller.json",
                    resume=args.resume,
                    resume_reason=args.resume_reason,
                )
        atomic_write(output, dump_json(result))
        print(dump_json(result), end="")
        return int(result["status"] in {"BLOCKED", "FAILED"})
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"pr delivery: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
