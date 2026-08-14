"""RIBP Timer RTL regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERIPHERAL = ROOT / "rtl/ip/peripheral"
def test_timer_modes_interrupts_and_errors(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "timer.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{common / 'clkrst'}",
                f"+incdir+{PERIPHERAL}",
                str(common / "interface/ribp_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "clkrst/counter.sv"),
                str(PERIPHERAL / "timer_core.sv"),
                str(PERIPHERAL / "timer_reg.sv"),
                str(PERIPHERAL / "ribp_timer.sv"),
                str(ROOT / "tests/rtl/timer_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "timer_tb.v"
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
    simulation = tmp_path / "timer_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "timer_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "RIBP Timer register, mode, interrupt, and error test passed" in result.stdout
