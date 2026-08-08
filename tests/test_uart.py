"""UART V2 register, FIFO, framing, interrupt, and DMA request tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_uart_v2_register_fifo_loopback_and_errors(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    serial = ROOT / "rtl/ip/ribp/serial"
    cluster_uart = ROOT / "rtl/managed/clusterip/uart/rtl"
    source_list = tmp_path / "uart.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{serial}",
                str(common / "interface/ribp_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(cluster_uart / "uart_if.sv"),
                str(serial / "uart_baudgen.sv"),
                str(serial / "ribp_uart_tx.sv"),
                str(serial / "ribp_uart_rx.sv"),
                str(serial / "uart_core.sv"),
                str(serial / "uart_reg.sv"),
                str(serial / "ribp_uart.sv"),
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
    assert "UART V2 register, FIFO, loopback, error, interrupt, and DMA test passed" in result.stdout
