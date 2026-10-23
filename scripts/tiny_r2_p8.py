#!/usr/bin/env python3
"""Retain P8 inputs and validate CPU/DMA pin-level workload evidence."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as evidence  # noqa: E402
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402

PHASE = "TINY-R2-P8"


def measurements(content: str, config: dict, absent: bool = False) -> dict:
    if DEFAULT_FAILURE.search(content) or "SIM_TEST_PASS Tiny cycles=" not in content:
        raise ValueError("missing strict Tiny terminal success or forbidden error marker")
    rows = [dict((k, int(v)) for k, v in re.findall(r"(\w+)=(\d+)", line))
            for line in content.splitlines() if line.startswith("P8_TRANSPORT ")]
    windows = [dict((k, int(v)) for k, v in re.findall(r"(\w+)=(\d+)", line))
               for line in content.splitlines() if line.startswith("P8_XPI_WINDOW ")]
    terminal = re.findall(r"P8_RESULT code=(\d+) profiles=(\d+)", content)
    if len(terminal) != 1 or terminal[0] != ("0", str(len(rows))):
        raise ValueError("missing or inconsistent firmware workload result")
    if absent:
        if rows or windows or "P8_ABSENT bounded optional-device rejection" not in content:
            raise ValueError("absent-device run must reject initialization and perform no mapped DMA")
        return {"mode": "absent", "profiles": [], "windows": []}
    expected = [(24000000, 24000000)]
    if config["PDK"] == "ICS55":
        expected += [(192000000, 96000000), (240000000, 120000000)]
    elif int(config["EXT_CLK_HZ"]) != 24000000:
        expected += [(int(config["EXT_CLK_HZ"]), int(config["EXT_CLK_HZ"]))]
    if [(r.get("sys_hz"), r.get("mem_hz")) for r in rows] != expected:
        raise ValueError("missing, duplicated or unexpected clock profiles")
    if len(windows) != 4 * len(rows):
        raise ValueError("missing isolated/contended write and readback observation windows")
    for index, row in enumerate(rows):
        if row.get("bytes") != 1024 or row.get("burst") != 4 or row.get("progress", 0) <= 0:
            raise ValueError("incorrect workload size/burst or no concurrent CPU progress")
        for name in ("isolated", "contended"):
            cycles = row.get(f"{name}_cycles", 0)
            if cycles <= 0:
                raise ValueError("invalid measured cycle count")
            row[f"{name}_bytes_per_second"] = row["bytes"] * row["sys_hz"] / cycles
        for offset, window in enumerate(windows[index * 4:index * 4 + 4]):
            counts = (window.get("write_bytes"), window.get("read_bytes"))
            if (counts != ((1024, 0) if offset % 2 == 0 else (0, 1024)) or
                    window.get("index") != index * 4 + offset or window.get("mem_cycles", 0) <= 0):
                raise ValueError("wrong mapped-path byte accounting")
            for channel in ("aw", "w", "ar", "b", "r"):
                stall = window.get(f"{channel}_max", -1)
                if not 0 <= stall <= window["mem_cycles"]:
                    raise ValueError("missing or impossible backpressure measurement")
                window[f"{channel}_max_ns"] = stall * 1e9 / row["mem_hz"]
    return {"mode": "present", "profiles": rows, "windows": windows,
            "limits": "Digital model only; measured stalls apply only to this finite workload. "
                      "No physical frequency, unrestricted contention or camera rate qualification."}


def source_inputs() -> dict:
    inputs = evidence.source_inputs(ROOT, "ICS55") | evidence.source_inputs(ROOT, "IHP130")
    for folder in ("rtl/model", "tests", "configs/ci"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in (".sv", ".svh", ".py", ".c", ".h", ".mk"):
                inputs[str(path.relative_to(ROOT))] = evidence.sha256(path)
    return inputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "report"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--variant-root", type=Path)
    parser.add_argument("--simulator", choices=("verilator", "iverilog"))
    parser.add_argument("--attempt", type=Path)
    parser.add_argument("--absent", action="store_true")
    args = parser.parse_args()
    if args.variant_root:
        args.variant_root = args.variant_root.resolve()
    try:
        if args.output.exists():
            raise ValueError("evidence already exists; select a new attempt")
        inputs = source_inputs()
        if args.action == "capture":
            if not all((args.variant_root, args.simulator)):
                raise ValueError("capture requires a built --variant-root and --simulator")
            runtime = evidence.runtime_inputs(ROOT, args.variant_root, args.simulator)
            for path in (args.variant_root / "sw/firmware",
                         args.variant_root / "sw/retrosoc_fw.hex",
                         args.variant_root / "sim" / args.simulator /
                         ("emu" if args.simulator == "verilator" else "simv")):
                runtime[str(path.resolve().relative_to(ROOT))] = evidence.sha256(path)
            evidence.dump(args.output, {
                "phase": PHASE, "repository": evidence.git_info(ROOT),
                "captured_at": datetime.now(timezone.utc).isoformat(),
                "variant": str(args.variant_root.resolve()), "simulator": args.simulator,
                "runtime_inputs": runtime,
                "specification": evidence.artifact(ROOT / "docs/ip/tiny-soc.md"),
                "source_inputs": inputs, "source_digest": evidence.digest_map(inputs),
                "tools": evidence.tools_identity(ROOT),
                "snapshot": evidence.snapshot(ROOT, args.output.parent / "source", inputs),
            })
        else:
            if not all((args.source, args.variant_root, args.simulator, args.attempt)):
                raise ValueError("report requires --source --variant-root --simulator --attempt")
            source = evidence.read_json(args.source)
            if source.get("phase") != PHASE or source.get("source_inputs") != inputs:
                raise ValueError("source changed since the retained snapshot")
            if (source.get("variant") != str(args.variant_root.resolve()) or
                    source.get("simulator") != args.simulator):
                raise ValueError("runtime snapshot belongs to another variant or simulator")
            for name, digest in source["runtime_inputs"].items():
                if evidence.sha256(ROOT / name) != digest:
                    raise ValueError(f"runtime input changed after capture: {name}")
            manifest = evidence.read_json(args.variant_root / "meta/manifest.json")
            config = manifest["configuration"]
            if (config.get("SOC") != "TINY" or config.get("TINY_P8_ACCEPTANCE") != "YES" or
                    config.get("PDK") not in ("ICS55", "IHP130")):
                raise ValueError("not an explicit Tiny P8 configuration")
            result = evidence.read_json(args.attempt / "result-sim.json")
            log = args.attempt / "sim.log"
            if (result.get("status") != "passed" or result.get("exit_code") != 0 or
                    Path(result.get("log", "")).resolve() != log.resolve()):
                raise ValueError("simulation command did not complete successfully with this log")
            if datetime.fromisoformat(result["started_at"]) < datetime.fromisoformat(source["captured_at"]):
                raise ValueError("simulation predates the source/runtime snapshot")
            command = result.get("command", [])
            binary = args.variant_root / "sim" / args.simulator / (
                "emu" if args.simulator == "verilator" else "simv")
            firmware_arg = "+firmware=" + str((args.variant_root / "sw/retrosoc_fw.hex").resolve())
            if (str(binary.resolve()) not in command or firmware_arg not in command or
                    "+tiny_p8_psram" not in command or (("+p8_absent" in command) != args.absent)):
                raise ValueError("simulation command does not match captured binary/firmware/mode")
            report = measurements(log.read_text(), config, args.absent)
            artifacts = [log, args.attempt / "result-sim.json", args.source,
                         args.variant_root / "sw/firmware",
                         args.variant_root / "sw/retrosoc_fw.hex",
                         args.variant_root / "sim" / args.simulator /
                         ("emu" if args.simulator == "verilator" else "simv")]
            evidence.dump(args.output, {"phase": PHASE, "status": "passed",
                "configuration": config, "simulator": args.simulator, "measurements": report,
                "source_digest": source["source_digest"],
                "artifacts": [evidence.artifact(p) for p in artifacts]})
        print(f"{PHASE} {args.action}: PASS ({args.output})")
        return 0
    except (OSError, ValueError, KeyError) as error:
        print(f"{PHASE}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
