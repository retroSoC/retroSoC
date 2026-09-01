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


CI_SMOKE_APP_VALUE = "APP=ci_smoke"
CI_SMOKE_VERILATOR_VALUES = (
    "VERILATOR_SIM_ARGS=--fast-flash",
    "SIMU=VERILATOR",
    "HAVE_SVA=YES",
    "firmware",
    "sim",
)
CI_SMOKE_SIM_VALUES = (
    CI_SMOKE_APP_VALUE,
    "LINK_TYPE=ld2_all_sram",
    "SOC_SIM_TIME=360",
    *CI_SMOKE_VERILATOR_VALUES,
)
CI_SMOKE_SDRAM_SIM_VALUES = (
    CI_SMOKE_APP_VALUE,
    "LINK_TYPE=ld2_sdram",
    "SOC_SIM_TIME=600",
    *CI_SMOKE_VERILATOR_VALUES,
)
RTL_LINT_VALUES = ("SIMU=VERILATOR", "HAVE_SVA=YES", "rtl-lint")
RTL_LINT_OBSERVATION_VALUES = (
    "SIMU=VERILATOR",
    "HAVE_SVA=YES",
    "check-rtl-lint",
)
OBSERVATION_TARGETS = ("check-warnings", "check-metrics")
SYNTHESIS_DEPENDENT_TARGETS = frozenset(("synth", "sta", "netsim", "netsim-boot", "metrics"))


