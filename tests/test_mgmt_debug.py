"""Directed reset-sequencing test for the management Hazard3 debug path."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_management_debug_reset_waits_for_the_ahbl_bridge(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "mgmt_debug_reset_tb"
    sources = (
        ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv",
        ROOT / "rtl/mini/top/mgmt_debug_reset.sv",
        ROOT / "tests/rtl/mgmt_debug_reset_tb.sv",
    )
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            f"-I{ROOT / 'rtl/managed/clusterip/common/rtl'}",
            "-s",
            "mgmt_debug_reset_tb",
            "-o",
            str(simulation),
            *(str(source) for source in sources),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "management debug reset test passed" in result.stdout
