"""Required GA2D Phase 6 synthesized-block netlist transaction test."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from test_ga2d import _generate_memory_map, _require_tool


ROOT = Path(__file__).resolve().parents[1]

P6_NETLIST_SUCCESS_MARKER = (
    "GA2D P6 netlist block test passed with exact FILL COPY BLEND and "
    "validation-error coverage"
)

SYNTH_TCL = ROOT / "physical/smoke/syn/yosys/script/synth.tcl"
SUMMARY_SCRIPT = ROOT / "scripts/ga2d_block_summary.py"
SYNTH_WRAPPER = ROOT / "physical/smoke/syn/yosys/apb4_ga2d_block_top.sv"
CELL_MODELS = (
    ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_udp.v",
    ROOT
    / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v",
    ROOT / "rtl/tech/netlist_sim_cells.v",
)


def _ga2d_block_synth_sources(memory_map: Path) -> list[str]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    return [
        "+incdir+" + str(memory_map),
        "+incdir+" + str(common),
        "+incdir+" + str(common / "interface"),
        "+incdir+" + str(multimedia),
        str(common / "interface/apb4_if.sv"),
        str(common / "interface/axi4_if.sv"),
        str(common / "utils/register.sv"),
        str(common / "utils/fifo.sv"),
        str(common / "stream/round_robin_arbiter.sv"),
        str(multimedia / "ga2d_pkg.sv"),
        str(multimedia / "ga2d_addr_gen.sv"),
        str(multimedia / "ga2d_axi4_master.sv"),
        str(multimedia / "ga2d_dma.sv"),
        str(multimedia / "ga2d_pixel.sv"),
        str(multimedia / "ga2d_core.sv"),
        str(multimedia / "ga2d_reg.sv"),
        str(multimedia / "apb4_ga2d.sv"),
        str(SYNTH_WRAPPER),
    ]


def _synthesize_block_netlist(tmp_path: Path) -> Path:
    yosys = _require_tool("yosys")
    memory_map = _generate_memory_map(tmp_path)
    filelist = tmp_path / "ga2d_block_synth.fl"
    filelist.write_text(
        "\n".join((*_ga2d_block_synth_sources(memory_map), "")),
        encoding="utf-8",
    )
    period = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/yosys_period.py"),
            "--domains",
            str(ROOT / "rtl/mini/integration/clock_reset_domains.json"),
            "--domain",
            "pclk",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    build = tmp_path / "syn"
    reports = build / "rpt"
    netlist = build / "out/apb4_ga2d_block_top_yosys.v"
    for directory in (build / "out", build / "tmp", reports):
        directory.mkdir(parents=True)
    result = subprocess.run(
        [yosys, "-c", str(SYNTH_TCL)],
        check=True,
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PDK": "IHP130",
            "SOC": "MINI",
            "SYNTH_RECIPE": "balanced",
            "HAVE_SRAM_MACRO": "YES",
            "SRAM_SIZE_KIB": "32",
            "YOSYS_TARGET_PERIOD_PS": period,
            "YOSYS_FLATTEN_HIER": "1",
            "SV_FLIST": str(filelist),
            "TOP_DESIGN": "apb4_ga2d_block_top",
            "CONFIG": str(build / "out/apb4_ga2d_block_top_yosys.config"),
            "YOSYS_KEEP_HIER_INST": "",
            "YOSYS_REPORT_INSTS": "",
            "PROJ_NAME": "apb4_ga2d_block_top",
            "WORK": str(build / "tmp"),
            "BUILD": str(build / "out"),
            "REPORTS": str(reports),
            "NETLIST": str(netlist),
        },
    )
    log = build / "yosys.log"
    log.write_text(result.stdout, encoding="utf-8")
    subprocess.run(
        [
            sys.executable,
            str(SUMMARY_SCRIPT),
            "--log",
            str(log),
            "--check-report",
            str(reports / "apb4_ga2d_block_top_synth.rpt"),
            "--area-json",
            str(reports / "apb4_ga2d_block_top_area.json"),
            "--registers-report",
            str(reports / "apb4_ga2d_block_top_registers.rpt"),
            "--generic-report",
            str(reports / "apb4_ga2d_block_top_generic.rpt"),
            "--top",
            "apb4_ga2d_block_top",
            "--pdk",
            "IHP130",
            "--recipe",
            "balanced",
            "--period-ps",
            period,
            "--cell-prefix",
            "sg13g2_",
            "--output",
            str(reports / "ga2d_block_summary.json"),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return netlist


def test_ga2d_p6_netlist_block(tmp_path: Path) -> None:
    iverilog = _require_tool("iverilog")
    vvp = _require_tool("vvp")
    netlist = _synthesize_block_netlist(tmp_path)
    simulation = tmp_path / "ga2d_netlist_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-gno-specify",
            "-I",
            str(ROOT / "rtl/ip/multimedia"),
            *(str(path) for path in CELL_MODELS),
            str(netlist),
            str(ROOT / "tests/rtl/ga2d_netlist_tb.sv"),
            "-o",
            str(simulation),
            "-s",
            "ga2d_netlist_tb",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert P6_NETLIST_SUCCESS_MARKER in result.stdout
