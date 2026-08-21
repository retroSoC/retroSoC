"""DMA protocol regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_dma_reports_native_axi4_errors_bursts_and_streams(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    memory_map = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    source_list = tmp_path / "dma_error.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/stream'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/utils'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/ip/peripheral'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_pkg.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_req_if.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_core.sv"),
                str(ROOT / "tests/rtl/dma_error_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "dma_error_tb.v"
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
    simulation = tmp_path / "dma_error_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "dma_error_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "DMA native AXI4 burst, backpressure, stream, and error test passed" in result.stdout


def test_dma_apb_registers_and_irq(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    memory_map = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "dma_reg.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'stream'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{ROOT / 'rtl/ip/peripheral'}",
                str(common / "interface/apb4_if.sv"),
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_pkg.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_req_if.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_reg.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_core.sv"),
                str(ROOT / "rtl/ip/peripheral/apb4_dma.sv"),
                str(ROOT / "tests/rtl/dma_reg_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "dma_reg_tb.v"
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
    simulation = tmp_path / "dma_reg_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "dma_reg_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "DMA APB register and aggregate IRQ test passed" in result.stdout


def test_dma_crypto_stream_endpoints(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    memory_map = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "dma_crypto.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'stream'}",
                f"+incdir+{common / 'utils'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_pkg.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_req_if.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_core.sv"),
                str(ROOT / "tests/rtl/dma_crypto_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "dma_crypto_tb.v"
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
    simulation = tmp_path / "dma_crypto_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "dma_crypto_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "DMA crypto channel 4/5 streaming test passed" in result.stdout
