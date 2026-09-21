#!/usr/bin/env python3
"""Run the full PR and nightly regressions required by NPU-P6."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {
        "path": str(path.resolve()),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def run_suite(suite: str, output: Path, timestamp: str) -> dict[str, object]:
    log = output / f"regress-{suite}.log"
    started = datetime.now().astimezone().isoformat()
    with log.open("w", encoding="utf-8") as stream:
        completed = subprocess.run(
            ["make", f"regress-{suite}"],
            cwd=ROOT,
            text=True,
            stdout=stream,
            stderr=subprocess.STDOUT,
            check=False,
            env={**os.environ, "BUILD_TIMESTAMP": timestamp, "CCACHE_DISABLE": "1"},
        )
    if completed.returncode != 0:
        raise RuntimeError(f"P6 {suite} regression failed: {log}")
    return {
        "suite": suite,
        "status": "PASS",
        "command": ["make", f"regress-{suite}"],
        "started_at": started,
        "log": identity(log),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--build-timestamp", default=datetime.now().astimezone().strftime("%Y-%m-%d-%H-%M")
    )
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    suites = [run_suite(suite, output, args.build_timestamp) for suite in ("pr", "nightly")]
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V018"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "implementation": {
            name: identity(ROOT / name)
            for name in ("scripts/run_npu_p6_regression.py", "scripts/regress.py")
        },
        "suites": suites,
        "summary": {"required_suites": 2, "passes": 2, "failures": 0, "skipped": 0},
        "verdict": "PASS",
    }
    report_path = output / "qualification-p6-regression.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 regressions: PASS ({report_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
