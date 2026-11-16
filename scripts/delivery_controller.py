#!/usr/bin/env python3
"""Coordinate existing native auto-merge deliveries with durable recovery state."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.agent_control import dump_json, read_json  # noqa: E402
from scripts.flow_control import utc_now  # noqa: E402
from scripts.pr_delivery import REVISION, reconcile_delivery  # noqa: E402
from scripts.pr_workflow import (  # noqa: E402
    checks_report,
    native_auto_merge_enabled,
    view_pr,
    worktree_main_root,
)
from scripts.setup_helpers import atomic_write  # noqa: E402

TERMINAL_FAILURES = {"FAILED", "ATTENTION", "CLOSED_NOT_MERGED"}


def record_path(directory: Path, number: int) -> Path:
    return directory / f"pr-{number}-delivery.json"


def reconcile_record(
    root: Path,
    repository: str,
    number: int,
    delivery_dir: Path,
) -> tuple[dict[str, Any], str]:
    path = record_path(delivery_dir, number)
    record = read_json(path)
    if record.get("schema_version") != 1 or record.get("pr") != number:
        raise ValueError(f"delivery record identity mismatch for PR {number}")
    if record.get("repository") != repository:
        raise ValueError(f"delivery record repository mismatch for PR {number}")
    if record.get("auto_merge") is not True:
        raise ValueError("delivery coordinator accepts only records with auto_merge=true")
    if record.get("status") == "MERGED" and record.get("cleanup") == "COMPLETE" and not record.get("warnings"):
        return record, "ALREADY_RECONCILED"

    pull = view_pr(repository, number, root)
    if pull.get("headRefName") != record.get("branch"):
        raise ValueError(f"delivery branch differs for PR {number}")
    if pull.get("state") == "MERGED":
        reconciled = reconcile_delivery(root, repository, number, cleanup=True, delete_remote=True)
        result = {
            **record,
            **reconciled,
            "controller_reconciliations": int(record.get("controller_reconciliations", 0)) + 1,
            "controller_reconciled_at": utc_now(),
        }
        action = "CLEANUP_WARNING" if result.get("warnings") else "RECONCILED"
    elif pull.get("state") != "OPEN":
        result = {**record, "status": "CLOSED_NOT_MERGED", "checked_at": utc_now(), "warnings": ["PR closed without merge"]}
        action = "CLOSED_NOT_MERGED"
    else:
        head = pull.get("headRefOid", "")
        if REVISION.fullmatch(head) is None or head != record.get("head_sha"):
            raise ValueError(f"PR {number} head differs from its delivery record")
        if not native_auto_merge_enabled(repository, number, root):
            result = {
                **record,
                "status": "ATTENTION",
                "checked_at": utc_now(),
                "warnings": ["native auto-merge is disabled externally; manual review is required"],
            }
            action = "AUTO_MERGE_DISABLED"
        else:
            required = record.get("required_contexts")
            if not isinstance(required, list) or not required or any(not isinstance(item, str) or not item for item in required):
                raise ValueError(f"PR {number} delivery record has no valid required contexts")
            report = checks_report(root, number, repository, required, allow_empty=True)
            report_head = report.get("head_sha")
            if report_head is not None and report_head != head:
                raise ValueError(f"PR {number} check report is stale")
            status = report.get("status")
            result = {
                **record,
                "status": status if status in {"FAIL", "PENDING"} else "WAITING_FOR_NATIVE_MERGE",
                "checked_at": utc_now(),
                "last_check_status": status,
                "last_check_head_sha": head,
            }
            if status == "FAIL":
                result["status"] = "FAILED"
                result["warnings"] = ["required or observed checks failed; no merge or cleanup was attempted"]
                action = "CHECKS_FAILED"
            elif status == "PENDING":
                action = "MONITORING"
            else:
                action = "WAITING_FOR_NATIVE_MERGE"
    atomic_write(path, dump_json(result))
    return result, action


def coordinate_once(
    root: Path,
    repository: str,
    numbers: list[int],
    delivery_dir: Path,
) -> dict[str, Any]:
    records = []
    for number in numbers:
        path = record_path(delivery_dir, number)
        try:
            record, action = reconcile_record(root, repository, number, delivery_dir)
            issue = None
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            record = read_json(path)
            issue = str(error)
            record = {
                **record,
                "status": "ATTENTION",
                "checked_at": utc_now(),
                "controller_issues": [issue],
            }
            atomic_write(path, dump_json(record))
            action = "ERROR"
        records.append({"pr": number, "status": record.get("status"), "action": action, "issue": issue})
    status = "COMPLETE"
    if any(record["status"] in TERMINAL_FAILURES for record in records):
        status = "ATTENTION" if any(record["status"] == "ATTENTION" for record in records) else "FAILED"
    elif any(record["status"] == "MERGED_WITH_WARNINGS" for record in records):
        status = "ATTENTION"
    elif any(record["status"] in {"PENDING", "WAITING_FOR_NATIVE_MERGE", "AUTO_MERGE_ENABLED"} for record in records):
        status = "PENDING"
    return {
        "schema_version": 1,
        "repository": repository,
        "created_at": utc_now(),
        "status": status,
        "record_count": len(records),
        "records": records,
    }


def coordinate(
    root: Path,
    repository: str,
    numbers: list[int],
    delivery_dir: Path,
    interval: int,
    watch: bool,
    output: Path,
) -> dict[str, Any]:
    if interval <= 0:
        raise ValueError("coordination interval must be positive")
    if not numbers or len(set(numbers)) != len(numbers) or any(number <= 0 for number in numbers):
        raise ValueError("coordinated PR numbers must be unique positive integers")
    started = time.monotonic()
    while True:
        result = coordinate_once(root, repository, numbers, delivery_dir)
        result["watch_seconds"] = round(time.monotonic() - started, 3)
        atomic_write(output, dump_json(result))
        if not watch or result["status"] != "PENDING":
            return result
        time.sleep(interval)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--repository", default="retroSoC/retroSoC")
    parser.add_argument("--delivery-dir", type=Path)
    parser.add_argument("--pr", type=int, action="append", required=True)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = args.root.resolve()
        main_root = worktree_main_root(root)
        delivery_dir = (args.delivery_dir or main_root / "build/engineering").resolve()
        output = (args.output or main_root / "build/engineering/delivery-controller.json").resolve()
        result = coordinate(
            root,
            args.repository,
            args.pr,
            delivery_dir,
            args.interval,
            args.watch,
            output,
        )
        print(dump_json(result), end="")
        return int(result["status"] in {"ATTENTION", "FAILED"})
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"delivery coordinator: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
