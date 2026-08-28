#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
import re
from pathlib import Path

from filelist import atomic_write, parse_filelists, write_filelist


SCRIPT_DIR = Path(__file__).resolve().parent
MINI_DIR = SCRIPT_DIR.parent
ROOT_DIR = MINI_DIR.parents[1]
DEFAULT_GENERATED_DIR = MINI_DIR / ".generated_fl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate an Icarus Verilog filelist")
    parser.add_argument("--mode", required=True, choices=("behv", "netl", "post"))
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--generated-dir", type=Path, default=DEFAULT_GENERATED_DIR)
    parser.add_argument("--pin-map-rtl-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--converted", type=Path)
    parser.add_argument("--netlist", type=Path)
    parser.add_argument("--sdf", type=Path)
    parser.add_argument("--sdf-scope", default="retrosoc_tb.u_retrosoc_asic")
    return parser.parse_args()


def _require(path: Path | None, description: str) -> Path:
    if path is None or not path.is_file():
        raise FileNotFoundError(f"{description} not found: {path}")
    return path.resolve()


def _prepare_sdf(source: Path, output_dir: Path, scope: str) -> Path:
    sdf_output = output_dir / "timing.sdf"
    if source.suffix == ".gz":
        content = gzip.open(source, "rt", encoding="utf-8", errors="replace").read()
    else:
        content = source.read_text(encoding="utf-8", errors="replace")
    atomic_write(sdf_output, content)

    annotator = output_dir / "sdf_annotator.sv"
    escaped_sdf = str(sdf_output.resolve()).replace("\\", "\\\\").replace('"', '\\"')
    atomic_write(
        annotator,
        "module retrosoc_sdf_annotator;\n"
        "  initial begin\n"
        f'    $sdf_annotate("{escaped_sdf}", {scope}, , "sdf.log", "MINIMUM");\n'
        "  end\n"
        "endmodule\n",
    )
    return annotator


def _standard_cell_models(pdk: str, netlist: Path | None = None) -> list[Path]:
    if pdk == "GF180":
        cells_dir = (
            ROOT_DIR
            / "physical/pdk/gf180mcu-pdk/libraries/gf180mcu_fd_sc_mcu7t5v0/latest/cells"
        )
        sequential_models = {
            "gf180mcu_fd_sc_mcu7t5v0__dffq_1",
            "gf180mcu_fd_sc_mcu7t5v0__dffrnq_1",
            "gf180mcu_fd_sc_mcu7t5v0__dffsnq_1",
        }
        return [
            ROOT_DIR / "rtl/tech/gf180_sim_cells.v",
            *sorted(
                path
                for path in cells_dir.glob("*/*.functional.v")
                if path.name[: -len(".functional.v")] not in sequential_models
            ),
        ]
    if pdk == "SKY130":
        cells_dir = (
            ROOT_DIR / "physical/pdk/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells"
        )
        if netlist is None:
            raise ValueError("SKY130 standard-cell models require a netlist")
        cell_models = {
            path.stem: path
            for path in cells_dir.glob("*/*.v")
            if "." not in path.stem
        }
        cell_types = set(
            re.findall(
                r"^\s*(sky130_fd_sc_hd__[A-Za-z0-9_]+)\s+",
                netlist.read_text(encoding="utf-8", errors="replace"),
                flags=re.MULTILINE,
            )
        )
        missing = sorted(cell_types - cell_models.keys())
        if missing:
            raise FileNotFoundError(
                "missing SKY130 functional model(s): " + ", ".join(missing)
            )
        return sorted(cell_models[cell_type] for cell_type in cell_types)
    return []


def main() -> int:
    args = parse_args()
    generated_dir = args.generated_dir.resolve()
    base_names = ["def.fl", "sys_def.fl", "inc.fl", "tb.fl"]
    base = parse_filelists(generated_dir / name for name in base_names)
    base.options.insert(0, "+timescale+1ns/1ps")
    pin_map_rtl_dir = args.pin_map_rtl_dir.resolve()
    if not pin_map_rtl_dir.is_dir():
        raise FileNotFoundError(f"pin-map RTL directory not found: {pin_map_rtl_dir}")
    base.incdirs.append(pin_map_rtl_dir)

    if args.mode == "behv":
        base.files.append(_require(args.converted, "converted behavioral RTL"))
    else:
        base.extend(parse_filelists([generated_dir / "netlist_support.fl"]))
        base.files.append(_require(args.netlist, f"{args.mode} netlist"))

    if args.mode == "post":
        sdf = _require(args.sdf, "post-layout SDF")
        base.files.append(_prepare_sdf(sdf, args.output.resolve().parent, args.sdf_scope))

    pdk_filelist = generated_dir / f"pdk_{args.pdk.lower()}.fl"
    base.extend(parse_filelists([pdk_filelist]))
    if args.mode != "behv":
        base.files.append(ROOT_DIR / "rtl/tech/netlist_sim_cells.v")
        cell_models = _standard_cell_models(args.pdk, args.netlist)
        if args.pdk == "SKY130":
            base.defines.append("+define+FUNCTIONAL")
            base.defines.append("+define+UNIT_DELAY=#0")
            # SKY130 wrappers include functional models from their cell directory.
            base.incdirs.extend(sorted(path.parent for path in cell_models))
        base.files.extend(cell_models)
    base.deduplicate()
    write_filelist(args.output.resolve(), base)
    print(f"generated {args.mode} filelist: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
