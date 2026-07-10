#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
from pathlib import Path

from filelist import FileList, atomic_write, parse_filelists, write_filelist


SCRIPT_DIR = Path(__file__).resolve().parent
MINI_DIR = SCRIPT_DIR.parent
DEFAULT_GENERATED_DIR = MINI_DIR / ".generated_fl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate an Icarus Verilog filelist")
    parser.add_argument("--mode", required=True, choices=("behv", "netl", "post"))
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--generated-dir", type=Path, default=DEFAULT_GENERATED_DIR)
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


def main() -> int:
    args = parse_args()
    generated_dir = args.generated_dir.resolve()
    base_names = ["def.fl", "sys_def.fl", "inc.fl", "tb.fl"]
    base = parse_filelists(generated_dir / name for name in base_names)
    base.options.insert(0, "+timescale+1ns/1ps")

    if args.mode == "behv":
        base.files.append(_require(args.converted, "converted behavioral RTL"))
    else:
        common = parse_filelists([generated_dir / "commonip.fl"])
        base.extend(common)
        base.files.append(_require(args.netlist, f"{args.mode} netlist"))

    if args.mode == "post":
        sdf = _require(args.sdf, "post-layout SDF")
        base.files.append(_prepare_sdf(sdf, args.output.resolve().parent, args.sdf_scope))

    pdk_filelist = generated_dir / f"pdk_{args.pdk.lower()}.fl"
    base.extend(parse_filelists([pdk_filelist]))
    base.deduplicate()
    write_filelist(args.output.resolve(), base)
    print(f"generated {args.mode} filelist: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
