"""APB4 I2S register, CDC, clocking, and interrupt regression."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_i2s_controller_abi_and_clocking(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    ip = ROOT / "rtl/ip/serial"
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
        str(common / "interface/apb4_if.sv"),
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
        str(ip / "i2s_pkg.sv"),
        str(ip / "i2s_reg.sv"),
        str(ip / "i2s_clkgen.sv"),
        str(ip / "i2s_recv.sv"),
        str(ip / "i2s_send.sv"),
        str(ip / "i2s_core.sv"),
        str(ip / "apb4_i2s.sv"),
        str(ROOT / "tests/rtl/i2s_tb.sv"),
    ]
    source_list = tmp_path / "i2s.fl"
    source_list.write_text("\n".join([*defines, *source, ""]), encoding="utf-8")
    converted = tmp_path / "i2s.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(source_list), "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "i2s_tb"
    subprocess.run([iverilog, "-g2012", "-s", "i2s_tb", "-o", str(simulation), str(converted)], check=True)
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APB4 I2S controller test passed" in result.stdout
