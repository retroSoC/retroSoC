"""CLINT RTL regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERIPHERAL = ROOT / "rtl/ip/peripheral"


def test_clint_standard_map_multi_hart_and_timebase(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "clint.fl"
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
                str(common / "utils/edge_det.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "clkrst/counter.sv"),
                str(PERIPHERAL / "clint_if.sv"),
                str(PERIPHERAL / "clint_timebase.sv"),
                str(PERIPHERAL / "clint_reg.sv"),
                str(PERIPHERAL / "clint_core.sv"),
                str(PERIPHERAL / "ribp_clint.sv"),
                str(ROOT / "tests/rtl/clint_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "clint_tb.v"
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
    simulation = tmp_path / "clint_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "clint_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "CLINT standard map, multi-hart, IRQ, error, and timebase test passed" in result.stdout
