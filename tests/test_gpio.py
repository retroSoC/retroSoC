"""Directed RTL tests for the GPIO register and pad-control contract."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_gpio_register_pad_interrupt_and_filter_contract(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return

    peripheral = ROOT / "rtl/ip/peripheral"
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "gpio.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{peripheral}",
                f"+incdir+{common}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "clkrst/counter.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "utils/edge_det.sv"),
                str(peripheral / "gpio_if.sv"),
                str(peripheral / "user_gpio_if.sv"),
                str(peripheral / "gpio_core.sv"),
                str(peripheral / "gpio_reg.sv"),
                str(peripheral / "apb4_gpio.sv"),
                str(ROOT / "tests/rtl/gpio_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "gpio_tb.v"
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
    simulation = tmp_path / "gpio_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "gpio_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "GPIO directed test passed" in result.stdout
