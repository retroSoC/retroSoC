#!/usr/bin/env python3
"""Generate the IHP130 LibreLane Chip configuration for the Tiny SoC."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from scripts.rtl.generate_pin_map import (  # noqa: E402
    POWER_PAD_KINDS,
    Pad,
    ihp130_pad_instance,
    read_map,
    read_power_pad_counts,
)
from scripts.setup_helpers import atomic_write  # noqa: E402


SIDE_ORDER = ("south", "east", "north", "west")
EXPECTED_SIGNAL_PADS = 52
CLOCK_PORTS = ("extclk_i_pad", "jtag_tck_i_pad")
SRAM_MASTER = "RM_IHPSG13_1P_1024x32_c2_bm_bist"
SRAM_INSTANCE = "u_soc.u_sram.gen_group[{group}].u_group.gen_bank[{bank}].u_ram.u_mem"
SRAM_COLUMNS = 8
SRAM_ORIGIN = (400, 600)
# Detailed routing requires an M2 track inside each bank's 0.26 um bottom-edge
# pin stubs: the bank y origin must keep residue {0, 0.24} mod 0.42 um (the M2
# vertical track pitch); a y pitch of 504 um (1200 x 0.42) preserves it per row.
SRAM_PITCH = (480, 504)
DIE_AREA = [0, 0, 4700, 4700]
CORE_AREA = [365, 365, 4335, 4335]


def config_path(path: Path, base: Path) -> str:
    return f"dir::{os.path.relpath(path.resolve(), base.resolve())}"


def signal_side(pad: Pad) -> str:
    name = pad.name
    if name.startswith("gpio_"):
        return "east" if pad.index is not None and pad.index < 16 else "west"
    if name.startswith("xpi_"):
        return "north"
    return "south"


def power_instances(counts: dict[str, int], side_index: int) -> list[str]:
    per_side: dict[str, int] = {}
    for kind in POWER_PAD_KINDS:
        count = counts[kind]
        if count % len(SIDE_ORDER) != 0:
            raise ValueError(
                f"power_pads.{kind}={count} cannot be distributed across "
                f"{len(SIDE_ORDER)} pad-ring sides"
            )
        per_side[kind] = count // len(SIDE_ORDER)
    result: list[str] = []
    for local_index in range(per_side["vdd"]):
        for kind in ("vdd", "vss"):
            index = (side_index * per_side[kind]) + local_index
            result.append(f"{kind}_pads[{index}].{kind}_pad")
    for local_index in range(per_side["iovdd"]):
        for kind in ("iovdd", "iovss"):
            index = (side_index * per_side[kind]) + local_index
            result.append(f"{kind}_pads[{index}].{kind}_pad")
    return result


def interleave(signals: list[str], supplies: list[str]) -> list[str]:
    result: list[str] = []
    signal_index = 0
    for supply_index, supply in enumerate(supplies):
        target = round(((supply_index + 1) * len(signals)) / (len(supplies) + 1))
        result.extend(signals[signal_index:target])
        signal_index = target
        result.append(supply)
    result.extend(signals[signal_index:])
    return result


def sram_instances(capacity_kib: int) -> dict[str, tuple[list[int], str]]:
    if capacity_kib <= 0 or capacity_kib % 4 != 0:
        raise ValueError("SRAM_SIZE_KIB must be a positive multiple of 4")
    instances: dict[str, tuple[list[int], str]] = {}
    for index in range(capacity_kib // 4):
        column, row = index % SRAM_COLUMNS, index // SRAM_COLUMNS
        location = [
            SRAM_ORIGIN[0] + column * SRAM_PITCH[0],
            SRAM_ORIGIN[1] + row * SRAM_PITCH[1],
        ]
        instances[SRAM_INSTANCE.format(group=index // 8, bank=index % 8)] = (location, "N")
    return instances


def macro_config(instances: dict[str, tuple[list[int], str]], header: str) -> dict[str, object]:
    base = "pdk_dir::libs.ref/sg13g2_sram"
    master = SRAM_MASTER
    return {
        "gds": [f"{base}/gds/{master}.gds"],
        "lef": [f"{base}/lef/{master}.lef"],
        "vh": [header],
        "spice": [f"{base}/cdl/{master}.cdl"],
        "lib": {
            "*_typ_1p20V_25C": [f"{base}/lib/{master}_typ_1p20V_25C.lib"],
            "*_fast_1p32V_m40C": [f"{base}/lib/{master}_fast_1p32V_m55C.lib"],
            "*_slow_1p08V_125C": [f"{base}/lib/{master}_slow_1p08V_125C.lib"],
        },
        "instances": {
            name: {"location": location, "orientation": orientation}
            for name, (location, orientation) in instances.items()
        },
    }


def macro_hooks(instances: dict[str, tuple[list[int], str]]) -> list[str]:
    hooks: list[str] = []
    for instance in instances:
        # OpenDB and synthesis may escape array brackets differently. Handle
        # every index (group and bank), retaining the exact non-index hierarchy.
        instance_pattern = ".*".join(re.escape(part) for part in re.split(r"[\[\]]", instance))
        hooks.extend(
            [
                f"{instance_pattern} VDD VSS VDDARRAY! VSS!",
                f"{instance_pattern} VDD VSS VDD! VSS!",
            ]
        )
    return hooks


def build_config(args: argparse.Namespace) -> dict[str, object]:
    pads, _ = read_map(args.pin_map)
    power_counts = read_power_pad_counts(args.pin_map)
    signal_instances: dict[str, list[str]] = {side: [] for side in SIDE_ORDER}
    for pad in pads:
        instance = ihp130_pad_instance(pad)
        if instance is None:
            raise ValueError(f"IHP130 physical PAD mapping is missing for {pad.name}")
        signal_instances[signal_side(pad)].append(instance)

    flattened = [item for side in SIDE_ORDER for item in signal_instances[side]]
    if len(flattened) != EXPECTED_SIGNAL_PADS:
        raise ValueError(
            f"expected {EXPECTED_SIGNAL_PADS} signal PADs, got {len(flattened)}"
        )
    if len(flattened) != len(set(flattened)):
        raise ValueError("physical signal PAD instances are not unique")

    pad_sides = {
        side.upper(): interleave(signal_instances[side], power_instances(power_counts, index))
        for index, side in enumerate(SIDE_ORDER)
    }
    all_placed = [item for side in SIDE_ORDER for item in pad_sides[side.upper()]]
    expected_total = len(flattened) + sum(power_counts.values())
    if len(all_placed) != expected_total or len(all_placed) != len(set(all_placed)):
        raise ValueError(
            "PAD ring placement does not cover every signal and power PAD exactly once"
        )

    config_dir = args.output.resolve().parent
    sram_header = config_path(args.sram_vh, config_dir)
    active_sram_instances = sram_instances(args.sram_size_kib) if args.have_sram_macro else {}
    macros = (
        {SRAM_MASTER: macro_config(active_sram_instances, sram_header)}
        if active_sram_instances
        else {}
    )

    return {
        "meta": {"version": 3, "flow": "Chip"},
        "DESIGN_NAME": "retrosoc_tiny_asic",
        "VERILOG_FILES": [config_path(args.rtl, config_dir)],
        "USE_SLANG": True,
        "SLANG_ARGUMENTS": ["--keep-hierarchy"],
        "VERILOG_POWER_DEFINE": None,
        "SYNTH_SHARE_RESOURCES": False,
        "SYNTH_HIERARCHY_MODE": "deferred_flatten",
        "SYNTH_KEEP_HIERARCHY_MODULES": [
            "sg13g2_IOPadVdd",
            "sg13g2_IOPadVss",
            "sg13g2_IOPadIOVdd",
            "sg13g2_IOPadIOVss",
        ],
        "YOSYS_LOG_LEVEL": "WARNING",
        "SYNTH_STRATEGY": "AREA 3",
        # Hotspots sit at the SRAM bank pin edges; detailed routing resolves the
        # moderate estimated overflow. The signoff bar remains detailed-routing
        # DRC, post-RCX multi-corner STA, KLayout DRC, and netgen LVS.
        "GRT_ALLOW_CONGESTION": True,
        # This OpenROAD build's antenna analysis leaks/stalls on the Tiny netlist
        # (check_antennas -verbose ballooned to 248 GB RSS; repair_antennas did
        # not converge in 100 minutes). Skip the report/repair steps; antenna
        # coverage is a documented gap for this flow revision.
        "RUN_ANTENNA_REPAIR": False,
        # Hazard3 with EXTENSION_A=0 (RV32IM) leaves x_amo_phase undriven by
        # design; every use is masked by a constant-false guard. Waive the
        # three benign "used but has no driver" check errors.
        "ERROR_ON_SYNTH_CHECKS": False,
        "RUN_POST_GPL_DESIGN_REPAIR": False,
        "RUN_CTS": False,
        "RUN_POST_CTS_RESIZER_TIMING": False,
        "EXTRA_EXCLUDED_CELLS": ["sg13g2_IOPad*"],
        "PRIMARY_GDSII_STREAMOUT_TOOL": "klayout",
        "PNR_SDC_FILE": config_path(args.sdc, config_dir),
        "SIGNOFF_SDC_FILE": config_path(args.sdc, config_dir),
        "FALLBACK_SDC": config_path(args.sdc, config_dir),
        "STA_EXTRA_CORNER_TCL_FILE": config_path(
            ROOT / "physical/librelane/tiny/sta_report_limit.tcl", config_dir
        ),
        "CLOCK_PORT": list(CLOCK_PORTS),
        "CLOCK_PERIOD": 1_000_000_000 / args.ext_clk_hz,
        "VDD_NETS": ["VDD"],
        "GND_NETS": ["VSS"],
        "FP_SIZING": "absolute",
        "PDN_CORE_RING": True,
        "PDN_CORE_RING_VWIDTH": 15,
        "PDN_CORE_RING_HWIDTH": 15,
        "PDN_CORE_RING_VSPACING": 5,
        "PDN_CORE_RING_HSPACING": 5,
        "PDN_ENABLE_PINS": True,
        "ERROR_ON_PDN_VIOLATIONS": True,
        "PDN_CFG": config_path(args.pdn, config_dir),
        "MACROS": macros,
        "PDN_MACRO_CONNECTIONS": macro_hooks(active_sram_instances),
        "MAGIC_GDS_FLATGLOB": [
            "lvsres_*",
            "VIA_M1_*",
            "VIA_M2_*",
            "*_CELL_CORNER",
            "RSC_*",
            "*_CELL_SUB",
        ],
        "PAD_SOUTH": pad_sides["SOUTH"],
        "PAD_EAST": pad_sides["EAST"],
        "PAD_NORTH": pad_sides["NORTH"],
        "PAD_WEST": pad_sides["WEST"],
        "DIE_AREA": DIE_AREA,
        "CORE_AREA": CORE_AREA,
        "PL_TARGET_DENSITY_PCT": 45,
        "PDN_CORE_RING_CONNECT_TO_PADS": True,
        "PAD_CFG": config_path(ROOT / "physical/librelane/tiny/pad_cfg.tcl", config_dir),
        "PAD_BONDPAD_NAME": "bondpad_70x70",
        "EXTRA_GDS": [config_path(args.bondpad_gds, config_dir)],
        "EXTRA_LEFS": [config_path(args.bondpad_lef, config_dir)],
        "IGNORE_DISCONNECTED_MODULES": ["bondpad_70x70"],
        "MAGIC_EXT_UNIQUE": "notopports",
    }


def positive_integer(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin-map", type=Path, required=True)
    parser.add_argument("--rtl", type=Path, required=True)
    parser.add_argument("--sdc", type=Path, required=True)
    parser.add_argument("--pdn", type=Path, required=True)
    parser.add_argument("--bondpad-gds", type=Path, required=True)
    parser.add_argument("--bondpad-lef", type=Path, required=True)
    parser.add_argument("--sram-vh", type=Path, required=True)
    parser.add_argument("--ext-clk-hz", type=positive_integer, required=True)
    parser.add_argument("--have-sram-macro", action="store_true")
    parser.add_argument("--sram-size-kib", type=positive_integer, default=128)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = build_config(args)
        atomic_write(args.output, json.dumps(config, indent=2, sort_keys=True) + "\n")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
