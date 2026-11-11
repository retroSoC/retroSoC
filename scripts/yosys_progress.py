#!/usr/bin/env python3
"""Summarize Yosys optimization progress without inferring a convergence cause."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, git_output, read_json  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

PASS_RE = re.compile(r"^\[(?P<seconds>\d+(?:\.\d+)?)\]\s+(?P<phase>\d+)\.(?P<iteration>\d+)\.\s+(?P<message>.+)$")
EXECUTING_RE = re.compile(r"Executing (?P<name>[A-Z_]+) pass")
REMOVED_RE = re.compile(r"Removed (?:a total of )?(?P<count>\d+) cells\.")


def analyze(
    log: Path,
    *,
    phase: int = 45,
    result: Path | None = None,
    summary: Path | None = None,
    manifest: Path | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    if result is not None and summary is not None:
        raise ValueError("use either --result or --summary, not both")
    if phase < 0:
        raise ValueError("phase must be non-negative")
    records = []
    removed = []
    phases = []
    last_phase = None
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        match = PASS_RE.match(line)
        if match is None:
            if last_phase == phase:
                removed_match = REMOVED_RE.search(line)
                if removed_match and int(removed_match["count"]) > 0:
                    removed.append(int(removed_match["count"]))
            continue
        current_phase = int(match["phase"])
        last_phase = current_phase
        phases.append(current_phase)
        if current_phase != phase:
            continue
        removed_match = REMOVED_RE.search(line)
        if removed_match and int(removed_match["count"]) > 0:
            removed.append(int(removed_match["count"]))
        executing = EXECUTING_RE.search(match["message"])
        records.append(
            (
                float(match["seconds"]),
                int(match["iteration"]),
                executing["name"] if executing else match["message"],
                bool(executing),
            )
        )
    if not records:
        raise ValueError(f"no Yosys progress records found for phase {phase}")

    pass_counts = Counter(record[2] for record in records if record[3])
    executing_pass_count = sum(record[3] for record in records)
    rerun_markers = sum(record[2].startswith("Rerunning OPT passes") for record in records)
    complete = any(current > phase for current in phases)
    issues = []
    if not complete:
        issues.append("no subsequent Yosys phase was recorded; convergence or non-convergence cannot be inferred from the log boundary alone")

    synthesis: dict[str, Any] = {"status": "not_reported"}
    if result is not None:
        data = read_json(result)
        synthesis = {
            key: data.get(key)
            for key in ("status", "exit_code", "started_at", "finished_at", "duration_seconds", "command", "log", "peak_rss_kib")
        }
    elif summary is not None:
        data = read_json(summary)
        matches = [item for item in data.get("results", []) if item.get("tool") == "yosys"]
        if matches:
            synthesis = matches[0]
        else:
            issues.append("the CI summary contains no Yosys result")
    if synthesis.get("status") == "passed" and not complete:
        issues.append("the result claims success but the requested phase has no subsequent phase")

    source: dict[str, Any] = {"revision": None, "dirty": None, "matches_worktree": None}
    if manifest is not None:
        data = read_json(manifest)
        repository = data.get("repository", {})
        source = {
            "revision": repository.get("commit"),
            "dirty": repository.get("dirty"),
            "matches_worktree": repository.get("commit") == git_output(root, "rev-parse", "HEAD") if root is not None else None,
            "manifest": str(manifest),
        }

    return {
        "schema_version": 1,
        "log": str(log),
        "phase": phase,
        "metrics": {
            "step_count": len(records),
            "executing_pass_count": executing_pass_count,
            "rerun_marker_count": rerun_markers,
            "first_step": records[0][1],
            "last_step": records[-1][1],
            "first_pass": records[0][2],
            "last_pass": records[-1][2],
            "pass_counts": dict(sorted(pass_counts.items())),
            "start_seconds": records[0][0],
            "last_seconds": records[-1][0],
            "elapsed_seconds": round(records[-1][0] - records[0][0], 6),
            "phase_complete": complete,
            "removed_cell_events": len(removed),
            "removed_cells_reported": sum(removed),
        },
        "synthesis": synthesis,
        "source": source,
        "issues": issues,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--phase", type=int, default=45)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        document = analyze(args.log, phase=args.phase, result=args.result, summary=args.summary, manifest=args.manifest, root=args.root)
        atomic_write(args.output, dump_json(document))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"yosys progress: {error}", file=sys.stderr)
        return 2
    metrics = document["metrics"]
    print(f"yosys progress: phase={document['phase']} steps={metrics['step_count']} complete={metrics['phase_complete']}: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
