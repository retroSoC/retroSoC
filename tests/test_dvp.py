"""RIBP DVP V2 register, CDC, framing, and packing regression."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_dvp_capture_framing(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    ip = ROOT / "rtl/ip/ribp/multimedia"
    defines = [
        "+define+PDK_BEHAV",
        "+define+SV_ASSRT_DISABLE",
    ]
    source = [
        "+incdir+" + str(common),
        "+incdir+" + str(common / "interface"),
        "+incdir+" + str(common / "utils"),
        "+incdir+" + str(common / "cdc"),
        "+incdir+" + str(common / "clkrst"),
        "+incdir+" + str(ip),
        str(common / "interface/ribp_if.sv"),
        str(common / "interface/axi4_stream_if.sv"),
        str(common / "utils/register.sv"),
        str(common / "utils/xchecker.sv"),
        str(common / "utils/bin2gray.sv"),
        str(common / "utils/gray2bin.sv"),
        str(common / "utils/spill_register.sv"),
        str(common / "cdc/cdc_sync.sv"),
        str(common / "cdc/cdc_rst_ctrlr.sv"),
        str(common / "cdc/async_reqack.sv"),
        str(common / "cdc/cdc_fifo.sv"),
        str(common / "cdc/cdc_2phase.sv"),
        str(common / "cdc/cdc_warm_flush.sv"),
        str(common / "utils/edge_det.sv"),
        str(common / "clkrst/rst_sync.sv"),
        str(ROOT / "rtl/tech/tc_clk.sv"),
        str(ip / "dvp_core.sv"),
        str(ip / "dvp_reg.sv"),
        str(ip / "dvp.sv"),
        str(ROOT / "tests/rtl/dvp_tb.sv"),
    ]
    source_list = tmp_path / "dvp.fl"
    source_list.write_text("\n".join([*defines, *source, ""]), encoding="utf-8")
    converted = tmp_path / "dvp.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(source_list), "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "dvp_tb"
    subprocess.run([iverilog, "-g2012", "-s", "dvp_tb", "-o", str(simulation), str(converted)], check=True)
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "RIBP DVP V2 capture test passed" in result.stdout
