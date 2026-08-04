"""RTL regression for XPI output-enable isolation during input phases."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_xpi_releases_data_pads_while_receiving(tmp_path: Path) -> None:
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
    source_list = tmp_path / "xpi_io.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{generated / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/ip/ribp/storage'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/ribp/storage/xpi.sv"),
                str(ROOT / "rtl/ip/ribp/storage/xpi_clkgen.sv"),
                str(ROOT / "rtl/ip/ribp/storage/xpi_core.sv"),
                str(ROOT / "tests/rtl/xpi_io_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "xpi_io_tb.v"
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
    simulation = tmp_path / "xpi_io_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "xpi_io_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "XPI pad drive isolation test passed" in result.stdout
