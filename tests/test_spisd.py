"""Focused standalone SPI-SD RTL regressions."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONVERTER = ROOT / "rtl/mini/script/convt_sv2v.py"
BUILD = ROOT / "build/test-spisd"
COMMON_REGISTER = "rtl/managed/clusterip/common/rtl/utils/register.sv"
INCDIRS = [
    "rtl/managed/clusterip/common/rtl",
    "rtl/managed/clusterip/common/rtl/interface",
    "rtl/managed/clusterip/spi/rtl",
    "rtl/ip/peripheral",
    "rtl/ip/storage",
]


def _run_tb(name: str, top: str, sources: list[str], marker: str) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    BUILD.mkdir(parents=True, exist_ok=True)
    filelist = BUILD / f"{name}.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                *(f"+incdir+{ROOT / path}" for path in INCDIRS),
                *(str(ROOT / path) for path in sources),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    converted = BUILD / f"{name}.v"
    simulation = BUILD / f"{name}.vvp"
    subprocess.run(
        ["python3", str(CONVERTER), "-f", str(filelist), "--output", str(converted)],
        check=True,
    )
    subprocess.run(
        [iverilog, "-g2012", "-s", top, "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation)], check=True, text=True, capture_output=True
    )
    assert marker in result.stdout


def test_spisd_crc_vectors() -> None:
    _run_tb(
        "crc",
        "spisd_crc_tb",
        ["rtl/ip/storage/spisd_pkg.sv", "tests/rtl/spisd_crc_tb.sv"],
        "SPISD CRC vectors passed",
    )


def test_spisd_phase_clock() -> None:
    _run_tb(
        "clock",
        "spisd_clock_tb",
        [COMMON_REGISTER, "rtl/ip/storage/spisd_clock.sv", "tests/rtl/spisd_clock_tb.sv"],
        "SPISD phase clock and low-only pause test passed",
    )


def test_spisd_command_engine() -> None:
    _run_tb(
        "command",
        "spisd_command_tb",
        [
            "rtl/ip/storage/spisd_pkg.sv",
            COMMON_REGISTER,
            "rtl/ip/storage/spisd_clock.sv",
            "rtl/ip/storage/spisd_command.sv",
            "tests/rtl/spisd_command_tb.sv",
        ],
        "SPISD command frame, R1 response, and timeout test passed",
    )


def test_spisd_data_engine() -> None:
    _run_tb(
        "data",
        "spisd_data_tb",
        [
            "rtl/ip/storage/spisd_pkg.sv",
            COMMON_REGISTER,
            "rtl/ip/storage/spisd_data.sv",
            "tests/rtl/spisd_data_tb.sv",
        ],
        "SPISD read/write data, CRC, and backpressure test passed",
    )


def test_spisd_wrapper_apb_and_training() -> None:
    _run_tb(
        "wrapper",
        "spisd_wrapper_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
            "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
            "rtl/managed/clusterip/spi/rtl/spi_if.sv",
            "rtl/ip/storage/spisd_pkg.sv",
            "rtl/ip/storage/spisd_define.svh",
            COMMON_REGISTER,
            "rtl/managed/clusterip/common/rtl/utils/fifo.sv",
            "rtl/ip/peripheral/dma_axi4_master.sv",
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_dma.sv",
            "rtl/ip/storage/spisd_clock.sv",
            "rtl/ip/storage/spisd_command.sv",
            "rtl/ip/storage/spisd_data.sv",
            "rtl/ip/storage/spisd_reg.sv",
            "rtl/ip/storage/spisd_core.sv",
            "rtl/ip/storage/apb4_spisd.sv",
            "rtl/mini/dv/tb/spisd_card.sv",
            "tests/rtl/spisd_wrapper_tb.sv",
        ],
        "SPISD APB ABI, training, card model, and DMA abort test passed",
    )
