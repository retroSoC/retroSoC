"""Tests for the generated Mini SoC internal integration bindings."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOPOLOGY = ROOT / "rtl/mini/integration/soc_topology.json"
GENERATOR = ROOT / "rtl/mini/integration/generate_soc_topology.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"
MEMORY_MAP_GENERATOR = ROOT / "rtl/mini/address_map/generate_memory_map.py"


def generate(output_dir: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(TOPOLOGY),
            "--memory-map",
            str(MEMORY_MAP),
            "--output-dir",
            str(output_dir),
        ],
        check=True,
    )


def validate(topology: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(topology),
            "--memory-map",
            str(MEMORY_MAP),
            "--check",
        ],
        text=True,
        capture_output=True,
    )


def write_invalid_topology(tmp_path: Path, document: dict[str, object]) -> Path:
    path = tmp_path / "invalid_topology.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def test_topology_generates_complete_rib_apb_and_gpio_bindings(tmp_path: Path) -> None:
    generate(tmp_path)

    interfaces = (tmp_path / "rtl/apb4_periph_interfaces.svh").read_text(encoding="utf-8")
    routes = (tmp_path / "rtl/apb4_periph_select_routes.svh").read_text(encoding="utf-8")
    gpio = (tmp_path / "rtl/soc_gpio_alt_bindings.svh").read_text(encoding="utf-8")
    apb_interfaces = (tmp_path / "rtl/apb4_system_interfaces.svh").read_text(encoding="utf-8")
    apb_declarations = (tmp_path / "rtl/apb4_system_declarations.svh").read_text(encoding="utf-8")
    apb_routes = (tmp_path / "rtl/apb4_system_request_routes.svh").read_text(encoding="utf-8")
    apb_response = (tmp_path / "rtl/apb4_system_response_mux.svh").read_text(encoding="utf-8")
    fabric = (tmp_path / "rtl/soc_fabric_interfaces.svh").read_text(encoding="utf-8")
    bus_fabric = (tmp_path / "rtl/soc_bus_fabric.svh").read_text(encoding="utf-8")
    apb_system_fabric = (tmp_path / "rtl/apb4_system_fabric.svh").read_text(encoding="utf-8")
    apb_periph_fabric = (tmp_path / "rtl/apb4_periph_fabric.svh").read_text(encoding="utf-8")
    irq_config = (tmp_path / "rtl/soc_irq_config.svh").read_text(encoding="utf-8")
    rib_irq = (tmp_path / "rtl/apb4_periph_irq_bindings.svh").read_text(encoding="utf-8")
    apb_irq = (tmp_path / "rtl/apb4_system_irq_bindings.svh").read_text(encoding="utf-8")
    irq_wiring = (tmp_path / "rtl/soc_irq_wiring.svh").read_text(encoding="utf-8")
    irq_sva = (tmp_path / "rtl/soc_irq_sva.svh").read_text(encoding="utf-8")
    filelist = (tmp_path / "soc_topology.fl").read_text(encoding="utf-8")

    assert interfaces.count("apb4_if u_") == 24
    assert "nmi_if" not in interfaces
    assert "soc_nmi" not in interfaces
    assert "assign s_psel_comb[17] = `SOC_ADDR_IS_APB4_I2C1(s_decode_addr);" in routes
    assert "assign s_psel_comb[1] = `SOC_ADDR_IS_APB4_GPIO(s_decode_addr) || `SOC_ADDR_IS_APB4_GPIO_ADMIN(s_decode_addr);" in routes
    assert "SOC_ADDR_FLASH" not in routes
    assert "assign s_psel_comb[15] = `SOC_ADDR_IS_APB4_SDIO0(s_decode_addr);" in routes
    assert "assign s_psel_comb[16] = `SOC_ADDR_IS_APB4_OPIPSRAM(s_decode_addr);" in routes
    assert "assign s_psel_comb[18] = `SOC_ADDR_IS_APB4_SDIO1(s_decode_addr);" in routes
    assert "assign s_psel_comb[19] = `SOC_ADDR_IS_APB4_CRYPTO(s_decode_addr);" in routes
    assert "assign s_psel_comb[20] = `SOC_ADDR_IS_APB4_USB2(s_decode_addr);" in routes
    assert "assign s_psel_comb[22] = `SOC_ADDR_IS_APB4_UART1(s_decode_addr);" in routes
    assert "assign s_psel_comb[23] = `SOC_ADDR_IS_APB4_HP_MAILBOX(s_decode_addr);" in routes
    assert "assign s_psel_comb[24] = `SOC_ADDR_IS_HP_ACLINT(s_decode_addr);" in routes
    assert "assign s_psel_comb[25] = `SOC_ADDR_IS_HP_PLIC(s_decode_addr);" in routes
    assert gpio.count("// GPIO") == 64
    assert "u_uart1_if" not in gpio
    assert "assign u_uart0_if.cts_n_i = u_gpio_if.di_i[0];" in gpio
    assert "assign u_gpio_if.alt0_do_i[0] = 1'b0;" in gpio
    assert "assign u_gpio_if.alt0_oe_i[0] = 1'b0;" in gpio
    assert "assign u_gpio_if.alt0_do_i[1] = u_uart0_if.rts_n_o;" in gpio
    assert "assign u_gpio_if.alt0_oe_i[1] = 1'b1;" in gpio
    assert "assign u_gpio_if.alt0_do_i[15] = u_sdio0_if.sck_o;" in gpio
    assert "assign u_sdio0_if.cmd_di_i = u_gpio_if.di_i[16];" in gpio
    assert "assign u_gpio_if.alt1_do_i[0] = u_ps2_if.ps2_clk_o;" in gpio
    assert "assign u_gpio_if.alt1_oe_i[0] = u_ps2_if.ps2_clk_oe_o;" in gpio
    assert "assign u_gpio_if.alt1_do_i[1] = u_ps2_if.ps2_dat_o;" in gpio
    assert "assign u_gpio_if.alt1_oe_i[1] = u_ps2_if.ps2_dat_oe_o;" in gpio
    assert "assign u_gpio_if.alt1_do_i[2] = u_ws2812_if.dat_o;" in gpio
    assert "assign u_pwm_if.sync_i = u_gpio_if.di_i[2];" in gpio
    assert "assign u_gpio_if.alt0_do_i[3] = u_pwm_if.pwm_o[0];" in gpio
    assert "assign u_gpio_if.alt0_oe_i[3] = u_pwm_if.oe_o[0];" in gpio
    assert "assign u_pwm_if.fault_i = u_gpio_if.di_i[9];" in gpio
    assert "assign u_pwm_if.capture_i[0] = u_gpio_if.di_i[30];" in gpio
    assert "assign u_pwm_if.capture_i[1] = u_gpio_if.di_i[31];" in gpio
    assert "assign u_gpio_if.alt1_do_i[22] = u_psram_if.nss_o[0];" in gpio
    assert "assign u_gpio_if.alt0_do_i[21] = u_opipsram_if.ck_o;" in gpio
    assert "assign u_gpio_if.alt0_do_i[22] = u_opipsram_if.cs_n_o;" in gpio
    assert "assign u_opipsram_if.dq_i[6] = u_gpio_if.di_i[29];" in gpio
    assert "assign u_gpio_if.alt0_oe_i[29] = u_opipsram_if.dq_oe_o[6];" in gpio
    assert "assign u_opipsram_if.rwds_i = u_gpio_if.di_i[31];" in gpio
    assert "assign u_gpio_if.alt0_do_i[31] = u_opipsram_if.rwds_o;" in gpio
    assert "s_tmr_capch" not in gpio
    assert apb_interfaces.count("apb4_if u_") == 8
    assert "apb4_pure_if u_archinfo_apb4_pure_if ();" in apb_interfaces
    assert "assign user_ip.paddr = s_addr_q;" in apb_routes
    assert "({32{s_psel_q[7]}} & user_ip.prdata)" in apb_response
    assert "localparam int NSLV = 8;" in apb_declarations
    assert fabric.count("axi4_if #(") == 8
    assert ".mgmt_axi4(u_mgmt_axi4_if)" in bus_fabric
    assert ".user_axi4(u_user_axi4_if)" in bus_fabric
    assert ".dma_axi4(u_dma_axi4_if)" in bus_fabric
    assert ".sdio0_axi4(u_sdio0_axi4_if)" in bus_fabric
    assert ".sdio1_axi4(u_sdio1_axi4_if)" in bus_fabric
    assert ".usb2_axi4(u_usb2_axi4_if)" in bus_fabric
    assert ".cfg_axi4(u_cfg_axi4_if)" in bus_fabric
    assert ".system_axi4(u_system_axi4_if)" in bus_fabric
    assert ".axi4(u_system_axi4_if)" in apb_system_fabric
    assert ".usb2_axi4(u_usb2_axi4_if)" in apb_periph_fabric
    assert "`define SOC_IRQ_VECTOR_WIDTH 32" in irq_config
    assert "`define SOC_USER_IRQ_MASK 32'h004EFBFC" in irq_config
    assert "`define SOC_IRQ_APB4_PERIPH_WIDTH 22" in irq_config
    assert "`define SOC_IRQ_APB4_SYSTEM_WIDTH 5" in irq_config
    assert "assign irq_o[0] = u_clint_if.software_irq_o[0];" in rib_irq
    assert "assign irq_o[10] = ws2812.irq_o;" in rib_irq
    assert "assign irq_o[11] = gpio.irq_o;" in rib_irq
    assert "assign irq_o[12] = i2c1.irq_o;" in rib_irq
    assert "assign irq_o[13] = s_dvp_irq;" in rib_irq
    assert "assign irq_o[14] = s_dma_irq;" in rib_irq
    assert "assign irq_o[15] = opipsram.irq_o;" in rib_irq
    assert "assign irq_o[16] = sdio0.irq_o;" in rib_irq
    assert "assign irq_o[17] = sdio1.irq_o;" in rib_irq
    assert "assign irq_o[18] = s_crypto_irq;" in rib_irq
    assert "assign irq_o[19] = s_usb2_irq;" in rib_irq
    assert "assign irq_o[0] = pwm.irq_o;" in apb_irq
    assert "assign irq_o[4] = s_rng_irq;" in apb_irq
    assert "s_irq[10] = s_apb4_periph_irq[16];" in irq_wiring
    assert "s_irq[15] = s_apb4_periph_irq[13];" in irq_wiring
    assert "s_irq[16] = s_apb4_system_irq[4];" in irq_wiring
    assert "s_irq[20] = s_apb4_periph_irq[14];" in irq_wiring
    assert "s_irq[22] = s_apb4_periph_irq[15];" in irq_wiring
    assert "s_irq[21] = s_apb4_periph_irq[17];" in irq_wiring
    assert "s_irq[23] = s_apb4_periph_irq[18];" in irq_wiring
    assert "s_irq[24] = s_apb4_periph_irq[19];" in irq_wiring
    assert "irq_i[10] == apb4_periph_irq_i[16]" in irq_sva
    assert "irq_i[15] == apb4_periph_irq_i[13]" in irq_sva
    assert "irq_i[20] == apb4_periph_irq_i[14]" in irq_sva
    assert "irq_i[22] == apb4_periph_irq_i[15]" in irq_sva
    assert "irq_i[21] == apb4_periph_irq_i[17]" in irq_sva
    assert "irq_i[23] == apb4_periph_irq_i[18]" in irq_sva
    assert "irq_i[24] == apb4_periph_irq_i[19]" in irq_sva
    assert "irq_i[31] == 1'b0" in irq_sva
    assert "bind retrosoc soc_irq_topology_sva" in irq_sva
    assert filelist.startswith("+incdir+")


def test_topology_preserves_default_irq_compatibility_mapping() -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    assert document["irq_vector_width"] == 32
    mappings = [
        (
            interrupt["name"],
            interrupt["group"],
            interrupt["group_bit"],
            interrupt["core_bit"],
            interrupt["signal"],
        )
        for interrupt in document["interrupts"]
    ]
    assert mappings == [
        ("clint_software", "apb4_periph", 0, 0, "u_clint_if.software_irq_o[0]"),
        ("clint_timer", "apb4_periph", 1, 1, "u_clint_if.timer_irq_o[0]"),
        ("uart0", "apb4_periph", 2, 2, "uart.irq_o"),
        ("timer0", "apb4_periph", 3, 3, "s_tim0_irq"),
        ("timer1", "apb4_periph", 4, 4, "s_tim1_irq"),
        ("psram", "apb4_periph", 5, 5, "psram.irq_o"),
        ("spisd", "apb4_periph", 6, 6, "spisd.irq_o"),
        ("i2c0", "apb4_periph", 7, 7, "i2c0.irq_o"),
        ("i2s", "apb4_periph", 8, 8, "i2s.irq_o"),
        ("xpi", "apb4_periph", 9, 9, "s_xpi_irq"),
        ("sdio0", "apb4_periph", 16, 10, "sdio0.irq_o"),
        ("pwm", "apb4_system", 0, 11, "pwm.irq_o"),
        ("ps2", "apb4_system", 1, 12, "ps2.irq_o"),
        ("rtc", "apb4_system", 2, 13, "u_rtc_if.irq_o"),
        ("watchdog_early_warning", "apb4_system", 3, 14, "u_wdg_if.irq_o"),
        ("rng", "apb4_system", 4, 16, "s_rng_irq"),
        ("ws2812", "apb4_periph", 10, 17, "ws2812.irq_o"),
        ("gpio", "apb4_periph", 11, 18, "gpio.irq_o"),
        ("i2c1", "apb4_periph", 12, 19, "i2c1.irq_o"),
        ("dvp", "apb4_periph", 13, 15, "s_dvp_irq"),
        ("dma", "apb4_periph", 14, 20, "s_dma_irq"),
        ("opipsram", "apb4_periph", 15, 22, "opipsram.irq_o"),
        ("sdio1", "apb4_periph", 17, 21, "sdio1.irq_o"),
        ("crypto", "apb4_periph", 18, 23, "s_crypto_irq"),
        ("usb2", "apb4_periph", 19, 24, "s_usb2_irq"),
        ("hp_mailbox_lp", "apb4_periph", 20, 25, "s_mailbox_lp_irq"),
        ("uart1", "apb4_periph", 21, 26, "uart1.irq_o"),
    ]


def test_topology_always_adds_the_user_apb_target(tmp_path: Path) -> None:
    generate(tmp_path)

    interfaces = (tmp_path / "rtl/apb4_system_interfaces.svh").read_text(encoding="utf-8")
    declarations = (tmp_path / "rtl/apb4_system_declarations.svh").read_text(encoding="utf-8")
    response = (tmp_path / "rtl/apb4_system_response_mux.svh").read_text(encoding="utf-8")
    formal_design = (ROOT / "rtl/mini/formal/rib2apb_formal.sv").read_text(encoding="utf-8")
    formal_properties = (ROOT / "rtl/mini/formal/rib2apb_formal_props.sv").read_text(
        encoding="utf-8"
    )

    assert "apb4_if u_user_ip_apb4_if (clk_i, rst_n_i);" in interfaces
    assert "localparam int NSLV = 8;" in declarations
    assert "s_psel_q[7]" in response
    assert "apb4_pure_if user_ip ();" in formal_design
    assert ".user_ip (user_ip)" in formal_design
    assert "logic [ 7:0] psel_comb" in formal_design
    assert "wire [ 7:0] psel_comb" in formal_properties


def test_topology_rejects_unknown_or_non_rib_regions(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_periph_targets"][0]["regions"] = ["UNKNOWN"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "unknown region" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_periph_targets"][0]["regions"] = ["SRAM"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "not an active apb4_periph region" in result.stderr


def test_topology_rejects_duplicate_region_and_disabled_owner(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_periph_targets"][1]["regions"] = ["APB4_UART0"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "multiple targets" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_periph_targets"][15]["disabled"] = True
    document["apb4_periph_targets"][15]["regions"] = ["APB4_SDIO0"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "disabled but declares regions" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["fabric_links"][1]["name"] = "mgmt"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "fabric role mgmt is duplicated" in result.stderr


def test_topology_rejects_invalid_apb_target_ownership(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_system_targets"][0]["region"] = "SRAM"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "not an active apb4_system region" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb4_system_targets"][7]["slot"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "apb4_system_targets target slot 0 is duplicated" in result.stderr


def test_topology_rejects_invalid_gpio_coverage_and_expression(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["gpio_alt_functions"][1]["pin"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "gpio pin 0 is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["gpio_alt_functions"].pop()
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "one entry for every GPIO pin" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["gpio_alt_functions"][0]["alt0"]["do"] = "left + right"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "scalar SystemVerilog reference or constant" in result.stderr


def test_topology_rejects_invalid_irq_groups_and_bindings(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["irq_groups"][1]["name"] = "apb4_periph"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group apb4_periph is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][1]["group_bit"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group apb4_periph bit 0 is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][1]["core_bit"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "core interrupt bit 0 is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    rng_index = next(
        index
        for index, interrupt in enumerate(document["interrupts"])
        if interrupt["name"] == "rng"
    )
    document["interrupts"].pop(rng_index)
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group apb4_system does not cover every group bit" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][0]["signal"] = "left | right"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "scalar SystemVerilog reference or constant" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][0]["signal"] = "uart.irq_o"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "core interrupt bit 0 must retain its compatibility binding" in result.stderr


def test_generated_irq_wiring_preserves_the_expected_core_vector(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    topology_output = tmp_path / "topology"
    generate(topology_output)
    simulation = tmp_path / "soc_irq_topology_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-I",
            str(topology_output / "rtl"),
            "-s",
            "soc_irq_topology_tb",
            "-o",
            str(simulation),
            str(ROOT / "tests/rtl/soc_irq_topology_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "SoC topology IRQ routing test passed" in result.stdout


def test_generated_rib_routes_select_and_return_the_expected_target(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return

    memory_map_output = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(MEMORY_MAP_GENERATOR),
            "--map",
            str(MEMORY_MAP),
            "--output-dir",
            str(memory_map_output),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    topology_output = tmp_path / "topology"
    generate(topology_output)

    source_list = tmp_path / "apb4_topology.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map_output / 'rtl'}",
                f"+incdir+{topology_output / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "tests/rtl/apb4_topology_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apb4_topology_tb.v"
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
    simulation = tmp_path / "apb4_topology_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apb4_topology_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "SoC topology APB4 routing test passed" in result.stdout
