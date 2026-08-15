"""Tests for the canonical Mini SoC address-map generator."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "rtl/mini/address_map/generate_memory_map.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"
USER_EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions.json"
USER_GENERATOR = ROOT / "rtl/mini/integration/generate_user_extensions.py"


def generate(output_dir: Path, *, sram: str = "NO") -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(MEMORY_MAP),
            "--output-dir",
            str(output_dir),
            "--have-sram-if",
            sram,
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(USER_GENERATOR),
            "--map",
            str(USER_EXTENSIONS),
            "--output-dir",
            str(output_dir / "user_extensions"),
        ],
        check=True,
    )


def test_generated_artifacts_share_the_capacity_baseline(tmp_path: Path) -> None:
    generate(tmp_path, sram="YES")

    rtl = (tmp_path / "rtl/mmap_define.svh").read_text(encoding="utf-8")
    header = (tmp_path / "include/retrosoc/generated/memory_map.h").read_text(encoding="utf-8")
    linker = (tmp_path / "linker/memory_regions.ld").read_text(encoding="utf-8")

    assert "`define SOC_ADDR_PSRAM_END  32'h41FFFFFF" in rtl
    assert "`define SOC_ADDR_XPI_END  32'h5FFFFFFF" in rtl
    assert "`define SOC_ADDR_IS_FLASH(addr) ((addr) <= `SOC_ADDR_FLASH_END)" in rtl
    assert "`define CPU_RESET_ADDR `SOC_CPU_RESET_ADDR" in rtl
    assert "`define SOC_ADDR_IS_RESERVED(addr)" in rtl
    assert "RS_SOC_PSRAM_SIZE UINT32_C(0x02000000)" in header
    assert "RS_SOC_SDRAM_SIZE UINT32_C(0x04000000)" in header
    assert "RS_SOC_SPISD_SIZE UINT32_C(0x40000000)" in header
    assert "#ifdef __ASSEMBLER__" in header
    assert "#define UINT32_C(value) value" in header
    assert "RS_SOC_RIBP_SDIO_BASE" not in header
    assert "RS_SOC_NMI_" not in header
    assert "RS_SOC_OPIPSRAM_BASE" not in header
    assert "RS_SOC_HAS_SRAM 1U" in header
    assert "SOC_SYSCTRL_PLL_CFG_OFFSET      32'h00000008" in rtl
    assert "SOC_SYSCTRL_PLL_STATUS_OFFSET   32'h0000001C" in rtl
    assert "SOC_SYSCTRL_TEST_STATUS_OFFSET  32'h00000084" in rtl
    assert "SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET 32'h00000088" in rtl
    assert "SOC_ADDR_IS_RIBP(addr)" in rtl
    assert "SOC_ADDR_IS_NMI" not in rtl
    user_policy = rtl.split("`define SOC_USER_ADDR_READABLE", 1)[1].split(
        "`define SOC_ADDR_INCR4_CAPABLE", 1
    )[0]
    assert "SOC_ADDR_IS_APB_RNG" not in user_policy
    assert "RS_SOC_SYSCTRL_PLL_CFG_OFFSET UINT32_C(0x00000008)" in header
    assert "RS_SOC_SYSCTRL_PLL_STATUS_OFFSET UINT32_C(0x0000001C)" in header
    assert "RS_SOC_SYSCTRL_TEST_STATUS_OFFSET UINT32_C(0x00000084)" in header
    assert "RS_SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET UINT32_C(0x00000088)" in header
    assert "PSRAM (wxa!ri) : ORIGIN = 0x40000000, LENGTH = 0x02000000" in linker


def test_user_ip_is_always_emitted_for_the_fixed_platform(tmp_path: Path) -> None:
    generate(tmp_path)

    rtl = (tmp_path / "rtl/mmap_define.svh").read_text(encoding="utf-8")
    header = (tmp_path / "include/retrosoc/generated/memory_map.h").read_text(encoding="utf-8")

    expected_apb_bases = {
        "ARCHINFO": "20000000",
        "RNG": "20001000",
        "PWM": "20002000",
        "PS2": "20003000",
        "RTC": "20004000",
        "WDG": "20005000",
        "CRC": "20006000",
        "USER_IP": "20007000",
    }
    for symbol, base in expected_apb_bases.items():
        assert f"`define SOC_ADDR_APB_{symbol}_BASE 32'h{base}" in rtl
        assert f"#define RS_SOC_APB_{symbol}_BASE UINT32_C(0x{base})" in header
    assert "APB_UART1" not in rtl
    assert "APB_UART1" not in header
    assert "APB_TMR" not in rtl
    assert "APB_TMR" not in header


def test_bootstrap_assembly_uses_the_generated_gpio_admin_base() -> None:
    for source in (ROOT / "crt/arch/riscv/startup.S", ROOT / "app/asm/hello.s"):
        text = source.read_text(encoding="utf-8")
        assert '#include "retrosoc/generated/memory_map.h"' in text
        assert "RS_SOC_RIBP_GPIO_ADMIN_BASE + 0x34" in text
        assert "RS_SOC_RIBP_GPIO_ADMIN_BASE + 0x38" in text
        assert "RS_SOC_RIBP_PSRAM_BASE + 0x08" in text
        assert "0x10000028" not in text
        assert "0x1000002c" not in text


def test_map_validation_rejects_overlaps(tmp_path: Path) -> None:
    document = json.loads(MEMORY_MAP.read_text(encoding="utf-8"))
    document["regions"][1]["base"] = document["regions"][0]["base"]
    invalid_map = tmp_path / "overlap.json"
    invalid_map.write_text(json.dumps(document), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(GENERATOR), "--map", str(invalid_map), "--check"],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "address-map overlap" in result.stderr


def test_bus_fault_responder_handles_reserved_and_unmapped_addresses(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    generate(tmp_path)
    simulation = tmp_path / "bus_fault_tb"
    source_list = tmp_path / "bus_fault.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{tmp_path / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ram_if.sv"),
                str(ROOT / "rtl/mini/top/rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/mini/top/ribp2rib.sv"),
                str(ROOT / "rtl/mini/top/rib2ribp.sv"),
                str(ROOT / "rtl/mini/top/rib_error_slave.sv"),
                str(ROOT / "rtl/mini/top/rib2ram.sv"),
                str(ROOT / "rtl/mini/top/rib_bus.sv"),
                str(ROOT / "tests/rtl/bus_fault_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "bus_fault_tb.v"
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
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "bus_fault_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "bus fault responder test passed" in result.stdout


def test_sysctrl_fault_registers_record_and_clear_pending(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    generate(tmp_path)
    source_list = tmp_path / "sysctrl_fault.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{tmp_path / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv"),
                str(ROOT / "rtl/ip/peripheral/pll_ctrl_if.sv"),
                str(ROOT / "rtl/ip/peripheral/ribp_sysctrl.sv"),
                str(ROOT / "tests/rtl/sysctrl_fault_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "sysctrl_fault_tb.v"
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
    simulation = tmp_path / "sysctrl_fault_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "sysctrl_fault_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sysctrl fault, user core control, and RTC wake test passed" in result.stdout


def test_pll_controller_reconfigures_and_falls_back_to_the_safe_clock(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    generate(tmp_path)
    source_list = tmp_path / "pll_ctrl.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                "+define+PDK_BEHAV",
                "+define+HAVE_PLL",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{tmp_path / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_rst_ctrlr.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst/counter.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/edge_det.sv"),
                str(ROOT / "rtl/ip/peripheral/pll_ctrl_if.sv"),
                str(ROOT / "rtl/ip/peripheral/clint_timebase.sv"),
                str(ROOT / "rtl/ip/peripheral/ribp_sysctrl.sv"),
                str(ROOT / "rtl/tech/tc_clk.sv"),
                str(ROOT / "rtl/tech/tc_pll.sv"),
                str(ROOT / "rtl/mini/top/rcu.sv"),
                str(ROOT / "rtl/mini/top/pll_rcu_controller.sv"),
                str(ROOT / "tests/rtl/pll_ctrl_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "pll_ctrl_tb.v"
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
    simulation = tmp_path / "pll_ctrl_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "pll_ctrl_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "pll controller dynamic configuration test passed" in result.stdout
    result = subprocess.run(
        [vvp, str(simulation), "+pll_lock_fail"], text=True, capture_output=True, check=True
    )
    assert "pll controller timeout test passed" in result.stdout

    unsupported_list = tmp_path / "pll_unsupported.fl"
    unsupported_list.write_text(
        source_list.read_text(encoding="utf-8").replace("+define+HAVE_PLL\n", ""),
        encoding="utf-8",
    )
    unsupported_converted = tmp_path / "pll_unsupported_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(unsupported_list),
            "--output",
            str(unsupported_converted),
        ],
        check=True,
    )
    unsupported_simulation = tmp_path / "pll_unsupported_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "pll_ctrl_tb",
            "-o",
            str(unsupported_simulation),
            str(unsupported_converted),
        ],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(unsupported_simulation)], text=True, capture_output=True, check=True
    )
    assert "pll controller capability gate test passed" in result.stdout


def test_sysctrl_does_not_expose_unused_i2c_or_qspi_select_registers() -> None:
    rtl = (ROOT / "rtl/ip/peripheral/ribp_sysctrl.sv").read_text(encoding="utf-8")
    header = (ROOT / "crt/include/retrosoc/core/soc.h").read_text(encoding="utf-8")

    for symbol in (
        "SYSCTRL_I2CSEL",
        "SYSCTRL_QSPISEL",
        "i2c_sel_o",
        "qspi_sel_o",
        "s_sysctrl_i2csel",
        "s_sysctrl_qspisel",
    ):
        assert symbol not in rtl
    assert "reg_sysctrl_i2csel" not in header
    assert "reg_sysctrl_qspicsel" not in header
