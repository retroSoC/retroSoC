"""HP PLIC RTL regression test."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_plic_priority_claim_and_completion(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    peripheral = ROOT / "rtl/ip/peripheral"
    filelist = tmp_path / "plic.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(peripheral / "apb4_plic.sv"),
                str(ROOT / "tests/rtl/plic_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "plic_tb.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(filelist),
         "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "plic_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "plic_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "PLIC priority, claim, and completion test passed" in result.stdout
