"""Directed USB2/SDIO0/APU Gateway A contention evidence for APU-P8."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def test_apu_p8_gateway_a_contention(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        pytest.skip("iverilog, vvp, or sv2v is not installed")

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_p8_gateway_contention.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/mini/top/hp_axi4_mux3.sv"),
                str(ROOT / "tests/rtl/apu_p8_gateway_contention_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p8_gateway_contention_tb.v"
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
    simulation = tmp_path / "apu_p8_gateway_contention_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_p8_gateway_contention_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P8 Gateway A contention passed" in result.stdout
