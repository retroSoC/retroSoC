"""WS2812 register, waveform, and streaming regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_ws2812_register_waveform_streaming_and_errors(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    serial = ROOT / "rtl/ip/ribp/serial"
    source_list = tmp_path / "ws2812.fl"
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
                str(serial / "ws2812_if.sv"),
                str(serial / "ws2812_reg.sv"),
                str(serial / "ws2812_core.sv"),
                str(serial / "ribp_ws2812.sv"),
                str(ROOT / "tests/rtl/ws2812_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "ws2812_tb.v"
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
    simulation = tmp_path / "ws2812_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "ws2812_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "WS2812 register, waveform, streaming, and error test passed" in result.stdout


def test_ws2812_accepts_dma_fixed_destination_backpressure(tmp_path: Path) -> None:
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
    serial = ROOT / "rtl/ip/ribp/serial"
    source_list = tmp_path / "ws2812_dma.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{serial}",
                str(common / "interface/ribp_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/mini/top/rib_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/ip/ribp/peripheral/dma.sv"),
                str(ROOT / "rtl/ip/ribp/peripheral/dma_core.sv"),
                str(serial / "ws2812_if.sv"),
                str(serial / "ws2812_reg.sv"),
                str(serial / "ws2812_core.sv"),
                str(serial / "ribp_ws2812.sv"),
                str(ROOT / "tests/rtl/ws2812_dma_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "ws2812_dma_tb.v"
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
    simulation = tmp_path / "ws2812_dma_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "ws2812_dma_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "WS2812 DMA backpressure integration test passed" in result.stdout
