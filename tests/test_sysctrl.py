"""SystemCtrl RTL regression tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERIPHERAL = ROOT / "rtl/ip/peripheral"
TOP = ROOT / "rtl/mini/top"


def test_sysctrl_fault_master_keeps_the_data_plane_high_bit() -> None:
    interface = (PERIPHERAL / "sysctrl_if.sv").read_text(encoding="utf-8")
    core = (PERIPHERAL / "sysctrl_core.sv").read_text(encoding="utf-8")
    top = (TOP / "retrosoc.sv").read_text(encoding="utf-8")
    fault_cdc = (TOP / "data_plane_fault_cdc.sv").read_text(encoding="utf-8")

    assert "logic [                         3:0] fault_master_i;" in interface
    assert "28'd0, s_fault_master_q" in core
    assert "{1'b0, s_bus_fault_master}" in top
    assert "data_plane_fault_cdc u_data_plane_fault_cdc" in top
    assert ".fault_ready_i           (s_data_plane_fault_ready_hp)" in top
    assert "s_data_plane_fault_valid_pclk || s_bus_fault_valid" in top
    assert "async_reqack" in fault_cdc
    assert "fault_ready_o" in fault_cdc


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
                    "+define+MINI_PRODUCT",
                f"+incdir+{generated / 'rtl'}",
                f"+incdir+{generated / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'utils'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{PERIPHERAL}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "clkrst/rst_sync.sv"),
                str(common / "cdc/cdc_rst_ctrlr.sv"),
                str(TOP / "soc_common_cdc.sv"),
                str(TOP / "data_plane_fault_cdc.sv"),
                    str(PERIPHERAL / "pll_ctrl_if.sv"),
                    str(PERIPHERAL / "clock_ctrl_if.sv"),
                str(PERIPHERAL / "sysctrl_if.sv"),
                str(PERIPHERAL / "sysctrl_define.svh"),
                str(PERIPHERAL / "sysctrl_reg.sv"),
                str(PERIPHERAL / "sysctrl_core.sv"),
                str(PERIPHERAL / "apb4_sysctrl.sv"),
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
    assert "SystemCtrl register, lifecycle, fault, performance, RTC wake, and HP test passed" in (
        result.stdout
    )
