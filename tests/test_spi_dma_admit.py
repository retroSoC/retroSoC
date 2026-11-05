"""Dynamic SPI DMA admission, response-retirement, and recovery checks."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from test_tiny_r2_p7 import COMMON, run_rtl

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_spi_dma_admission_and_recovery(tmp_path: Path, simulator: str) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(tmp_path / "map"),
            "--have-sram-if",
            "NO",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    log = run_rtl(
        tmp_path,
        simulator,
        "spi_dma_admit_tb",
        [
            COMMON / "utils/fifo.sv",
            COMMON / "stream/round_robin_arbiter.sv",
            COMMON / "interface/axi4_stream_if.sv",
            ROOT / "rtl/tiny/top/tiny_axi42apb4.sv",
            ROOT / "rtl/ip/peripheral/dma_req_if.sv",
            ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
            ROOT / "rtl/ip/peripheral/dma_reg.sv",
            ROOT / "rtl/ip/peripheral/dma_core.sv",
            ROOT / "rtl/ip/peripheral/apb4_dma.sv",
            ROOT / "rtl/ip/serial/spi_ctrl_if.sv",
            ROOT / "rtl/ip/serial/spi_reg.sv",
            ROOT / "rtl/ip/serial/spi_phase_ctrl.sv",
            ROOT / "rtl/ip/serial/spi_word_packer.sv",
            ROOT / "rtl/ip/serial/spi_gpio_guard.sv",
            ROOT / "rtl/ip/serial/spi_dma_pacing.sv",
            ROOT / "rtl/ip/serial/spi_master_core.sv",
            ROOT / "rtl/ip/serial/apb4_spi.sv",
        ],
        defines=[
            f"-I{ROOT / 'rtl/ip/peripheral'}",
            f"-I{ROOT / 'rtl/ip/serial'}",
            f"-I{tmp_path / 'map/rtl'}",
        ],
        packages=[
            ROOT / "rtl/ip/peripheral/dma_pkg.sv",
            ROOT / "rtl/ip/serial/spi_pkg.sv",
        ],
    )
    assert "SPI_DMA_ADMIT_PASS tx_full=1 rx_empty=1 delayed_B=1 delayed_R=1 abort_inflight=1" in log
    assert not DEFAULT_FAILURE.search(log)
