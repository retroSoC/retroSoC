#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.check_c_warnings import self_owned_warnings  # noqa: E402


PR_COMMANDS = (
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("firmware",)),
    ("configs/ci/hazard3-rv32im-ihp130-shell.mk", ("firmware",)),
    ("configs/ci/hazard3-rv32im-ihp130-ip-mdd-shell.mk", ("firmware",)),
    (
        "configs/ci/hazard3-rv32im-ihp130-ip-mdd.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "firmware", "sim"),
    ),
    (
        "configs/ci/mdd-rv32im-ihp130.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "firmware", "sim"),
    ),
    (
        "configs/ci/hazard3-rv32im-ihp130.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "firmware", "sim"),
    ),
    (
        "configs/ci/hazard3-rv32im-ihp130.mk",
        ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm"),
    ),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("SYNTH=YOSYS", "synth")),
    (
        "configs/ci/hazard3-rv32im-ihp130.mk",
        (
            "SIMU=IVERILOG",
            "SIM_FIRMWARE_NAME=retrosoc_asm",
            "SIM_SUCCESS_MARKER=Mem wr/rd test success",
            "RTL_SIM_TIMEOUT=5200000",
            "netsim",
        ),
    ),
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("STA=OPENSTA", "sta")),
)
SMOKE_COMMANDS = (
    ("configs/ci/hazard3-rv32im-ihp130.mk", ("firmware",)),
    (
        "configs/ci/hazard3-rv32im-ihp130.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "comp"),
    ),
    (
        "configs/ci/hazard3-rv32im-ihp130.mk",
        ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm"),
    ),
)
NIGHTLY_COMMANDS = PR_COMMANDS + (
    (
        "configs/nightly/picorv32-rv32im-ihp130.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "firmware", "sim"),
    ),
    (
        "configs/nightly/picorv32-rv32im-ihp130.mk",
        ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm"),
    ),
)
PR_PROFILES = (
    "configs/ci/hazard3-rv32im-ihp130.mk",
    "configs/ci/hazard3-rv32im-ihp130-ip-mdd.mk",
    "configs/ci/mdd-rv32im-ihp130.mk",
)
SMOKE_PROFILES: tuple[str, ...] = ()
NIGHTLY_PROFILES = PR_PROFILES + ("configs/nightly/picorv32-rv32im-ihp130.mk",)

PDK_PR_PROFILES = {
    "GF180": "configs/ci/hazard3-rv32im-gf180.mk",
    "IHP130": "configs/ci/hazard3-rv32im-ihp130.mk",
    "SKY130": "configs/ci/hazard3-rv32im-sky130.mk",
}


def pdk_pr_commands(profile: str) -> tuple[tuple[str, tuple[str, ...]], ...]:
    return (
        (profile, ("firmware",)),
        (profile, ("SIMU=VERILATOR", "HAVE_SVA=YES", "firmware", "sim")),
        (profile, ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
        (profile, ("SYNTH=YOSYS", "synth")),
        (profile, ("STA=OPENSTA", "sta")),
        (
            profile,
            (
                "SIMU=IVERILOG",
                "SIM_FIRMWARE_NAME=retrosoc_asm",
                "SIM_SUCCESS_MARKER=Mem wr/rd test success",
                "RTL_SIM_TIMEOUT=5200000",
                "netsim",
            ),
        ),
    )


def select_regression(
    suite: str, pdk: str | None
) -> tuple[tuple[tuple[str, tuple[str, ...]], ...], tuple[str, ...]]:
    if suite == "smoke":
        if pdk is not None and pdk != "IHP130":
            raise ValueError("smoke regression supports only --pdk IHP130")
        return SMOKE_COMMANDS, SMOKE_PROFILES
    if pdk:
        if suite == "nightly":
            if pdk != "IHP130":
                raise ValueError("nightly regression supports only --pdk IHP130")
            return NIGHTLY_COMMANDS, NIGHTLY_PROFILES
        if pdk == "IHP130":
            return PR_COMMANDS, PR_PROFILES
        profile = PDK_PR_PROFILES[pdk]
        return pdk_pr_commands(profile), (profile,)
    if suite == "pr":
        return PR_COMMANDS, PR_PROFILES
    return NIGHTLY_COMMANDS, NIGHTLY_PROFILES


def regression_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment.setdefault(
        "BUILD_TIMESTAMP", datetime.now().astimezone().strftime("%Y-%m-%d-%H-%M")
    )
    return environment


def run_command(
    command: list[str], root: Path, capture_output: bool, environment: dict[str, str]
) -> str:
    if not capture_output:
        subprocess.run(command, cwd=root, env=environment, check=True)
        return ""

    result = subprocess.run(
        command,
        cwd=root,
        env=environment,
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
    parser.add_argument("--suite", choices=("smoke", "pr", "nightly"), required=True)
    parser.add_argument("--pdk", choices=tuple(PDK_PR_PROFILES), help="run one PDK matrix")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        commands, profiles = select_regression(args.suite, args.pdk)
    except ValueError as error:
        parser.error(str(error))
    environment = regression_environment()
    for profile, values in commands:
        command = ["make", f"CONFIG={profile}", *values]
        print("+ " + " ".join(command), flush=True)
        if not args.dry_run:
            output = run_command(command, args.root, "firmware" in values, environment)
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
            subprocess.run(command, cwd=args.root, env=environment, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
