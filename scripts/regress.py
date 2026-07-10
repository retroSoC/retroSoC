#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


PR_COMMANDS = (
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("firmware",)),
    ("configs/ci/mdd-rv32im-ihp130.mk", ("SIMU=VERILATOR", "firmware", "sim")),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("SIMU=VERILATOR", "sim")),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("SYNTH=YOSYS", "synth")),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("SIMU=IVERILOG", "SIM_FIRMWARE_NAME=retrosoc_asm", "SIM_SUCCESS_MARKER=Mem wr/rd test success", "RTL_SIM_TIMEOUT=5200000", "netsim")),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("STA=OPENSTA", "sta")),
)
NIGHTLY_COMMANDS = PR_COMMANDS + (
    ("configs/nightly/picorv32-rv32im-ihp130.mk", ("SIMU=VERILATOR", "firmware", "sim")),
    ("configs/nightly/picorv32-rv32im-ihp130.mk", ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
)
PR_PROFILES = (
    "configs/ci/hazard3-rv32im-ihp130.mk",
    "configs/ci/mdd-rv32im-ihp130.mk",
)
NIGHTLY_PROFILES = PR_PROFILES + ("configs/nightly/picorv32-rv32im-ihp130.mk",)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a supported retroSoC regression suite")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--suite", choices=("pr", "nightly"), required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    commands = PR_COMMANDS if args.suite == "pr" else NIGHTLY_COMMANDS
    profiles = PR_PROFILES if args.suite == "pr" else NIGHTLY_PROFILES
    for profile, values in commands:
        command = ["make", f"CONFIG={profile}", *values]
        print("+ " + " ".join(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, cwd=args.root, check=True)
    for profile in profiles:
        command = [
            "make",
            f"CONFIG={profile}",
            "check-warnings",
            "check-metrics",
        ]
        print("+ " + " ".join(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, cwd=args.root, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
