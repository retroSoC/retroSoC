#!/usr/bin/env python3
"""Enable native merge-commit auto-merge early and reconcile cleanup safely."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json  # noqa: E402
from scripts.engineering_metrics import gh_json  # noqa: E402
from scripts.flow_control import utc_now  # noqa: E402
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


def enable_delivery(root: Path, repository: str, number: int, preflight: dict[str, Any]) -> dict[str, Any]:
    if preflight["status"] != "READY":
        return preflight
    if native_auto_merge_enabled(repository, number, root):
        status = "AUTO_MERGE_ALREADY_ENABLED"
    else:
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


def reconcile_delivery(
    root: Path,
    repository: str,
    number: int,
    cleanup: bool,
    delete_remote: bool,
) -> dict[str, Any]:
    auto_merge_policy(root)
    pull = view_pr(repository, number, root)
    warnings = cleanup_merged_branch(root, pull, delete_remote=delete_remote) if cleanup else ["cleanup was not requested"]
    return {
        "schema_version": 1,
        "repository": repository,
        "pr": number,
        "status": "MERGED" if not warnings else "MERGED_WITH_WARNINGS",
        "head_sha": pull.get("headRefOid"),
        "branch": pull.get("headRefName"),
        "merge_commit": pull.get("mergeCommit", {}).get("oid"),
        "cleanup": "COMPLETE" if cleanup and not warnings else "WARNING",
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
) -> dict[str, Any]:
    if interval <= 0:
        raise ValueError("interval must be positive")
    started = time.monotonic()
    document = enable_delivery(root, repository, number, delivery_preflight(root, repository, number))
    if document["status"] == "BLOCKED" or not watch:
        return document
    previous_output = ""
    while True:
        pull = view_pr(repository, number, root)
        if pull.get("state") == "MERGED":
            result = reconcile_delivery(root, repository, number, cleanup, delete_remote)
            result.update(
                head_sha=pull.get("headRefOid") or document["head_sha"],
                required_contexts=document["required_contexts"],
                auto_merge=True,
                watch_seconds=round(time.monotonic() - started, 3),
            )
            return result
        if pull.get("state") != "OPEN":
            raise RuntimeError(f"PR #{number} is {pull.get('state')}; native auto-merge cannot complete")
        if not native_auto_merge_enabled(repository, number, root):
            raise RuntimeError(f"PR #{number} native auto-merge was disabled; reconcile manually after review")
        report = checks_report(
            root,
            number,
            repository,
            document["required_contexts"],
            allow_empty=True,
        )
        output = json.dumps(report, sort_keys=True)
        if output != previous_output:
            print(output, flush=True)
            previous_output = output
        if report["status"] == "FAIL":
            raise RuntimeError(f"PR #{number} checks failed at {report['head_sha']}; GitHub will not auto-merge")
        time.sleep(interval)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--watch", action="store_true", help="retain bounded polling for immediate reconciliation")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--reconcile-only", action="store_true")
    parser.add_argument("--no-cleanup", action="store_true")
    parser.add_argument("--no-remote-delete", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.preflight_only and args.reconcile_only:
        print("pr delivery: --preflight-only and --reconcile-only are mutually exclusive", file=sys.stderr)
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
                result = deliver(
                    root,
                    args.repository,
                    args.pr,
                    args.interval,
                    args.watch,
                    cleanup=not args.no_cleanup,
                    delete_remote=not args.no_remote_delete,
                )
        atomic_write(output, dump_json(result))
        print(dump_json(result), end="")
        return int(result["status"] in {"BLOCKED", "FAILED"})
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"pr delivery: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
