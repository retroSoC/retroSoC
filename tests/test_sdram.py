"""SDRAM controller data-integrity regression."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_sdram_controller_preserves_full_and_masked_writes(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    generated = tmp_path / "generated"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
        ],
        check=True,
    )
    source_list = tmp_path / "sdram_data.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{generated / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_clkgen.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_reg.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_core.sv"),
                str(ROOT / "rtl/mini/dv/verilator/rtl/sdram_verilator_model.sv"),
                str(ROOT / "tests/rtl/sdram_data_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "sdram_data_tb.v"
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
    simulation = tmp_path / "sdram_data_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "sdram_data_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sdram data integrity test passed" in result.stdout


def test_sdram_controller_preserves_data_with_micron_timing_model(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    generated = tmp_path / "generated"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
        ],
        check=True,
    )
    source_list = tmp_path / "sdram_timing.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                "+define+SDRAM_TIMING_MODEL",
                f"+incdir+{generated / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/third_party/model/sdram'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_clkgen.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_reg.sv"),
                str(ROOT / "rtl/ip/ribp/memory/sdram_core.sv"),
                str(ROOT / "tests/rtl/sdram_data_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "sdram_timing_tb.v"
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
    simulation = tmp_path / "sdram_timing_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "sdram_data_tb",
            "-I",
            str(ROOT / "rtl/managed/third_party/model/sdram"),
            "-o",
            str(simulation),
            str(converted),
            str(ROOT / "rtl/managed/third_party/model/sdram/sdr.v"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sdram data integrity test passed" in result.stdout
