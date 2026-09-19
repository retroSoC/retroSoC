#!/usr/bin/env python3
"""Run the isolated NPU IHP130 synthesis and 72 MHz STA flow (P1/P3 modules)."""

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
    "npu_dma",
    "npu_job_decoder",
    "npu_scheduler",
    "npu_core",
    "apb4_npu",
)
NPU_RTL = (
    "npu_pkg.sv",
    "npu_local_sram.sv",
    "npu_patch_packer.sv",
    "npu_mac_array.sv",
    "npu_accumulator.sv",
    "npu_vector.sv",
    "npu_requantizer.sv",
    "npu_dma.sv",
    "npu_job_decoder.sv",
    "npu_scheduler.sv",
    "npu_reg.sv",
    "npu_control_cdc.sv",
    "npu_core.sv",
    "apb4_npu.sv",
)
# Tops whose only non-logic port is an AXI4 master interface get a generated
# synthesis wrapper in the build tree (never tracked): the interface is
# instantiated inside the wrapper so the DUT has no unconnected ports.
INTERFACE_WRAPPED = {
    "npu_dma": """
module npu_dma_synth_top (
    input  logic        clk_hp_i,
    input  logic        rst_hp_n_i,
    input  logic        clear_i,
    input  logic        block_new_i,
    output logic        pause_ack_o,
    input  logic        read_req_valid_i,
    output logic        read_req_ready_o,
    input  logic [31:0] read_addr_i,
    input  logic [31:0] read_bytes_i,
    output logic        read_data_valid_o,
    input  logic        read_data_ready_i,
    output logic [63:0] read_data_o,
    output logic [ 7:0] read_keep_o,
    output logic        read_last_o,
    input  logic        write_req_valid_i,
    output logic        write_req_ready_o,
    input  logic [31:0] write_addr_i,
    input  logic [31:0] write_bytes_i,
    input  logic        write_data_valid_i,
    output logic        write_data_ready_o,
    input  logic [63:0] write_data_i,
    input  logic [ 7:0] write_keep_i,
    input  logic        write_last_i,
    output logic        write_done_o,
    output logic        busy_o,
    output logic        read_busy_o,
    output logic        write_busy_o,
    output logic [63:0] read_bytes_o,
    output logic [63:0] write_bytes_o,
    output logic [63:0] stall_cycles_o,
    output logic        fault_o,
    output logic [ 3:0] fault_code_o,
    output logic [31:0] fault_addr_o,
    output logic [ 1:0] fault_resp_o,
    output logic        read_cmd_err_o,
    output logic        write_cmd_err_o
);
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  npu_dma u_dut (
      .clk_hp_i          (clk_hp_i),
      .rst_hp_n_i        (rst_hp_n_i),
      .clear_i           (clear_i),
      .block_new_i       (block_new_i),
      .pause_ack_o       (pause_ack_o),
      .read_req_valid_i  (read_req_valid_i),
      .read_req_ready_o  (read_req_ready_o),
      .read_addr_i       (read_addr_i),
      .read_bytes_i      (read_bytes_i),
      .read_data_valid_o (read_data_valid_o),
      .read_data_ready_i (read_data_ready_i),
      .read_data_o       (read_data_o),
      .read_keep_o       (read_keep_o),
      .read_last_o       (read_last_o),
      .write_req_valid_i (write_req_valid_i),
      .write_req_ready_o (write_req_ready_o),
      .write_addr_i      (write_addr_i),
      .write_bytes_i     (write_bytes_i),
      .write_data_valid_i(write_data_valid_i),
      .write_data_ready_o(write_data_ready_o),
      .write_data_i      (write_data_i),
      .write_keep_i      (write_keep_i),
      .write_last_i      (write_last_i),
      .write_done_o      (write_done_o),
      .busy_o            (busy_o),
      .read_busy_o       (read_busy_o),
      .write_busy_o      (write_busy_o),
      .read_bytes_o      (read_bytes_o),
      .write_bytes_o     (write_bytes_o),
      .stall_cycles_o    (stall_cycles_o),
      .fault_o           (fault_o),
      .fault_code_o      (fault_code_o),
      .fault_addr_o      (fault_addr_o),
      .fault_resp_o      (fault_resp_o),
      .read_cmd_err_o    (read_cmd_err_o),
      .write_cmd_err_o   (write_cmd_err_o),
      .axi4              (u_axi4)
  );
endmodule
""",
    "apb4_npu": """
module apb4_npu_synth_top (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       clk_hp_i,
    input  logic       rst_hp_n_i,
    input  logic [1:0] resource_owner_i,
    input  logic       resource_owner_lock_i,
    input  logic       resource_quiesce_i,
    input  logic       resource_reset_i,
    output logic       idle_o,
    output logic       block_ack_o,
    output logic       irq_o,
    input  logic       hp_block_new_i,
    output logic       hp_pause_ack_o,
    input  logic       hp_flush_i,
    output logic       hp_flush_busy_o,
    output logic       hp_idle_o
);
  apb4_if u_apb4 (.pclk(clk_i), .presetn(rst_n_i));
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_npu_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  apb4_npu u_dut (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .clk_hp_i            (clk_hp_i),
      .rst_hp_n_i          (rst_hp_n_i),
      .resource_owner_i    (resource_owner_i),
      .resource_owner_lock_i(resource_owner_lock_i),
      .resource_quiesce_i  (resource_quiesce_i),
      .resource_reset_i    (resource_reset_i),
      .apb4                (u_apb4),
      .idle_o              (idle_o),
      .block_ack_o         (block_ack_o),
      .irq_o               (irq_o),
      .hp_block_new_i      (hp_block_new_i),
      .hp_pause_ack_o      (hp_pause_ack_o),
      .hp_flush_i          (hp_flush_i),
      .hp_flush_busy_o     (hp_flush_busy_o),
      .hp_idle_o           (hp_idle_o),
      .npu_axi4            (u_npu_axi4)
  );
endmodule
""",
}
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


