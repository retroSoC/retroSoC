"""UART register, FIFO, framing, flow-control, interrupt, and DMA tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_uart_register_fifo_loopback_flow_control_and_errors(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    serial = ROOT / "rtl/ip/serial"
    source_list = tmp_path / "uart.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{serial}",
                str(common / "interface/apb4_if.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/edge_det.sv"),
                str(common / "utils/fifo.sv"),
                str(serial / "uart_if.sv"),
                str(serial / "uart_baudgen.sv"),
                str(serial / "apb4_uart_tx.sv"),
                str(serial / "apb4_uart_rx.sv"),
                str(serial / "uart_flow_ctrl.sv"),
                str(serial / "uart_core.sv"),
                str(serial / "uart_reg.sv"),
                str(serial / "apb4_uart.sv"),
                str(ROOT / "tests/rtl/uart_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "uart_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "uart_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "uart_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "UART register, FIFO, loopback, flow-control, interrupt, and DMA test passed" in result.stdout
