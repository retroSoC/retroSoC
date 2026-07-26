"""RTL tests for user-IP ownership of the native GPIO pad bank."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_user_ip_can_own_native_gpio_pads_with_a_safe_handoff(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return

    source_list = tmp_path / "gpio_user_mux.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{ROOT / 'rtl/ip/native/peripheral'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/nmi_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/edge_det.sv"),
                str(ROOT / "rtl/ip/native/peripheral/gpio.sv"),
                str(ROOT / "tests/rtl/gpio_user_mux_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "gpio_user_mux_tb.v"
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
    simulation = tmp_path / "gpio_user_mux_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "gpio_user_mux_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "GPIO user ownership test passed" in result.stdout
