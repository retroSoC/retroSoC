#!/usr/bin/env python3
"""Assemble the bounded NPU-P6 formal closure report."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = ("npu_dma", "npu_context", "npu_control")


def identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def task(target_dir: Path, name: str) -> dict[str, object]:
    status_path = target_dir / name / "status"
    result_path = target_dir / f"result-{name}.json"
    config_path = target_dir / f"{name}.sby"
    if status_path.read_text(encoding="utf-8").split()[0] != "PASS":
        raise ValueError(f"formal task failed: {status_path}")
    result = json.loads(result_path.read_text(encoding="utf-8"))
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        raise ValueError(f"formal structured result failed: {result_path}")
    config = config_path.read_text(encoding="utf-8")
    depth_match = re.search(r"(?m)^depth\s+(\d+)$", config)
    mode_match = re.search(r"(?m)^mode\s+(\w+)$", config)
    if depth_match is None or mode_match is None:
        raise ValueError(f"formal task lacks mode/depth: {config_path}")
    return {
        "mode": mode_match.group(1),
        "depth": int(depth_match.group(1)),
        "status": "PASS",
        "result": identity(result_path),
        "log": identity(target_dir / f"{name}.log"),
        "config": identity(config_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--formal-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    records = {}
    for target in TARGETS:
        target_dir = args.formal_dir / target
        records[target] = {
            "prove": task(target_dir, "prove"),
            "cover": task(target_dir, "cover"),
        }
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V015"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "scope": {
            "npu_dma": "AXI accepted-transfer conservation and bounded pause/flush safety",
            "npu_context": "two-context ownership, backpressure and exactly-once 64-beat drain",
            "npu_control": "launch/result/snapshot mailbox and lifecycle reconciliation",
        },
        "assumptions": {
            "liveness": "no unbounded liveness claim",
            "environment": "bounded responder stalls and explicitly modeled mailbox consumers",
        },
        "implementation": {
            name: identity(ROOT / name)
            for name in (
                "scripts/npu_p6_formal_report.py",
                "rtl/mini/formal/generate_formal_filelist.py",
                "rtl/mini/formal/npu_context_formal.sv",
                "rtl/mini/formal/npu_context_formal_props.sv",
                "rtl/mini/formal/npu_control_formal.sv",
                "rtl/mini/formal/npu_control_formal_props.sv",
                "rtl/mini/mk/formal.mk",
            )
        },
        "targets": records,
        "summary": {"required_tasks": 6, "passes": 6, "failures": 0, "skipped": 0},
        "verdict": "PASS",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 formal closure: PASS ({args.output})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
