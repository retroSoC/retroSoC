"""Directed tests for the SoC-owned RIB building blocks."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_bus_preserves_incr4_and_rejects_illegal_bursts(tmp_path: Path) -> None:
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
    source_list = tmp_path / "rib_bus.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ram_if.sv"),
                str(ROOT / "rtl/mini/top/soc_ribl_if.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/mini/top/soc_ribl2rib.sv"),
                str(ROOT / "rtl/mini/top/soc_rib2ribp.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_error_slave.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_ram.sv"),
                str(ROOT / "rtl/mini/top/bus.sv"),
                str(ROOT / "tests/rtl/rib_bus_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "rib_bus_tb.v"
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
    simulation = tmp_path / "rib_bus_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "rib_bus_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "RIB burst arbitration and protocol test passed" in result.stdout


def test_common_spill_register_preserves_ready_valid_data(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "spill_register_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "spill_register_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
            str(ROOT / "tests/rtl/spill_register_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "spill register ready/valid test passed" in result.stdout


def test_burst_sram_preserves_data_and_backpressure(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    source_list = tmp_path / "soc_rib_ram.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ram_if.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/mini/top/soc_rib_ram.sv"),
                str(ROOT / "tests/rtl/soc_rib_ram_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "soc_rib_ram_tb.v"
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
    simulation = tmp_path / "soc_rib_ram_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "soc_rib_ram_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "RIB SRAM pipeline test passed" in result.stdout
