#!/usr/bin/env python3
"""Validate the reproducible padless ICS55 ECC hardening environment."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import load_lock  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402


EXPECTED_ECC_VERSION = "ecc 0.1.0a10"
EXPECTED_CLOCKS = (
    "clk_external",
    "clk_system",
    "clk_audio",
    "clk_jtag",
    "clk_dvp",
    "clk_usb2_ulpi",
)


def command_environment(project: Path) -> dict[str, str]:
    cache = project / ".fontconfig-cache"
    cache.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["XDG_CACHE_HOME"] = str(cache)
    return environment


def command_output(command: list[str], project: Path) -> str:
    return subprocess.check_output(
        command,
        text=True,
        stderr=subprocess.STDOUT,
        env=command_environment(project),
    ).strip()


def ecc_version(binary: Path, project: Path) -> str:
    output = command_output([str(binary), "--version"], project)
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in reversed(lines):
        if line.startswith("ecc "):
            return line
    return output


def read_config(path: Path) -> dict[str, Any]:
    with path.open("rb") as source:
        data = tomllib.load(source)
    if not isinstance(data, dict):
        raise ValueError("ECC configuration must be a TOML object")
    return data


def validate_config(config: dict[str, Any], sdc: Path) -> tuple[list[str], dict[str, object]]:
    errors: list[str] = []
    details: dict[str, object] = {}
    design = config.get("design")
    pdk = config.get("pdk")
    flow = config.get("flow")
    if not isinstance(design, dict):
        errors.append("ecc.toml [design] table is missing")
        design = {}
    if not isinstance(pdk, dict):
        errors.append("ecc.toml [pdk] table is missing")
        pdk = {}
    if not isinstance(flow, dict):
        errors.append("ecc.toml [flow] table is missing")
        flow = {}
    details["top"] = design.get("top")
    details["pdk"] = pdk.get("name")
    details["preset"] = flow.get("preset")
    if design.get("name") != "retrosoc_core" or design.get("top") != "retrosoc_core":
        errors.append("ECC design must target the padless retrosoc_core macro")
    if design.get("clock_port") != "extclk_i_pad":
        errors.append("ECC primary clock must be the logical extclk_i_pad port")
    if pdk.get("name") != "ics55":
        errors.append("ECC PDK must be ics55")
    if flow.get("preset") != "harden":
        errors.append("ECC flow preset must be harden")
    overrides = pdk.get("overrides")
    if not isinstance(overrides, dict):
        errors.append("ECC PDK overrides are required for padless H7CR hardening")
        overrides = {}
    for field in ("tech", "lefs", "libs", "sdc", "site_core", "tap_cell", "end_cap", "fillers"):
        if field not in overrides:
            errors.append(f"ECC PDK override is missing: {field}")
    lefs = overrides.get("lefs", [])
    libs = overrides.get("libs", [])
    if not isinstance(lefs, list) or len(lefs) != 1 or "H7CR" not in str(lefs[0]):
        errors.append("ECC must use exactly one H7CR standard-cell LEF")
    if not isinstance(libs, list) or len(libs) != 1 or "h7cr" not in str(libs[0]).lower():
        errors.append("ECC must use exactly one H7CR standard-cell Liberty")
    no_pad_markers = ("IO", "PAD", "bondpad")
    lef_values = lefs if isinstance(lefs, list) else []
    lib_values = libs if isinstance(libs, list) else []
    flattened = " ".join(str(value) for value in [*lef_values, *lib_values])
    if any(marker.lower() in flattened.lower() for marker in no_pad_markers):
        errors.append("ECC padless flow may not reference IO, PAD, or bondpad collateral")
    if not sdc.is_file():
        errors.append(f"ECC SDC is missing: {sdc}")
    else:
        text = sdc.read_text(encoding="utf-8")
        missing = [clock for clock in EXPECTED_CLOCKS if f"-name {clock}" not in text]
        if missing:
            errors.append("ECC SDC is missing clock(s): " + ", ".join(missing))
        if "set_clock_groups -name retrosoc_async -asynchronous" not in text:
            errors.append("ECC SDC must preserve asynchronous clock groups")
    return errors, details


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--ecc", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--pdk-root", type=Path, required=True)
    parser.add_argument("--sdc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    errors: list[str] = []
    details: dict[str, object] = {}
    project = args.project.resolve()
    config_path = project / "ecc.toml"
    lock = load_lock(args.lock)
    details["ecc_archive_sha256"] = lock["archives"]["ecc_cli_linux_x86_64"]["sha256"]
    details["locked_pdk_revision"] = lock["sources"]["pdk_ics55"]["revision"]

    if not args.ecc.is_file() or not args.ecc.stat().st_mode & 0o111:
        errors.append(f"ECC executable is missing or not executable: {args.ecc}")
    else:
        try:
            version = ecc_version(args.ecc, project)
            details["ecc_version"] = version
            if version != EXPECTED_ECC_VERSION:
                errors.append(f"expected {EXPECTED_ECC_VERSION}, found {version or '<empty>'}")
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append(f"cannot execute ECC: {error}")

    if not (args.pdk_root / ".git").is_dir():
        errors.append(f"ICS55 PDK checkout is missing: {args.pdk_root}")
    else:
        try:
            revision = command_output(
                ["git", "-C", str(args.pdk_root), "rev-parse", "HEAD"], project
            )
            details["pdk_revision"] = revision
            if revision != details["locked_pdk_revision"]:
                errors.append(
                    f"expected ICS55 PDK {details['locked_pdk_revision']}, found {revision}"
                )
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append(f"cannot inspect ICS55 PDK revision: {error}")

    required = (
        args.pdk_root / "prtech/techLEF/N551P6M_ecos.lef",
        args.pdk_root
        / "IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CR/lef/"
        "ics55_LLSC_H7CR_ecos.lef",
    )
    for path in required:
        if not path.is_file():
            errors.append(f"required padless ICS55 PDK input is missing: {path}")

    if not config_path.is_file():
        errors.append(f"ECC project configuration is missing: {config_path}")
    else:
        try:
            config_errors, config_details = validate_config(read_config(config_path), args.sdc.resolve())
            errors.extend(config_errors)
            details.update(config_details)
        except (OSError, tomllib.TOMLDecodeError, ValueError) as error:
            errors.append(f"cannot validate ECC project configuration: {error}")

    if not errors and args.ecc.is_file():
        try:
            check = subprocess.run(
                [str(args.ecc), "check", "--project", str(project), "--json"],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=command_environment(project),
            )
            details["ecc_check"] = json.loads(check.stdout)
        except subprocess.CalledProcessError as error:
            errors.append(f"ECC project check failed: {error.stdout.strip()}")
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"ECC project check failed: {error}")

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
    print(f"ECC doctor passed: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
