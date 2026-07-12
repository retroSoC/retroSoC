#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.check_c_warnings import self_owned_warnings  # noqa: E402


PR_COMMANDS = (
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("firmware",)),
    ("configs/ci/hazard3-rv32im-ihp130-shell.mk", ("firmware",)),
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


def run_command(command: list[str], root: Path, capture_output: bool) -> str:
    if not capture_output:
        subprocess.run(command, cwd=root, check=True)
        return ""

    result = subprocess.run(
        command,
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.stdout.write(result.stdout)
    result.check_returncode()
    return result.stdout


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
            output = run_command(command, args.root, "firmware" in values)
            warnings = self_owned_warnings(args.root, output)
            if warnings:
                print("self-owned C compiler warnings:", flush=True)
                print("\n".join(warnings), flush=True)
                return 1
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