PR_COMMANDS = (
    ("configs/ci/ihp130.mk", RTL_LINT_VALUES),
    ("configs/ci/ihp130.mk", (CI_SMOKE_APP_VALUE, "firmware")),
    ("configs/ci/ihp130-shell.mk", ("firmware",)),
    (
        "configs/ci/ihp130.mk",
        CI_SMOKE_SIM_VALUES,
    ),
    ("configs/ci/ihp130-debug.mk", ("SIMU=VERILATOR", "debug-sim")),
    ("configs/ci/ihp130.mk", ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
    ("configs/ci/ihp130.mk", ("SYNTH=YOSYS", "synth")),
    (
        "configs/ci/ihp130.mk",
        (
            "SIMU=IVERILOG",
            "SIM_FIRMWARE_NAME=retrosoc_asm",
            "RTL_SIM_TIMEOUT=5200000",
            "netsim",
        ),
    ),
    ("configs/ci/ihp130.mk", ("STA=OPENSTA", "sta")),
)
RTL_COMMANDS = PR_COMMANDS[:6]
SMOKE_COMMANDS = (
    ("configs/ci/ihp130.mk", RTL_LINT_VALUES),
    ("configs/ci/ihp130.mk", (CI_SMOKE_APP_VALUE, "firmware")),
    (
        "configs/ci/ihp130.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "comp"),
    ),
    (
        "configs/ci/ihp130.mk",
        ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm"),
    ),
)
NIGHTLY_EXTRA_COMMANDS = (
    (
        "configs/benchmark/ihp130-hazard3-coremark.mk",
        ("SIMU=VERILATOR", "HAVE_SVA=YES", "coremark-report"),
    ),
    ("configs/ci/ihp130.mk", ("SYNTH=YOSYS", "SYNTH_RECIPE=area", "synth")),
    ("configs/ci/ihp130.mk", ("STA=OPENSTA", "SYNTH_RECIPE=area", "sta")),
    ("configs/ci/ihp130.mk", ("SYNTH_RECIPE=area", "metrics")),
    ("configs/ci/ihp130.mk", ("SYNTH=YOSYS", "SYNTH_RECIPE=speed", "synth")),
    ("configs/ci/ihp130.mk", ("STA=OPENSTA", "SYNTH_RECIPE=speed", "sta")),
    ("configs/ci/ihp130.mk", ("SYNTH_RECIPE=speed", "metrics")),
)
NIGHTLY_COMMANDS = (
    *PR_COMMANDS,
    *NIGHTLY_EXTRA_COMMANDS,
)
PR_PROFILES = ("configs/ci/ihp130.mk",)
SMOKE_PROFILES: tuple[str, ...] = ()
NIGHTLY_PROFILES = PR_PROFILES

PDK_PR_PROFILES = {
    "GF180": "configs/ci/gf180.mk",
    "IHP130": "configs/ci/ihp130.mk",
    "ICS55": "configs/ci/ics55.mk",
    "SKY130": "configs/ci/sky130.mk",
}
NETSIM_BOOT_PROFILES = frozenset(
    ("configs/ci/gf180.mk", "configs/ci/ics55.mk")
)


def pdk_pr_commands(profile: str) -> tuple[tuple[str, tuple[str, ...]], ...]:
    netsim_target = "netsim-boot" if profile in NETSIM_BOOT_PROFILES else "netsim"
    verilator_values = (
        CI_SMOKE_SIM_VALUES
        if profile == "configs/ci/ihp130.mk"
        else CI_SMOKE_SDRAM_SIM_VALUES
    )
    return (
        (profile, RTL_LINT_VALUES),
        (profile, (CI_SMOKE_APP_VALUE, "firmware")),
        (profile, verilator_values),
        (profile, ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm")),
        (profile, ("SYNTH=YOSYS", "synth")),
        (profile, ("STA=OPENSTA", "sta")),
        (
            profile,
            (
                "SIMU=IVERILOG",
                "SIM_FIRMWARE_NAME=retrosoc_asm",
                "RTL_SIM_TIMEOUT=5200000",
                netsim_target,
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
    if suite == "rtl":
        if pdk is not None and pdk != "IHP130":
            raise ValueError("rtl regression supports only --pdk IHP130")
        return RTL_COMMANDS, PR_PROFILES
    if suite == "nightly-extra":
        if pdk is not None and pdk != "IHP130":
            raise ValueError("nightly-extra regression supports only --pdk IHP130")
        return NIGHTLY_EXTRA_COMMANDS, NIGHTLY_PROFILES
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


def with_netsim_boot_only(
    commands: tuple[tuple[str, tuple[str, ...]], ...],
) -> tuple[tuple[str, tuple[str, ...]], ...]:
    """Replace only the local netlist target and retain its selected firmware image."""
    transformed: list[tuple[str, tuple[str, ...]]] = []
    for profile, values in commands:
        if "netsim" not in values:
            transformed.append((profile, values))
            continue
        filtered = tuple(
            value
            for value in values
            if not value.startswith("SIM_SUCCESS_MARKER=")
            and value != "netsim"
        )
        transformed.append((profile, (*filtered, "netsim-boot")))
    return tuple(transformed)


def behavioral_only(
    commands: tuple[tuple[str, tuple[str, ...]], ...],
) -> tuple[tuple[str, tuple[str, ...]], ...]:
    """Exclude synthesis and commands that consume its generated netlist."""
    return tuple(
        (profile, values)
        for profile, values in commands
        if SYNTHESIS_DEPENDENT_TARGETS.isdisjoint(values)
    )


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


def run_observation(command: list[str], root: Path, environment: dict[str, str]) -> None:
    """Run a report-producing quality check without changing the regression verdict."""
    try:
        result = subprocess.run(command, cwd=root, env=environment, check=False)
    except OSError as error:
        print(
            f"non-blocking observation could not start: {error}: {' '.join(command)}",
            file=sys.stderr,
        )
        return
    if result.returncode:
        print(
            f"non-blocking observation failed (exit {result.returncode}): {' '.join(command)}",
            file=sys.stderr,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a supported retroSoC regression suite")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument(
        "--suite", choices=("smoke", "rtl", "pr", "nightly", "nightly-extra"), required=True
    )
    parser.add_argument("--pdk", choices=tuple(PDK_PR_PROFILES), help="run one PDK matrix")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--netsim-boot-only",
        action="store_true",
        help="locally stop each Icarus assembly netlist run after Hello retroSoC!",
    )
    parser.add_argument(
        "--behavioral-only",
        action="store_true",
        help="skip synthesis, STA, netlist simulation, and synthesis-recipe metrics",
    )
    args = parser.parse_args()
    try:
        commands, profiles = select_regression(args.suite, args.pdk)
    except ValueError as error:
        parser.error(str(error))
    if args.netsim_boot_only:
        commands = with_netsim_boot_only(commands)
    if args.behavioral_only:
        commands = behavioral_only(commands)
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
        command = ["make", f"CONFIG={profile}", *RTL_LINT_OBSERVATION_VALUES]
        print("+ " + " ".join(command), flush=True)
        if not args.dry_run:
            run_observation(command, args.root, environment)
        for target in OBSERVATION_TARGETS:
            command = ["make", f"CONFIG={profile}", target]
            print("+ " + " ".join(command), flush=True)
            if not args.dry_run:
                run_observation(command, args.root, environment)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
