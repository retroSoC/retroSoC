"""Directed I2C controller, FIFO, error, timeout, and recovery tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_i2c_controller_and_recovery_contract(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    serial = ROOT / "rtl/ip/serial"
    source_list = tmp_path / "i2c.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{serial}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(serial / "i2c_if.sv"),
                str(serial / "i2c_filter.sv"),
                str(serial / "i2c_core.sv"),
                str(serial / "i2c_reg.sv"),
                str(serial / "apb4_i2c.sv"),
                str(ROOT / "tests/rtl/i2c_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "i2c_tb.v"
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
    simulation = tmp_path / "i2c_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "i2c_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "I2C transfer, error, stretch, arbitration, and recovery test passed" in result.stdout
