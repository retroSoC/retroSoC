#!/usr/bin/env python3
"""Generate the IHP130 LibreLane Chip configuration from canonical SoC data."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from rtl.mini.pin_map.generate_pin_map import (  # noqa: E402
    IHP130_POWER_PAD_COUNTS,
    Pad,
    ihp130_pad_instance,
    read_map,
)
from scripts.setup_helpers import atomic_write  # noqa: E402


SIDE_ORDER = ("south", "east", "north", "west")
EXPECTED_SIGNAL_PADS = 111
CLOCK_PORTS = (
    "extclk_i_pad",
    "audclk_i_pad",
    "jtag_tck_i_pad",
    "gpio_10_io_pad",
    "usb2_ulpi_clk_i_pad",
)
SRAM_INSTANCES = {
    "RM_IHPSG13_1P_4096x16_c3_bm_bist": {
        "u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store."
        "u_packet_ram.u_packet_ram.u_data_high": ([500, 500], "N"),
        "u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store."
        "u_packet_ram.u_packet_ram.u_data_low": ([1000, 500], "N"),
    },
    "RM_IHPSG13_1P_4096x8_c3_bm_bist": {
        "u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store."
        "u_packet_ram.u_packet_ram.u_ecc": ([1500, 500], "N"),
    },
}


def onchip_sram_instances(capacity_kib: int) -> dict[str, tuple[list[int], str]]:
    if capacity_kib <= 0 or capacity_kib % 4 != 0:
        raise ValueError("SRAM_SIZE_KIB must be a positive multiple of 4")
    count = capacity_kib // 4
    return {
        f"u_retrosoc.u_onchip_ram.gen_memory.gen_bank[{index}].u_ram.u_mem": (
            [2000 + (index % 4) * 500, 500 + (index // 4) * 750],
            "N",
        )
        for index in range(count)
    }


def config_path(path: Path, base: Path) -> str:
    return f"dir::{os.path.relpath(path.resolve(), base.resolve())}"


def signal_side(pad: Pad) -> str:
    name = pad.name
    if name.startswith("sdram_"):
        return "west"
    if name.startswith("gpio_"):
        return "east"
    if name.startswith(("sdio1_", "usb2_", "xpi_")):
        return "north"
    return "south"


def power_instances(side_index: int) -> list[str]:
    result: list[str] = []
    for local_index in range(6):
        for kind in ("vdd", "vss"):
            index = (side_index * 6) + local_index
            result.append(f"{kind}_pads[{index}].{kind}_pad")
        if local_index < 4:
            for kind in ("iovdd", "iovss"):
                index = (side_index * 4) + local_index
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


def macro_config(
    master: str, instances: dict[str, tuple[list[int], str]], header: str
) -> dict[str, object]:
    base = "pdk_dir::libs.ref/sg13g2_sram"
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


def build_config(args: argparse.Namespace) -> dict[str, object]:
    target = getattr(args, "target", "chip")
    if target not in {"chip", "core"}:
        raise ValueError("target must be chip or core")
    pads, _ = read_map(args.pin_map)
    active_pads = [pad for pad in pads if pad.feature is None or args.have_pll]
    signal_instances: dict[str, list[str]] = {side: [] for side in SIDE_ORDER}
    for pad in active_pads:
        instance = ihp130_pad_instance(pad)
        if instance is None:
            if pad.kind == "xtal" and not pad.bind:
                continue
            raise ValueError(f"IHP130 physical PAD mapping is missing for {pad.name}")
        signal_instances[signal_side(pad)].append(instance)

    flattened = [item for side in SIDE_ORDER for item in signal_instances[side]]
    if not args.have_pll and len(flattened) != EXPECTED_SIGNAL_PADS:
        raise ValueError(
            f"expected {EXPECTED_SIGNAL_PADS} signal PADs without PLL, got {len(flattened)}"
        )
    if len(flattened) != len(set(flattened)):
        raise ValueError("physical signal PAD instances are not unique")

    pad_sides = {
        side.upper(): interleave(signal_instances[side], power_instances(index))
        for index, side in enumerate(SIDE_ORDER)
    }
    all_placed = [item for side in SIDE_ORDER for item in pad_sides[side.upper()]]
    expected_total = len(flattened) + sum(IHP130_POWER_PAD_COUNTS.values())
    if len(all_placed) != expected_total or len(all_placed) != len(set(all_placed)):
        raise ValueError(
            "PAD ring placement does not cover every signal and power PAD exactly once"
        )

    config_dir = args.output.resolve().parent
    sram_header = config_path(args.sram_vh, config_dir)
    active_sram_instances = dict(SRAM_INSTANCES)
    if getattr(args, "have_sram_macro", False):
        active_sram_instances["RM_IHPSG13_1P_1024x32_c2_bm_bist"] = onchip_sram_instances(
            getattr(args, "sram_size_kib", 32)
        )
    macros = {
        master: macro_config(master, instances, sram_header)
        for master, instances in active_sram_instances.items()
    }
    macro_hooks: list[str] = []
    for instances in active_sram_instances.values():
        for instance in instances:
            bracket_start = instance.find("[")
            if bracket_start >= 0:
                bracket_end = instance.index("]", bracket_start)
                instance_pattern = (
                    re.escape(instance[:bracket_start])
                    + ".*"
                    + instance[bracket_start + 1 : bracket_end]
                    + ".*"
                    + re.escape(instance[bracket_end + 1 :])
                )
            else:
                instance_pattern = re.escape(instance)
            macro_hooks.extend(
                [
                    f"{instance_pattern} VDD VSS VDDARRAY! VSS!",
                    f"{instance_pattern} VDD VSS VDD! VSS!",
                ]
            )

    common = {
        "VERILOG_FILES": [config_path(args.rtl, config_dir)],
        "USE_SLANG": True,
        "SLANG_ARGUMENTS": ["--keep-hierarchy"],
        "VERILOG_POWER_DEFINE": None,
        "SYNTH_SHARE_RESOURCES": False,
        "SYNTH_HIERARCHY_MODE": "deferred_flatten",
        "YOSYS_LOG_LEVEL": "WARNING",
        "SYNTH_STRATEGY": "AREA 3",
        "RUN_POST_GPL_DESIGN_REPAIR": False,
        "RUN_CTS": False,
        "RUN_POST_CTS_RESIZER_TIMING": False,
        "EXTRA_EXCLUDED_CELLS": ["sg13g2_IOPad*"],
        "PRIMARY_GDSII_STREAMOUT_TOOL": "klayout",
        "PNR_SDC_FILE": config_path(args.sdc, config_dir),
        "SIGNOFF_SDC_FILE": config_path(args.sdc, config_dir),
        "FALLBACK_SDC": config_path(args.sdc, config_dir),
        "STA_EXTRA_CORNER_TCL_FILE": config_path(
            ROOT / "physical/librelane/sta_report_limit.tcl", config_dir
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
        "PDN_MACRO_CONNECTIONS": macro_hooks,
        "MAGIC_GDS_FLATGLOB": [
            "lvsres_*",
            "VIA_M1_*",
            "VIA_M2_*",
            "*_CELL_CORNER",
            "RSC_*",
            "*_CELL_SUB",
        ],
    }
    if target == "core":
        return {
            "meta": {"version": 3, "flow": "Classic"},
            "DESIGN_NAME": "retrosoc_core",
            "DIE_AREA": [0, 0, 6000, 6000],
            "CORE_AREA": [120, 120, 5880, 5880],
            "PL_TARGET_DENSITY_PCT": 45,
            "PDN_CORE_RING_CONNECT_TO_PADS": False,
            **common,
        }
    return {
        "meta": {"version": 3, "flow": "Chip"},
        "DESIGN_NAME": "retrosoc_asic",
        "SYNTH_KEEP_HIERARCHY_MODULES": [
            "sg13g2_IOPadVdd",
            "sg13g2_IOPadVss",
            "sg13g2_IOPadIOVdd",
            "sg13g2_IOPadIOVss",
        ],
        "PAD_SOUTH": pad_sides["SOUTH"],
        "PAD_EAST": pad_sides["EAST"],
        "PAD_NORTH": pad_sides["NORTH"],
        "PAD_WEST": pad_sides["WEST"],
        "DIE_AREA": [0, 0, 8000, 8000],
        "CORE_AREA": [365, 365, 7635, 7635],
        "PL_TARGET_DENSITY_PCT": 45,
        "PDN_CORE_RING_CONNECT_TO_PADS": True,
        "PAD_CFG": config_path(ROOT / "physical/librelane/pad_cfg.tcl", config_dir),
        "PAD_BONDPAD_NAME": "bondpad_70x70",
        "EXTRA_GDS": [config_path(args.bondpad_gds, config_dir)],
        "EXTRA_LEFS": [config_path(args.bondpad_lef, config_dir)],
        "IGNORE_DISCONNECTED_MODULES": ["bondpad_70x70"],
        "MAGIC_EXT_UNIQUE": "notopports",
        **common,
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
    parser.add_argument("--aud-clk-hz", type=positive_integer, required=True)
    parser.add_argument("--have-pll", action="store_true")
    parser.add_argument("--have-sram-macro", action="store_true")
    parser.add_argument("--sram-size-kib", type=positive_integer, default=32)
    parser.add_argument("--target", choices=("chip", "core"), default="chip")
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
