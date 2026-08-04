"""DMA protocol regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_dma_reports_bus_errors_and_transfers_exact_word_count(tmp_path: Path) -> None:
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
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/mini/top/soc_ribl_if.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv"),
                str(ROOT / "rtl/ip/ribp/peripheral/dma.sv"),
                str(ROOT / "rtl/ip/ribp/peripheral/dma_core.sv"),
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
    assert "dma error and burst performance test passed" in result.stdout
