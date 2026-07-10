#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check the retroSoC build environment")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--simu", required=True)
    parser.add_argument("--synth", required=True)
    parser.add_argument("--sta", required=True)
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--core", required=True)
    parser.add_argument("--ip", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    tools = ["python3", "make", "git", "riscv32-unknown-elf-gcc"]
    if args.simu == "IVERILOG":
        tools.extend(("iverilog", "vvp", "sv2v"))
    elif args.simu == "VERILATOR":
        tools.extend(("verilator", "c++"))
    elif args.simu == "VCS":
        tools.extend(("bsub", "vcs"))
    if args.synth == "YOSYS":
        tools.extend(("yosys", "gawk"))
    if args.sta == "OPENSTA":
        tools.append("sta")

    paths = {
        "MPW generator": root / "rtl/mini/mpw/.git",
        "cluster IP": root / "rtl/clusterip/common",
        "third-party models": root / "rtl/ip/3rd-party",
    }
    pdk_paths = {
        "IHP130": root / "pdk/IHP-Open-PDK",
        "ICS55": root / "pdk/icsprout55-pdk",
        "SKY130": root / "pdk/skywater-sdk",
        "GF180": root / "pdk/gf180mcu-pdk",
    }
    paths[f"PDK {args.pdk}"] = pdk_paths[args.pdk]

    failures = 0
    print("Tools:")
    for tool in dict.fromkeys(tools):
        location = shutil.which(tool)
        status = location or "MISSING"
        print(f"  {tool:<28} {status}")
        failures += location is None

    print("Paths:")
    for name, path in paths.items():
        exists = path.exists()
        print(f"  {name:<28} {path} {'[ok]' if exists else '[MISSING]'}")
        failures += not exists

    if failures:
        print(f"doctor found {failures} missing requirement(s)")
        return 1
    print("doctor: all selected requirements are available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
