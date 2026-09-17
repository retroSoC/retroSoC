#!/usr/bin/env python3
"""Run the isolated NPU-P1 IHP130 synthesis and 72 MHz STA flow."""

from __future__ import annotations

import argparse
import glob
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

SYNTH_TCL = ROOT / "physical/smoke/syn/yosys/script/synth.tcl"
STA_TCL = ROOT / "physical/smoke/sta/opensta/npu_p1.tcl"
STA_SDC = ROOT / "physical/smoke/sta/opensta/npu_p1.sdc"
RUN_FLOW = ROOT / "scripts/run_flow.py"

PDK_ROOT = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref"
STA_LIBERTY = PDK_ROOT / "sg13g2_stdcell/lib/sg13g2_stdcell_slow_1p08V_125C.lib"
STA_LINK_LIB = PDK_ROOT / "sg13g2_io/lib/sg13g2_io_slow_1p08V_3p0V_125C.lib"

TOPS = (
    "npu_local_sram",
    "npu_patch_packer",
    "npu_mac_array",
    "npu_accumulator",
    "npu_vector",
    "npu_requantizer",
)
NPU_RTL = (
    "npu_pkg.sv",
    "npu_local_sram.sv",
    "npu_patch_packer.sv",
    "npu_mac_array.sv",
    "npu_accumulator.sv",
    "npu_vector.sv",
    "npu_requantizer.sv",
)
SRAM_MACRO = "RM_IHPSG13_1P_1024x32_c2_bm_bist"
EXPECTED_SRAM_MACROS = 16
TARGET_PERIOD_PS = 13889

VIOLATED = re.compile(r"VIOLATED")
LATCH = re.compile(r"\$dlatch|latch", re.IGNORECASE)


def _run_flow(tool: str, log: Path, result: Path, env: dict[str, str], command: list[str]) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    args = [sys.executable, str(RUN_FLOW), "--tool", tool, "--log", str(log), "--result", str(result)]
    for name, value in env.items():
        args += ["--env", f"{name}={value}"]
    args += ["--", *command]
    completed = subprocess.run(args, cwd=ROOT)
    if completed.returncode != 0:
        raise RuntimeError(f"{tool} flow failed for {env.get('TOP_DESIGN', env.get('OPENSTA_TOP'))}: {log}")


