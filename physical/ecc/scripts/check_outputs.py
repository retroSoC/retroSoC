#!/usr/bin/env python3
"""Check that an ECC harden run produced complete padless-core evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


REQUIRED_STEPS = {
    "SYNTHESIS",
    "FLOORPLAN",
    "NETLIST_OPT",
    "PLACEMENT",
    "CTS",
    "LEGALIZATION",
    "ROUTING",
    "DRC",
    "FILLER",
    "RCX",
    "STA",
    "HARDEN",
}
STEP_ALIASES = {
    "FIXFANOUT": "NETLIST_OPT",
    "PLACE": "PLACEMENT",
    "ROUTE": "ROUTING",
}
ARTIFACT_GROUPS = {
    "gds": ("*.gds", "*.gds.gz"),
    "def": ("*.def", "*.def.gz"),
    "netlist": ("*.v", "*.v.gz"),
    "spef": ("*.spef", "*.spef.gz"),
    "sta_report": ("*sta*.rpt", "*STA*.rpt", "*timing*.rpt"),
    "drc_report": ("*drc*.rpt", "*DRC*.rpt", "*drc*.json", "*DRC*.json"),
}


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def collect_step_names(value: Any) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        for key, item in value.items():
            if key.lower() in {"step", "name", "type"} and isinstance(item, str):
                names.add(item.upper())
            names.update(collect_step_names(item))
    elif isinstance(value, list):
        for item in value:
            names.update(collect_step_names(item))
    return names


def canonical_steps(steps: set[str]) -> set[str]:
    return {STEP_ALIASES.get(step, step) for step in steps}


def find_artifacts(workspace: Path, patterns: tuple[str, ...]) -> list[Path]:
    found: set[Path] = set()
    for pattern in patterns:
        found.update(path for path in workspace.rglob(pattern) if path.is_file())
    return sorted(found)


def command_environment(project: Path) -> dict[str, str]:
    cache = project / ".fontconfig-cache"
    cache.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["XDG_CACHE_HOME"] = str(cache)
    return environment


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ecc", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--sdc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    workspace = project / "runs/default"
    errors: list[str] = []
    details: dict[str, object] = {"workspace": str(workspace)}

    flow_path = workspace / "home/flow.json"
    if not flow_path.is_file():
        errors.append(f"ECC flow state is missing: {flow_path}")
    else:
        try:
            flow = json.loads(flow_path.read_text(encoding="utf-8"))
            steps = canonical_steps(collect_step_names(flow))
            details["steps"] = sorted(steps)
            missing_steps = sorted(REQUIRED_STEPS - steps)
            if missing_steps:
                errors.append("ECC harden flow is missing step(s): " + ", ".join(missing_steps))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"cannot read ECC flow state: {error}")

    copied_sdc = workspace / "origin" / args.sdc.name
    if not copied_sdc.is_file():
        errors.append(f"ECC workspace did not retain the generated SDC: {copied_sdc}")
    elif digest(copied_sdc) != digest(args.sdc):
        errors.append("ECC workspace SDC does not match the generated multi-clock SDC")

    for label, patterns in ARTIFACT_GROUPS.items():
        artifacts = find_artifacts(workspace, patterns)
        details[f"{label}_artifacts"] = [str(path.relative_to(workspace)) for path in artifacts]
        if not artifacts:
            errors.append(f"ECC harden output is missing {label} evidence")

    try:
        status = subprocess.run(
            [str(args.ecc), "status", "--project", str(project), "--json"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=command_environment(project),
        )
        details["status"] = json.loads(status.stdout)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        errors.append(f"cannot obtain ECC status: {error}")

    result = {
        "schema_version": 1,
        "status": "passed" if not errors else "failed",
        "errors": errors,
        "details": details,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"ECC output verification passed: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
