#!/usr/bin/env python3
"""Validate the local LibreLane/IHP130 full-chip environment and configuration."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from librelane.flows import Flow  # noqa: E402
from rtl.mini.pin_map.generate_pin_map import IHP130_POWER_PAD_COUNTS  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402


EXPECTED_LIBRELANE_VERSION = "LibreLane v3.0.5"
EXPECTED_SIGNAL_PADS = 109


def command_output(command: list[str]) -> str:
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--pdk-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    errors: list[str] = []
    details: dict[str, object] = {}

    for tool in ("librelane", "klayout"):
        path = shutil.which(tool)
        details[f"{tool}_path"] = path
        if path is None:
            errors.append(f"required tool is missing: {tool}")

    if shutil.which("librelane") is not None:
        version = command_output(["librelane", "--version"]).splitlines()[0]
        details["librelane_version"] = version
        if version != EXPECTED_LIBRELANE_VERSION:
            errors.append(f"expected {EXPECTED_LIBRELANE_VERSION}, found {version or '<empty>'}")

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    expected_pdk_revision = lock["sources"]["pdk_ihp130"]["revision"]
    details["locked_pdk_revision"] = expected_pdk_revision

    pdk_checkout = args.pdk_root.resolve()
    if not (pdk_checkout / ".git").exists():
        errors.append(f"IHP PDK checkout is missing: {pdk_checkout}")
    else:
        revision = command_output(["git", "-C", str(pdk_checkout), "rev-parse", "HEAD"])
        details["pdk_revision"] = revision
        if revision != expected_pdk_revision:
            errors.append(f"expected IHP PDK {expected_pdk_revision}, found {revision}")

    required = (
        args.config,
        pdk_checkout / "ihp-sg13g2/libs.tech/librelane/config.tcl",
        pdk_checkout / "ihp-sg13g2/libs.tech/klayout/tech/drc/ihp-sg13g2.drc",
        pdk_checkout / "ihp-sg13g2/libs.tech/klayout/tech/scripts/sealring.py",
        pdk_checkout / "ihp-sg13g2/libs.ref/sg13g2_io/spice/sg13g2_io.spice",
    )
    for path in required:
        if not path.is_file():
            errors.append(f"required LibreLane/IHP file is missing: {path}")

    config: dict[str, object] = {}
    flow_name = ""
    if args.config.is_file():
        try:
            config = json.loads(args.config.read_text(encoding="utf-8"))
            meta = config.get("meta", {})
            if not isinstance(meta, dict) or not isinstance(meta.get("flow"), str):
                raise ValueError("config meta.flow must name a LibreLane flow")
            flow_name = meta["flow"]
        except (OSError, ValueError, json.JSONDecodeError) as error:
            errors.append(f"failed to read LibreLane configuration: {error}")

    if args.config.is_file() and not errors:
        try:
            flow_class = Flow.factory.get(flow_name)
            if flow_class is None:
                raise ValueError(f"unknown LibreLane flow: {flow_name}")
            flow = flow_class(
                str(args.config.resolve()),
                pdk="ihp-sg13g2",
                pdk_root=str(pdk_checkout),
                scl="sg13g2_stdcell",
                pad="sg13g2_io",
                design_dir=str(args.config.resolve().parent),
            )
            details["flow"] = flow_name
            details["config_design"] = flow.config["DESIGN_NAME"]
            details["drc_runset"] = str(flow.config["KLAYOUT_DRC_RUNSET"])
            details["lvs_setup"] = str(flow.config["NETGEN_SETUP"])
            details["pad_spice"] = [str(path) for path in flow.config["PAD_SPICE_MODELS"]]
        except Exception as error:  # LibreLane reports structured configuration exceptions.
            errors.append(f"LibreLane {flow_name or 'unknown'} configuration failed to load: {error}")

    if config:
        placed = [
            item
            for side in ("PAD_SOUTH", "PAD_EAST", "PAD_NORTH", "PAD_WEST")
            for item in config.get(side, [])
        ]
        details["placed_pad_count"] = len(placed)
        if flow_name == "Chip":
            expected = EXPECTED_SIGNAL_PADS + sum(IHP130_POWER_PAD_COUNTS.values())
            if len(placed) != expected or len(placed) != len(set(placed)):
                errors.append(
                    f"expected {expected} unique placed signal/power PADs, found {len(placed)}"
                )
        elif flow_name == "Classic" and placed:
            errors.append("core hardening configuration must not define pad-ring placement")

    result = {
        "schema_version": 1,
        "status": "passed" if not errors else "failed",
        "errors": errors,
        "details": details,
    }
    atomic_write(args.output, json.dumps(result, indent=2, sort_keys=True) + "\n")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"LibreLane doctor passed: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