def _write_filelist(path: Path) -> None:
    lines = [
        "+define+PDK_IHP130",
        "+define+HAVE_SRAM_MACRO",
        "+define+SYNTHESIS",
        "+define+SV_ASSRT_DISABLE",
        f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
        f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
    ]
    for name in NPU_RTL:
        source = ROOT / "rtl/ip/multimedia" / name
        if not source.is_file():
            raise RuntimeError(f"missing NPU-P1 RTL source: {source}")
        lines.append(str(source))
    lines.append(str(ROOT / "rtl/tech/tc_sram.sv"))
    lines.append(str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _synth(top: str, build_root: Path, filelist: Path) -> dict[str, object]:
    base = build_root / "syn/yosys-npu" / top
    for sub in ("out", "tmp", "rpt"):
        (base / sub).mkdir(parents=True, exist_ok=True)
    env = {
        "PDK": "IHP130",
        "SOC": "MINI",
        "SYNTH_RECIPE": "balanced",
        "HAVE_SRAM_MACRO": "YES",
        "SRAM_SIZE_KIB": "32",
        "YOSYS_TARGET_PERIOD_PS": str(TARGET_PERIOD_PS),
        "SV_FLIST": str(filelist),
        "TOP_DESIGN": top,
        "PROJ_NAME": top,
        "BUILD": str(base / "out"),
        "WORK": str(base / "tmp"),
        "REPORTS": str(base / "rpt"),
        "NETLIST": str(base / "out" / f"{top}_yosys.v"),
        "CONFIG": str(base / "out" / f"{top}_yosys.config"),
    }
    log = build_root / "syn/yosys-npu" / f"{top}.log"
    _run_flow("yosys", log, base / "result-synth.json", env, ["yosys", "-c", str(SYNTH_TCL)])
    area = json.loads((base / "rpt" / f"{top}_area.json").read_text(encoding="utf-8"))
    design = area["design"]
    macro_count = design.get("num_cells_by_type", {}).get(SRAM_MACRO, 0)
    latch_cells = {
        name: count
        for name, count in design.get("num_cells_by_type", {}).items()
        if "dlatch" in name.lower() or "latch" in name.lower()
    }
    log_text = log.read_text(encoding="utf-8", errors="replace")
    latch_lines = [
        line
        for line in log_text.splitlines()
        if LATCH.search(line) and "PROC_DLATCH pass" not in line
    ]
    return {
        "top": top,
        "area_um2": design.get("area"),
        "num_cells": design.get("num_cells"),
        "sram_macro_count": macro_count,
        "latch_cells": latch_cells,
        "latch_log_lines": latch_lines[:10],
        "log": str(log),
        "netlist": env["NETLIST"],
    }


def _sta(top: str, build_root: Path, netlist: Path) -> dict[str, object]:
    base = build_root / "sta/opensta-npu" / top
    base.mkdir(parents=True, exist_ok=True)
    sram_libs = sorted(
        glob.glob(str(PDK_ROOT / "sg13g2_sram/lib/*_slow_1p08V_125C.lib"))
    )
    env = {
        "OPENSTA_NETLIST": str(netlist),
        "OPENSTA_LIBERTY": str(STA_LIBERTY),
        "OPENSTA_LINK_LIBS": str(STA_LINK_LIB),
        "OPENSTA_SRAM_LIBS": " ".join(sram_libs),
        "OPENSTA_SDC": str(STA_SDC),
        "OPENSTA_REPORT": str(base / f"{top}_checks.rpt"),
        "OPENSTA_METRICS": str(base / f"{top}_timing_metrics.rpt"),
        "OPENSTA_TOP": top,
    }
    log = base / f"{top}.log"
    _run_flow("opensta", log, base / "result-sta.json", env, ["sta", "-no_init", "-exit", str(STA_TCL)])
    metrics = {}
    for line in (base / f"{top}_timing_metrics.rpt").read_text(encoding="utf-8").splitlines():
        name, _, value = line.partition("=")
        metrics[name] = float(value)
    checks = (base / f"{top}_checks.rpt").read_text(encoding="utf-8", errors="replace")
    return {
        "top": top,
        "wns_setup_ns": metrics.get("wns_max"),
        "tns_setup_ns": metrics.get("tns_max"),
        "setup_paths": metrics.get("paths_max"),
        "wns_hold_ns": metrics.get("wns_min"),
        "tns_hold_ns": metrics.get("tns_min"),
        "hold_paths": metrics.get("paths_min"),
        "violated_paths": len(VIOLATED.findall(checks)),
        "log": str(log),
    }


def _tool_version(command: list[str]) -> str:
    completed = subprocess.run(command, capture_output=True, text=True)
    return (completed.stdout or completed.stderr).splitlines()[0].strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, default=ROOT / "build/npu-p1-flow")
    parser.add_argument("--top", action="append", choices=TOPS, help="limit to one top module")
    parser.add_argument("--synth", action="store_true")
    parser.add_argument("--sta", action="store_true")
    parser.add_argument("--evidence", type=Path, help="evidence JSON output path")
    args = parser.parse_args()
    if not args.synth and not args.sta:
        args.synth = args.sta = True

    tops = tuple(args.top) if args.top else TOPS
    build_root = args.build_root.resolve()
    filelist = build_root / "npu_p1.fl"
    _write_filelist(filelist)

    evidence: dict[str, object] = {
        "phase": "NPU-P1",
        "verification_ids": ["NPU-V017"],
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "tools": {
            "yosys": _tool_version(["yosys", "--version"]),
            "opensta": _tool_version(["sta", "-version"]),
        },
        "target_period_ps": TARGET_PERIOD_PS,
        "filelist": str(filelist),
        "tops": {},
        "failures": [],
    }
    failures: list[str] = evidence["failures"]
    for top in tops:
        record: dict[str, object] = {}
        if args.synth:
            record["synth"] = _synth(top, build_root, filelist)
            synth = record["synth"]
            if top == "npu_local_sram" and synth["sram_macro_count"] != EXPECTED_SRAM_MACROS:
                failures.append(
                    f"npu_local_sram maps {synth['sram_macro_count']} {SRAM_MACRO}, "
                    f"expected {EXPECTED_SRAM_MACROS}"
                )
            if synth["latch_log_lines"] or synth["latch_cells"]:
                failures.append(
                    f"{top} synthesis shows latches: {synth['latch_log_lines']} {synth['latch_cells']}"
                )
        netlist = build_root / "syn/yosys-npu" / top / "out" / f"{top}_yosys.v"
        if args.sta:
            if not netlist.is_file():
                raise RuntimeError(f"missing netlist for {top}: {netlist}; run --synth first")
            record["sta"] = _sta(top, build_root, netlist)
            sta = record["sta"]
            if not (sta["wns_setup_ns"] >= 0.0):
                failures.append(f"{top} setup WNS {sta['wns_setup_ns']} ns < 0")
            if not (sta["tns_setup_ns"] == 0.0):
                failures.append(f"{top} setup TNS {sta['tns_setup_ns']} ns != 0")
            if sta["violated_paths"]:
                failures.append(f"{top} has {sta['violated_paths']} violating paths")
            if not sta["setup_paths"]:
                failures.append(f"{top} has no constrained setup paths (vacuous STA)")
        evidence["tops"][top] = record

    evidence["verdict"] = "PASS" if not failures else "FAIL"
    payload = json.dumps(evidence, indent=2, sort_keys=True) + "\n"
    evidence_path = args.evidence or (build_root / "evidence-p1.json")
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
