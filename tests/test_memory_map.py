"""Tests for the canonical Mini SoC address-map generator."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "rtl/mini/address_map/generate_memory_map.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"
USER_EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions.json"
USER_GENERATOR = ROOT / "rtl/mini/integration/generate_user_extensions.py"
BOOTER = ROOT / "crt/src/service/booter.c"


def generate(output_dir: Path, *, sram: str = "NO", sram_size_kib: int = 128) -> None:
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
            "--sram-size-kib",
            str(sram_size_kib),
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
    assert "`define SOC_ADDR_OPIPSRAM_END  32'h4FFFFFFF" in rtl
    assert "`define SOC_ADDR_XPI_END  32'h5FFFFFFF" in rtl
    assert "`define SOC_ADDR_IS_FLASH(addr) ((addr) <= `SOC_ADDR_FLASH_END)" in rtl
    assert "`define CPU_RESET_ADDR `SOC_CPU_RESET_ADDR" in rtl
    assert "`define SOC_ADDR_IS_RESERVED(addr)" in rtl
    assert "RS_SOC_PSRAM_SIZE UINT32_C(0x02000000)" in header
    assert "RS_SOC_OPIPSRAM_SIZE UINT32_C(0x08000000)" in header
    assert "RS_SOC_SDRAM_SIZE UINT32_C(0x04000000)" in header
    assert "RS_SOC_SPISD_SIZE UINT32_C(0x40000000)" in header
    assert "#ifdef __ASSEMBLER__" in header
    assert "#define UINT32_C(value) value" in header
    assert "RS_SOC_APB4_SDIO_BASE" not in header
    assert "RS_SOC_APB4_SDIO0_BASE UINT32_C(0x1000F000)" in header
    assert "RS_SOC_APB4_SDIO1_BASE UINT32_C(0x10015000)" in header
    assert "RS_SOC_APB4_USB2_BASE UINT32_C(0x10016000)" in header
    assert "RS_SOC_APB4_SRAM_BASE UINT32_C(0x10017000)" in header
    assert "RS_SOC_NMI_" not in header
    assert "RS_SOC_OPIPSRAM_BASE UINT32_C(0x48000000)" in header
    assert "RS_SOC_HAS_SRAM 1U" in header
    assert "SOC_SYSCTRL_PLL_CFG_OFFSET      32'h00000008" in rtl
    assert "SOC_SYSCTRL_PLL_STATUS_OFFSET   32'h0000001C" in rtl
    assert "SOC_SYSCTRL_TEST_STATUS_OFFSET  32'h00000084" in rtl
    assert "SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET 32'h00000088" in rtl
    assert "SOC_SYSCTRL_PERF_SDIO0_WAIT_LO_OFFSET 32'h0000008C" in rtl
    assert "SOC_SYSCTRL_PERF_SDIO0_WAIT_HI_OFFSET 32'h00000090" in rtl
    assert "SOC_SYSCTRL_PERF_SDIO1_WAIT_LO_OFFSET 32'h00000094" in rtl
    assert "SOC_SYSCTRL_PERF_SDIO1_WAIT_HI_OFFSET 32'h00000098" in rtl
    assert "SOC_SYSCTRL_PERF_USB2_WAIT_LO_OFFSET 32'h0000009C" in rtl
    assert "SOC_SYSCTRL_PERF_USB2_WAIT_HI_OFFSET 32'h000000A0" in rtl
    assert "SOC_ADDR_IS_APB4_PERIPH(addr)" in rtl
    assert "SOC_ADDR_IS_NMI" not in rtl
    user_policy = rtl.split("`define SOC_USER_ADDR_READABLE", 1)[1].split(
        "`define SOC_ADDR_INCR4_CAPABLE", 1
    )[0]
    assert "SOC_ADDR_IS_APB_RNG" not in user_policy
    assert "SOC_ADDR_IS_APB4_OPIPSRAM" not in user_policy
    assert "SOC_ADDR_IS_OPIPSRAM" in user_policy
    assert "RS_SOC_SYSCTRL_PLL_CFG_OFFSET UINT32_C(0x00000008)" in header
    assert "RS_SOC_SYSCTRL_PLL_STATUS_OFFSET UINT32_C(0x0000001C)" in header
    assert "RS_SOC_SYSCTRL_TEST_STATUS_OFFSET UINT32_C(0x00000084)" in header
    assert "RS_SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET UINT32_C(0x00000088)" in header
    assert "RS_SOC_SYSCTRL_PERF_SDIO0_WAIT_LO_OFFSET UINT32_C(0x0000008C)" in header
    assert "RS_SOC_SYSCTRL_PERF_SDIO0_WAIT_HI_OFFSET UINT32_C(0x00000090)" in header
    assert "RS_SOC_SYSCTRL_PERF_SDIO1_WAIT_LO_OFFSET UINT32_C(0x00000094)" in header
    assert "RS_SOC_SYSCTRL_PERF_SDIO1_WAIT_HI_OFFSET UINT32_C(0x00000098)" in header
    assert "RS_SOC_SYSCTRL_PERF_USB2_WAIT_LO_OFFSET UINT32_C(0x0000009C)" in header
    assert "RS_SOC_SYSCTRL_PERF_USB2_WAIT_HI_OFFSET UINT32_C(0x000000A0)" in header
    assert "PSRAM (wxa!ri) : ORIGIN = 0x40000000, LENGTH = 0x02000000" in linker
    assert "OPIPSRAM (wxa!ri) : ORIGIN = 0x48000000, LENGTH = 0x08000000" in linker


def test_booter_prints_every_public_active_mmio_region() -> None:
    document = json.loads(MEMORY_MAP.read_text(encoding="utf-8"))
    expected = {
        region["symbol"]
        for region in document["regions"]
        if region["kind"] == "active"
        and region.get("public") is True
        and region["route"] in {"apb4_periph", "apb4_system"}
    }
    booter = BOOTER.read_text(encoding="utf-8")
    mmio_function = booter.split("static void rs_print_mmio_map(void) {", 1)[1].split(
        "\n}", 1
    )[0]
    actual = set(re.findall(r"RS_SOC_([A-Z0-9_]+)_BASE", mmio_function))

    assert actual == expected
    assert "DMA(8CH)" in mmio_function
    assert "DMA(6CH)" not in mmio_function
    assert "RS_SOC_APB4_GA_BASE" not in mmio_function
    assert "RS_SOC_APB4_APU_BASE" in mmio_function


def test_sram_capacity_selects_one_consistent_hardware_software_window(tmp_path: Path) -> None:
    for size_kib in (4, 16, 32, 64, 128):
        output = tmp_path / str(size_kib)
        generate(output, sram="YES", sram_size_kib=size_kib)
        size = size_kib * 1024
        end = 0x30000000 + size - 1
        rtl = (output / "rtl/mmap_define.svh").read_text(encoding="utf-8")
        header = (output / "include/retrosoc/generated/memory_map.h").read_text(encoding="utf-8")
        linker = (output / "linker/memory_regions.ld").read_text(encoding="utf-8")

        assert f"`define SOC_ADDR_SRAM_SIZE 32'h{size:08X}" in rtl
        assert f"`define SOC_ADDR_SRAM_END  32'h{end:08X}" in rtl
        assert f"#define RS_SOC_SRAM_SIZE UINT32_C(0x{size:08X})" in header
        assert f"SRAM (wxa!ri) : ORIGIN = 0x30000000, LENGTH = 0x{size:08X}" in linker


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
        assert f"`define SOC_ADDR_APB4_{symbol}_BASE 32'h{base}" in rtl
        assert f"#define RS_SOC_APB4_{symbol}_BASE UINT32_C(0x{base})" in header
    assert "APB_UART1" not in rtl
    assert "APB_UART1" not in header
    assert "APB_TMR" not in rtl
    assert "APB_TMR" not in header
    assert "`define SOC_ADDR_APB4_OPIPSRAM_BASE 32'h10010000" in rtl
    assert "`define SOC_ADDR_IS_OPIPSRAM(addr)" in rtl
    assert "#define RS_SOC_APB4_OPIPSRAM_BASE UINT32_C(0x10010000)" in header
    assert "`define SOC_ADDR_APB4_SDIO0_BASE 32'h1000F000" in rtl
    assert "`define SOC_ADDR_APB4_SDIO1_BASE 32'h10015000" in rtl
    assert "`define SOC_ADDR_APB4_USB2_BASE 32'h10016000" in rtl
    assert "`define SOC_ADDR_APB4_APU_BASE 32'h10013000" in rtl
    assert "`define SOC_ADDR_APB4_CRYPTO_BASE 32'h1000C000" in rtl
    assert "#define RS_SOC_APB4_CRYPTO_BASE UINT32_C(0x1000C000)" in header
    assert "#define RS_SOC_APB4_USB2_BASE UINT32_C(0x10016000)" in header
    assert "#define RS_SOC_APB4_APU_BASE UINT32_C(0x10013000)" in header


def test_bootstrap_assembly_uses_the_generated_gpio_admin_base() -> None:
    for source in (ROOT / "crt/arch/riscv/startup.S", ROOT / "app/asm/hello.s"):
        text = source.read_text(encoding="utf-8")
        assert '#include "retrosoc/generated/memory_map.h"' in text
        assert "RS_SOC_APB4_GPIO_ADMIN_BASE + 0x34" in text
        assert "RS_SOC_APB4_GPIO_ADMIN_BASE + 0x38" in text
        assert "RS_SOC_APB4_PSRAM_BASE + 0x08" in text
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
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ram_if.sv"),
                str(ROOT / "rtl/mini/top/rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
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
                    "+define+MINI_PRODUCT",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{tmp_path / 'user_extensions' / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_rst_ctrlr.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv"),
                    str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst/counter.sv"),
                    str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst/clk_int_div.sv"),
                    str(ROOT / "rtl/managed/clusterip/common/rtl/clock/safe_clock_mux.sv"),
                    str(ROOT / "rtl/mini/top/soc_clock_gate.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/edge_det.sv"),
                    str(ROOT / "rtl/ip/peripheral/pll_ctrl_if.sv"),
                    str(ROOT / "rtl/ip/peripheral/clock_ctrl_if.sv"),
                str(ROOT / "rtl/ip/peripheral/clint_timebase.sv"),
                str(ROOT / "rtl/ip/peripheral/sysctrl_if.sv"),
                str(ROOT / "rtl/ip/peripheral/sysctrl_define.svh"),
                str(ROOT / "rtl/ip/peripheral/sysctrl_reg.sv"),
                str(ROOT / "rtl/ip/peripheral/sysctrl_core.sv"),
                str(ROOT / "rtl/ip/peripheral/apb4_sysctrl.sv"),
                str(ROOT / "rtl/tech/tc_clk.sv"),
                str(ROOT / "rtl/tech/tc_pll.sv"),
                    str(ROOT / "rtl/mini/top/rcu.sv"),
                    str(ROOT / "rtl/mini/top/pll_rcu_controller.sv"),
                    str(ROOT / "rtl/mini/top/clock_config_controller.sv"),
                    str(ROOT / "rtl/mini/top/clock_frequency_monitor.sv"),
                    str(ROOT / "rtl/mini/top/soc_clock_reset_subsystem.sv"),
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
    rtl = (ROOT / "rtl/ip/peripheral/sysctrl_core.sv").read_text(encoding="utf-8")
    header = (ROOT / "crt/include/retrosoc/hal/sysctrl.h").read_text(encoding="utf-8")

    for symbol in (
        "SYSCTRL_I2CSEL",
        "SYSCTRL_QSPISEL",
        "i2c_sel_o",
        "qspi_sel_o",
        "s_sysctrl_i2csel",
        "s_sysctrl_qspisel",
    ):
        assert symbol not in rtl
    assert "reg_sysctrl_" not in header


def test_hp_lifecycle_controller_drains_and_forces_bounded_reset(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "hp_lifecycle_controller_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "hp_lifecycle_controller_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/mini/top/hp_lifecycle_controller.sv"),
            str(ROOT / "tests/rtl/hp_lifecycle_controller_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "HP lifecycle drain, flush, and forced reset test passed" in result.stdout


def test_clock_frequency_monitor_detects_stop_and_restart(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "clock_frequency_monitor_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "clock_frequency_monitor_tb",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv"),
            str(ROOT / "rtl/mini/top/clock_frequency_monitor.sv"),
            str(ROOT / "tests/rtl/clock_frequency_monitor_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "Clock frequency activity and sticky fault test passed" in result.stdout
