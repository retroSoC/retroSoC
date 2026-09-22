#!/usr/bin/env python3
"""Export the APU block-level Yosys synthesis filelist (apb4_apu as top).

The filelist is the exact subset of the whole-SoC synthesis inputs that the
APU block needs: the APU sources from rtl/mini/filelist/ip.fl, the three
clusterip interface definitions used in the APU port list, the tc_sram
wrapper from rtl/mini/filelist/tech.fl, and the include directories from
rtl/mini/filelist/inc.fl. PDK filelists are excluded, matching comb.py in
the whole-SoC flow: SRAM macros arrive as Liberty black boxes through
read_liberty -lib in init_tech.tcl, never as behavioral Verilog.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_DIR = REPO_ROOT / "rtl/mini/script"
sys.path.insert(0, str(SCRIPT_DIR))
from filelist import FileList, parse_filelists, write_filelist  # noqa: E402
from generate_filelist import generate_all  # noqa: E402


APU_SOURCE_MARKERS = ("/ip/multimedia/apu_", "/ip/multimedia/apb4_apu.sv")
INTERFACE_SOURCES = ("apb4_if.sv", "axi4_if.sv", "axi4_stream_if.sv")
# clusterip utility cells used inside the APU RTL: register.sv provides the
# dff/dffr/dffrc register cells; soc_common_fifo.sv includes fifo.sv for the
# stream_fifo used by the stream router and primitive dispatcher.
UTILITY_SOURCES = ("register.sv", "soc_common_fifo.sv")
# DMA engine frontend instantiated by apu_dma.sv.
IP_SOURCES = ("dma_axi4_master.sv",)
TECH_SOURCES = ("tc_sram.sv",)


def select_sources(paths: list[Path], names: tuple[str, ...], origin: str) -> list[Path]:
    selected = [path for path in paths if path.name in names]
    missing = [name for name in names if name not in {path.name for path in selected}]
    if missing:
        raise FileNotFoundError(f"{origin} does not provide: {', '.join(missing)}")
    return selected


def select_apu_sources(paths: list[Path]) -> list[Path]:
    selected = [
        path
        for path in paths
        if any(marker in path.as_posix() for marker in APU_SOURCE_MARKERS)
    ]
    names = {path.name for path in selected}
    if "apb4_apu.sv" not in names or "apu_microcode_pkg.sv" not in names:
        raise FileNotFoundError("ip.fl does not provide the complete APU source set")
    return selected


def build_block_filelist(defines: list[str], generated_dir: Path) -> FileList:
    includes = parse_filelists([generated_dir / "inc.fl"])
    interfaces = parse_filelists([generated_dir / "commonip.fl"])
    tech = parse_filelists([generated_dir / "tech.fl"])
    ip = parse_filelists([generated_dir / "ip.fl"])

    block = FileList()
    block.defines = list(defines)
    block.incdirs = list(includes.incdirs)
    block.files = [
        *select_sources(interfaces.files, INTERFACE_SOURCES, "commonip.fl"),
        *select_sources(interfaces.files, UTILITY_SOURCES, "commonip.fl"),
        *select_sources(tech.files, TECH_SOURCES, "tech.fl"),
        *select_sources(ip.files, IP_SOURCES, "ip.fl"),
        *select_apu_sources(ip.files),
    ]
    return block.deduplicate()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--define",
        action="append",
        default=[],
        help="filelist +define+ token, same convention as generate_filelist.py",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    invalid = [item for item in args.define if not item.startswith("+define+")]
    if invalid:
        raise SystemExit(f"invalid define token(s): {' '.join(invalid)}")
    if not any(item == "+define+PDK_IHP130" for item in args.define):
        raise SystemExit("the APU block flow is locked to +define+PDK_IHP130")
    if not any(item == "+define+HAVE_SRAM_MACRO" for item in args.define):
        raise SystemExit("the APU block flow requires +define+HAVE_SRAM_MACRO")
    output_dir = args.output_dir.resolve()
    generated_dir = output_dir / "templates"
    generate_all(generated_dir, args.define)
    filelist = build_block_filelist(args.define, generated_dir)
    output = output_dir / "apu_block.fl"
    write_filelist(output, filelist)
    print(f"generated APU block filelist: {output} ({len(filelist.files)} sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