def _synth_top(top: str) -> str:
    return f"{top}_synth_top" if top in INTERFACE_WRAPPED else top


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
            raise RuntimeError(f"missing NPU RTL source: {source}")
        lines.append(str(source))
    common_rtl = ROOT / "rtl/managed/clusterip/common/rtl"
    lines.append(str(ROOT / "rtl/tech/tc_sram.sv"))
    for extra in (
        "interface/apb4_if.sv",
        "interface/axi4_if.sv",
        "utils/register.sv",
        "utils/xchecker.sv",
        "utils/fifo.sv",
        "clkrst/rst_sync.sv",
        "cdc/cdc_sync.sv",
        "cdc/cdc_rst_ctrlr.sv",
        "cdc/async_reqack.sv",
    ):
        source = common_rtl / extra
        if not source.is_file():
            raise RuntimeError(f"missing Common source: {source}")
        lines.append(str(source))
    path.parent.mkdir(parents=True, exist_ok=True)
    for top, wrapper in INTERFACE_WRAPPED.items():
        wrapper_path = path.parent / f"{_synth_top(top)}.sv"
        wrapper_path.write_text(wrapper, encoding="utf-8")
        lines.append(str(wrapper_path))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _synth(top: str, build_root: Path, filelist: Path) -> dict[str, object]:
    base = build_root / "syn/yosys-npu" / top
    synth_top = _synth_top(top)
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
        "TOP_DESIGN": synth_top,
        "PROJ_NAME": synth_top,
        "BUILD": str(base / "out"),
        "WORK": str(base / "tmp"),
        "REPORTS": str(base / "rpt"),
        "NETLIST": str(base / "out" / f"{synth_top}_yosys.v"),
        "CONFIG": str(base / "out" / f"{synth_top}_yosys.config"),
    }
    log = build_root / "syn/yosys-npu" / f"{top}.log"
    _run_flow("yosys", log, base / "result-synth.json", env, ["yosys", "-c", str(SYNTH_TCL)])
    area = json.loads((base / "rpt" / f"{synth_top}_area.json").read_text(encoding="utf-8"))
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
        "OPENSTA_TOP": _synth_top(top),
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
        netlist = build_root / "syn/yosys-npu" / top / "out" / f"{_synth_top(top)}_yosys.v"
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
