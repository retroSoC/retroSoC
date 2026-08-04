#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, load_lock, lock_digest  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check the retroSoC build environment")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--simu", required=True)
    parser.add_argument("--synth", required=True)
    parser.add_argument("--sta", required=True)
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--formal", choices=("YES", "NO"), default="NO")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def version(executable: str) -> str | None:
    path = shutil.which(executable)
    if path is None:
        return None
    options = {
        "iverilog": "-V",
        "vvp": "-V",
        "sta": "-version",
    }
    result = subprocess.run(
        [executable, options.get(executable, "--version")],
        text=True,
        capture_output=True,
        check=False,
    )
    lines = (result.stdout or result.stderr).strip().splitlines()
    return lines[0] if lines else str(path)


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    lock = load_lock(args.lock)
    tools = ["python3", "make", "git", "riscv32-unknown-elf-gcc"]
    if args.simu == "IVERILOG":
        tools.extend(("iverilog", "vvp", "sv2v"))
    elif args.simu == "VERILATOR":
        tools.extend(("verilator", "c++"))
    elif args.simu == "VCS":
        tools.extend(("bsub", "vcs"))
    if args.synth == "YOSYS":
        tools.append("yosys")
    if args.sta == "OPENSTA":
        tools.append("sta")
    if args.formal == "YES":
        tools.extend(("sby", "yosys", "yosys-smtbmc", "sv2v", "bitwuzla"))

    source_names = ["mpw", "hazard3", "cluster_common", "third_party_ip"]
    pdk_names = {
        "IHP130": "pdk_ihp130",
        "ICS55": "pdk_ics55",
        "GF180": "pdk_gf180",
        "SKY130": "pdk_sky130",
    }
    if args.pdk in pdk_names:
        source_names.append(pdk_names[args.pdk])
    paths = {name: root / lock["sources"][name]["destination"] for name in source_names}
    tool_results = {
        tool: {"path": shutil.which(tool), "version": version(tool)}
        for tool in dict.fromkeys(tools)
    }
    path_results = {
        name: {"path": str(path), "exists": path.exists()} for name, path in paths.items()
    }
    failures = sum(value["path"] is None for value in tool_results.values())
    failures += sum(not value["exists"] for value in path_results.values())
    report = {
        "schema_version": 1,
        "ok": failures == 0,
        "failures": failures,
        "dependency_lock_sha256": lock_digest(args.lock),
        "tools": tool_results,
        "paths": path_results,
    }
    serialized = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        atomic_write(args.output, serialized)
    if args.format == "json":
        print(serialized, end="")
    else:
        print("Tools:")
        for name, value in tool_results.items():
            print(f"  {name:<28} {value['path'] or 'MISSING'}")
        print("Paths:")
        for name, value in path_results.items():
            suffix = "[ok]" if value["exists"] else "[MISSING]"
            print(f"  {name:<28} {value['path']} {suffix}")
        print(
            "doctor: all selected requirements are available"
            if not failures
            else f"doctor found {failures} missing requirement(s)"
        )
    return int(failures != 0)


if __name__ == "__main__":
    raise SystemExit(main())
