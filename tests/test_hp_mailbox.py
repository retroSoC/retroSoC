"""HP mailbox RTL regression test."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_hp_mailbox_registers_and_doorbells(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    peripheral = ROOT / "rtl/ip/peripheral"
    filelist = tmp_path / "hp_mailbox.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{peripheral}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(peripheral / "apb4_hp_mailbox.sv"),
                str(ROOT / "tests/rtl/hp_mailbox_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "hp_mailbox_tb.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(filelist),
         "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "hp_mailbox_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "hp_mailbox_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "HP mailbox register and doorbell test passed" in result.stdout
