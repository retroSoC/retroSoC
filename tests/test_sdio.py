"""Focused standalone SDIO RTL regressions."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONVERTER = ROOT / "rtl/mini/script/convt_sv2v.py"
BUILD = ROOT / "build/test-sdio"

SDIO_FULL_SOURCES = [
    "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
    "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
    "rtl/ip/storage/sdio_if.sv",
    "rtl/ip/storage/sdio_pkg.sv",
    "rtl/ip/storage/sdio_define.svh",
    "rtl/ip/storage/sdio_crc7.sv",
    "rtl/ip/storage/sdio_crc16.sv",
    "rtl/ip/storage/sdio_clock.sv",
    "rtl/ip/storage/sdio_command.sv",
    "rtl/ip/storage/sdio_data.sv",
    "rtl/ip/storage/sdio_dma_descriptor.sv",
    "rtl/ip/peripheral/dma_axi4_master.sv",
    "rtl/ip/storage/sdio_dma.sv",
    "rtl/ip/storage/sdio_reg.sv",
    "rtl/ip/storage/sdio_core.sv",
    "rtl/ip/storage/apb4_sdio.sv",
    "tests/rtl/sdio_native_model.sv",
    "tests/rtl/sdio_axi_memory_responder.sv",
]

SDIO_FULL_INCDIRS = [
    "rtl/managed/clusterip/common/rtl/interface",
    "rtl/ip/peripheral",
    "rtl/ip/storage",
]


def _run_tb(name: str, top: str, sources: list[str], incdirs: list[str], marker: str) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    BUILD.mkdir(parents=True, exist_ok=True)
    filelist = BUILD / f"{name}.fl"
    filelist.write_text(
        "\n".join([*(f"+incdir+{ROOT / path}" for path in incdirs), *(str(ROOT / path) for path in sources)])
        + "\n",
        encoding="utf-8",
    )
    converted = BUILD / f"{name}.v"
    simulation = BUILD / f"{name}.vvp"
    subprocess.run(
        ["python3", str(CONVERTER), "-f", str(filelist), "--output", str(converted)],
        check=True,
    )
    subprocess.run([iverilog, "-g2012", "-s", top, "-o", str(simulation), str(converted)], check=True)
    result = subprocess.run([vvp, str(simulation)], check=True, text=True, capture_output=True)
    assert marker in result.stdout


def _run_verilator_tb(
    name: str, top: str, sources: list[str], incdirs: list[str], marker: str
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return
    build_dir = BUILD / f"{name}-verilator"
    obj_dir = build_dir / "obj"
    obj_dir.mkdir(parents=True, exist_ok=True)
    source_paths = [str(ROOT / path) for path in sources]
    include_args = [f"-I{ROOT / path}" for path in incdirs]
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "--top-module",
            top,
            "-Mdir",
            str(obj_dir),
            "-o",
            "simv",
            *include_args,
            *source_paths,
        ],
        check=True,
    )
    result = subprocess.run(
        [str(obj_dir / "simv")], check=True, text=True, capture_output=True
    )
    assert marker in result.stdout


def test_sdio_crc_vectors() -> None:
    _run_tb(
        "crc",
        "sdio_crc_tb",
        [
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_crc7.sv",
            "rtl/ip/storage/sdio_crc16.sv",
            "tests/rtl/sdio_crc_tb.sv",
        ],
        ["rtl/ip/storage"],
        "SDIO CRC vectors passed",
    )


def test_sdio_phase_clock() -> None:
    _run_tb(
        "clock",
        "sdio_clock_tb",
        ["rtl/ip/storage/sdio_clock.sv", "tests/rtl/sdio_clock_tb.sv"],
        [],
        "SDIO phase clock test passed",
    )


def test_sdio_command_engine() -> None:
    _run_tb(
        "command",
        "sdio_command_tb",
        [
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_clock.sv",
            "rtl/ip/storage/sdio_command.sv",
            "tests/rtl/sdio_command_tb.sv",
        ],
        ["rtl/ip/storage"],
        "SDIO command engine test passed",
    )


def test_sdio_registers() -> None:
    _run_tb(
        "register",
        "sdio_register_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_define.svh",
            "rtl/ip/storage/sdio_reg.sv",
            "tests/rtl/sdio_register_tb.sv",
        ],
        ["rtl/managed/clusterip/common/rtl/interface", "rtl/ip/storage"],
        "SDIO APB register test passed",
    )


def test_sdio_descriptors() -> None:
    _run_tb(
        "descriptor",
        "sdio_descriptor_tb",
        [
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_dma_descriptor.sv",
            "tests/rtl/sdio_descriptor_tb.sv",
        ],
        ["rtl/ip/storage"],
        "SDIO descriptor validation test passed",
    )


def test_sdio_dma() -> None:
    _run_tb(
        "dma",
        "sdio_dma_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
            "rtl/ip/peripheral/dma_axi4_master.sv",
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_dma.sv",
            "tests/rtl/sdio_dma_tb.sv",
        ],
        [
            "rtl/managed/clusterip/common/rtl/interface",
            "rtl/ip/peripheral",
            "rtl/ip/storage",
        ],
        "SDIO DMA descriptor, tail, and 4 KiB split test passed",
    )


def test_sdio_wrapper() -> None:
    _run_tb(
        "wrapper",
        "sdio_wrapper_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
            "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
            "rtl/ip/storage/sdio_if.sv",
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_define.svh",
            "rtl/ip/storage/sdio_crc7.sv",
            "rtl/ip/storage/sdio_crc16.sv",
            "rtl/ip/storage/sdio_clock.sv",
            "rtl/ip/storage/sdio_command.sv",
            "rtl/ip/storage/sdio_data.sv",
            "rtl/ip/storage/sdio_dma_descriptor.sv",
            "rtl/ip/peripheral/dma_axi4_master.sv",
            "rtl/ip/storage/sdio_dma.sv",
            "rtl/ip/storage/sdio_reg.sv",
            "rtl/ip/storage/sdio_core.sv",
            "rtl/ip/storage/apb4_sdio.sv",
            "tests/rtl/sdio_wrapper_tb.sv",
        ],
        [
            "rtl/managed/clusterip/common/rtl/interface",
            "rtl/ip/peripheral",
            "rtl/ip/storage",
        ],
        "SDIO wrapper elaboration and APB smoke test passed",
    )


def test_sdio_standalone_sdhc() -> None:
    _run_tb(
        "standalone-sdhc",
        "sdio_standalone_tb",
        [*SDIO_FULL_SOURCES, "tests/rtl/sdio_standalone_tb.sv"],
        SDIO_FULL_INCDIRS,
        "SDIO standalone native SD model test passed (SDHC)",
    )


def test_sdio_standalone_sdsc() -> None:
    _run_tb(
        "standalone-sdsc",
        "sdio_sdsc_tb",
        [*SDIO_FULL_SOURCES, "tests/rtl/sdio_standalone_tb.sv"],
        SDIO_FULL_INCDIRS,
        "SDIO standalone native SD model test passed (SDSC)",
    )


def test_sdio_standalone_onebit() -> None:
    _run_tb(
        "standalone-onebit",
        "sdio_onebit_tb",
        [*SDIO_FULL_SOURCES, "tests/rtl/sdio_standalone_tb.sv"],
        SDIO_FULL_INCDIRS,
        "SDIO standalone native SD model test passed (SDHC)",
    )


def test_sdio_only_device() -> None:
    _run_tb(
        "sdio-only",
        "sdio_sdio_tb",
        [*SDIO_FULL_SOURCES, "tests/rtl/sdio_sdio_tb.sv"],
        SDIO_FULL_INCDIRS,
        "SDIO-only CMD5/CMD52/CMD53/DAT1 test passed",
    )


def test_sdio_dual_instance() -> None:
    _run_tb(
        "dual",
        "sdio_dual_tb",
        [*SDIO_FULL_SOURCES, "tests/rtl/sdio_dual_tb.sv"],
        SDIO_FULL_INCDIRS,
        "SDIO dual-instance isolation and concurrent traffic test passed",
    )


def test_sdio_dma_stress_contract() -> None:
    _run_tb(
        "dma-stress",
        "sdio_dma_stress_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
            "rtl/ip/peripheral/dma_axi4_master.sv",
            "rtl/ip/storage/sdio_pkg.sv",
            "rtl/ip/storage/sdio_dma.sv",
            "tests/rtl/sdio_axi_memory_responder.sv",
            "tests/rtl/sdio_dma_stress_tb.sv",
        ],
        ["rtl/managed/clusterip/common/rtl/interface", "rtl/ip/peripheral", "rtl/ip/storage"],
        "SDIO AXI 16-beat, 4 KiB split, error, and abort test passed",
    )


def test_sdio_50mhz_clock() -> None:
    _run_tb(
        "50mhz",
        "sdio_50mhz_tb",
        ["rtl/ip/storage/sdio_clock.sv", "tests/rtl/sdio_50mhz_tb.sv"],
        [],
        "SDIO 100 MHz to 50 MHz SDCLK test passed",
    )


def test_sdio_50mhz_clock_verilator() -> None:
    _run_verilator_tb(
        "50mhz",
        "sdio_50mhz_tb",
        ["rtl/ip/storage/sdio_clock.sv", "tests/rtl/sdio_50mhz_tb.sv"],
        [],
        "SDIO 100 MHz to 50 MHz SDCLK test passed",
    )


def test_sdio_sdk_high_speed_enable_sequence() -> None:
    """Keep the SDK high-speed capability/enable/verify/clock order explicit."""

    source = (ROOT / "crt/src/hal/sdio.c").read_text(encoding="utf-8")
    start = source.index("rs_sdio_function_initialize")
    end = source.index("rs_sdio_function_enable", start)
    initialize = source[start:end]
    capability_read = initialize.index('rs_sdio_function_cmd52_read(instance, 0U, 0x13U')
    enable_write = initialize.index("rs_sdio_function_cmd52_write", capability_read)
    verify_read = initialize.index('rs_sdio_function_cmd52_read(instance, 0U, 0x13U', enable_write)
    clock_change = initialize.index("rs_sdio_clock_set", verify_read)
    assert capability_read < enable_write < verify_read < clock_change
    assert "value | UINT8_C(0x02)" in initialize
    assert "value & UINT8_C(0x02)" in initialize
    high_speed_info = initialize.index("info->high_speed = high_speed_enabled")
    assert clock_change < high_speed_info
