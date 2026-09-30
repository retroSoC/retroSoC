#!/usr/bin/env python3
"""Fail-closed CRYPTO-P2 synthesis, netlist, STA and physical evidence report."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE_REVISION = "92830d963da2f1e39bb219c0d377bc4889c07755"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def manifest(root: Path) -> dict:
    path = root / "meta/manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def clean_revision() -> tuple[bool, str]:
    status = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    return not status, head


def artifact(path: Path, expected_status: str | None = None) -> dict:
    if not path.exists():
        return {"status": "NOT_RUN", "path": str(path)}
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        return {"status": "INVALID", "path": str(path), "error": str(error)}
    value.setdefault("path", str(path))
    if expected_status is not None and value.get("status") != expected_status:
        value["status_check"] = "failed"
    return value


def report(args: argparse.Namespace) -> int:
    variant = args.variant_root.resolve()
    p1 = args.p1_root.resolve()
    p0 = args.p0_root.resolve()
    is_clean, head = clean_revision()
    candidate_manifest = manifest(variant)
    p1_report = artifact(p1 / "crypto/p1/p1-report.json")
    synth = artifact(p1 / "crypto/p1/candidate-synthesis.json")
    netlist = artifact(args.netlist_root.resolve() / "sim/iverilog/netl/result-sim-check.json")
    sta = artifact(args.sta_root.resolve() / "sta/opensta/result-sta.json")
    physical = artifact(args.physical_root.resolve() / "crypto/p2/physical.json")
    metrics = artifact(variant / "meta/metrics.json")
    warnings = artifact(variant / "meta/warnings.json")

    checks = {
        "clean_candidate": is_clean,
        "candidate_manifest": candidate_manifest.get("profile") == "ihp130",
        "candidate_revision": bool(head) and head != BASELINE_REVISION,
        "p0_report": artifact(p0 / "crypto/p0/p0-report.json").get("status") == "passed",
        "p1_focused": p1_report.get("focused_gates_status") == "passed",
        "block_synthesis": synth.get("status") == "passed",
        "whole_soc_netlist": netlist.get("status") == "passed",
        "sta": sta.get("status") == "passed",
        "physical": physical.get("status") == "passed",
        "metrics": metrics.get("status") == "passed",
        "warnings": warnings.get("status") in ("passed", "observed"),
    }
    required = ("clean_candidate", "candidate_manifest", "candidate_revision", "p0_report",
                "p1_focused", "block_synthesis", "whole_soc_netlist", "sta", "physical")
    passed = all(checks[name] for name in required)
    result = {
        "schema_version": 1,
        "feature": "crypto",
        "phase": "CRYPTO-P2",
        "status": "passed" if passed else "incomplete",
        "verdict": "P2_ACCEPTED" if passed else "NOT_RUN_OR_INCOMPLETE",
        "baseline_revision": BASELINE_REVISION,
        "candidate_revision": head,
        "candidate_dirty": not is_clean,
        "profile": candidate_manifest.get("profile", "NOT_RUN"),
        "configuration": candidate_manifest.get("configuration", {}),
        "checks": checks,
        "artifacts": {
            "p0_report": str(p0 / "crypto/p0/p0-report.json"),
            "p1_report": str(p1 / "crypto/p1/p1-report.json"),
            "synthesis": synth,
            "netlist": netlist,
            "sta": sta,
            "physical": physical,
            "metrics": metrics,
            "warnings": warnings,
        },
        "gaps": [name for name, value in checks.items() if not value],
        "non_goals": ["Pytest under maintainer constraint", "CRYPTO-P3 commercial variants",
                       "DPA/FIA/physical security signoff"],
    }
    dump(variant / "crypto/p2/p2-report.json", result)
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("report",))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--p0-root", type=Path, required=True)
    parser.add_argument("--p1-root", type=Path, required=True)
    parser.add_argument("--netlist-root", type=Path)
    parser.add_argument("--sta-root", type=Path)
    parser.add_argument("--physical-root", type=Path)
    args = parser.parse_args()
    args.netlist_root = args.netlist_root or args.variant_root
    args.sta_root = args.sta_root or args.variant_root
    args.physical_root = args.physical_root or args.variant_root
    if args.command == "report":
        return report(args)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
