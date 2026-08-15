"""SystemCtrl RTL regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERIPHERAL = ROOT / "rtl/ip/peripheral"


def test_sysctrl_registers_lifecycle_faults_and_wake(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
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
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/integration/generate_user_extensions.py"),
            "--map",
            str(ROOT / "rtl/mini/integration/user_extensions.json"),
            "--output-dir",
            str(generated / "user_extensions"),
        ],
        check=True,
    )
    source_list = tmp_path / "sysctrl.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{generated / 'rtl'}",
                f"+incdir+{generated / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{PERIPHERAL}",
                str(common / "interface/ribp_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(PERIPHERAL / "pll_ctrl_if.sv"),
                str(PERIPHERAL / "sysctrl_if.sv"),
                str(PERIPHERAL / "sysctrl_define.svh"),
                str(PERIPHERAL / "sysctrl_reg.sv"),
                str(PERIPHERAL / "sysctrl_core.sv"),
                str(PERIPHERAL / "ribp_sysctrl.sv"),
                str(ROOT / "tests/rtl/sysctrl_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "sysctrl_tb.v"
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
    simulation = tmp_path / "sysctrl_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "sysctrl_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "SystemCtrl register, lifecycle, fault, performance, and RTC wake test passed" in (
        result.stdout
    )
