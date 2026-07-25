#!/usr/bin/env python3
"""Generate the narrow formal source list for one Mini SoC protocol proof."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[2]
FILELIST_DIR = ROOT / "rtl/mini/script"
sys.path.insert(0, str(FILELIST_DIR))

from filelist import FileList, write_filelist  # noqa: E402


COMMON_RTL = ROOT / "rtl/managed/clusterip/common/rtl"
INTERCONNECT = ROOT / "rtl/ip/native/interconnect"
TOP = ROOT / "rtl/mini/top"


def source_files(target: str) -> list[Path]:
    common = [
        COMMON_RTL / "interface/nmi_if.sv",
        COMMON_RTL / "utils/register.sv",
    ]
    if target == "bus":
        return [
            *common,
            INTERCONNECT / "nmi_regslice.sv",
            TOP / "bus.sv",
            SCRIPT_DIR / "bus_formal.sv",
        ]
    if target == "nmi2apb":
        return [
            COMMON_RTL / "interface/nmi_if.sv",
            COMMON_RTL / "interface/apb4_pure_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/edge_det.sv",
            INTERCONNECT / "nmi2apb.sv",
            SCRIPT_DIR / "nmi2apb_formal.sv",
        ]
    raise ValueError(f"unsupported formal target: {target}")


def generate(target: str, output: Path, memory_map_dir: Path, soc_topology_dir: Path) -> bool:
    filelist = FileList(
        defines=["+define+SV_ASSRT_DISABLE"],
        incdirs=[
            memory_map_dir.resolve() / "rtl",
            soc_topology_dir.resolve() / "rtl",
            TOP,
            COMMON_RTL,
            COMMON_RTL / "interface",
            COMMON_RTL / "utils",
            INTERCONNECT,
        ],
        files=source_files(target),
    ).deduplicate()
    return write_filelist(output.resolve(), filelist)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("bus", "nmi2apb"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--memory-map-dir", type=Path, required=True)
    parser.add_argument("--soc-topology-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    changed = generate(
        args.target,
        args.output,
        args.memory_map_dir,
        args.soc_topology_dir,
    )
    print(f"formal filelist {'updated' if changed else 'unchanged'}: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
