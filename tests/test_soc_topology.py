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

    interfaces = (tmp_path / "rtl/soc_rib_interfaces.svh").read_text(encoding="utf-8")
    routes = (tmp_path / "rtl/soc_rib_routes.svh").read_text(encoding="utf-8")
    gpio = (tmp_path / "rtl/soc_gpio_alt_bindings.svh").read_text(encoding="utf-8")
    apb_interfaces = (tmp_path / "rtl/soc_apb_interfaces.svh").read_text(encoding="utf-8")
    apb_declarations = (tmp_path / "rtl/soc_apb_declarations.svh").read_text(encoding="utf-8")
    apb_routes = (tmp_path / "rtl/soc_apb_request_routes.svh").read_text(encoding="utf-8")
    apb_response = (tmp_path / "rtl/soc_apb_response_mux.svh").read_text(encoding="utf-8")
    fabric = (tmp_path / "rtl/soc_fabric_interfaces.svh").read_text(encoding="utf-8")
    bus_fabric = (tmp_path / "rtl/soc_bus_fabric.svh").read_text(encoding="utf-8")
    irq_config = (tmp_path / "rtl/soc_irq_config.svh").read_text(encoding="utf-8")
    rib_irq = (tmp_path / "rtl/soc_rib_irq_bindings.svh").read_text(encoding="utf-8")
    apb_irq = (tmp_path / "rtl/soc_apb_irq_bindings.svh").read_text(encoding="utf-8")
    irq_wiring = (tmp_path / "rtl/soc_irq_wiring.svh").read_text(encoding="utf-8")
    irq_sva = (tmp_path / "rtl/soc_irq_sva.svh").read_text(encoding="utf-8")
    filelist = (tmp_path / "soc_topology.fl").read_text(encoding="utf-8")

    assert interfaces.count("rib_if u_") == 18
    assert "nmi_if" not in interfaces
    assert "soc_nmi" not in interfaces
    assert "assign s_slv_sel_d[17] = u_i2c1_rib_if.valid;" in routes
    assert "assign s_xpi_region_sel[1] = (rib.addr <= `SOC_ADDR_FLASH_END);" in routes
    assert "assign u_sdio_rib_if.valid = 1'b0;" in routes
    assert gpio.count("// GPIO") == 64
    assert "assign u_uart1_if.rx_i = u_gpio_if.di_i[0];" in gpio
    assert "assign u_gpio_if.alt1_do_i[22] = u_psram_if.nss_o[0];" in gpio
    assert apb_interfaces.count("apb4_if u_") == 10
    assert "apb4_pure_if u_archinfo_apb_pure_if ();" in apb_interfaces
    assert "assign tmr.paddr = rib.addr;" in apb_routes
    assert "({32{s_psel_q[8]}} & tmr.prdata)" in apb_response
    assert "localparam int NSLV = 10;" in apb_declarations
    assert fabric.count("rib_if u_") == 5
    assert ".mgmt_rib(u_mgmt_rib_if)" in bus_fabric
    assert ".user_rib(u_user_rib_if)" in bus_fabric
    assert ".apb_rib(u_apb_rib_if)" in bus_fabric
    assert ".rib(u_rib_if)" in bus_fabric
    assert "`define SOC_IRQ_VECTOR_WIDTH 32" in irq_config
    assert "`define SOC_IRQ_RIB_WIDTH 10" in irq_config
    assert "`define SOC_IRQ_APB_WIDTH 7" in irq_config
    assert "assign irq_o[0] = u_clint_if.sfr_irq_o;" in rib_irq
    assert "assign irq_o[5] = u_tmr_if.irq_o;" in apb_irq
    assert "s_irq[16] = s_apb_irq[6];" in irq_wiring
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
    assert mappings[:17] == [
        ("clint_software", "rib", 0, 0, "u_clint_if.sfr_irq_o"),
        ("clint_timer", "rib", 1, 1, "u_clint_if.tmr_irq_o"),
        ("uart0", "rib", 2, 2, "uart.irq_o"),
        ("timer0", "rib", 3, 3, "s_tim0_irq"),
        ("timer1", "rib", 4, 4, "s_tim1_irq"),
        ("psram", "rib", 5, 5, "psram.irq_o"),
        ("spisd", "rib", 6, 6, "spisd.irq_o"),
        ("i2c0", "rib", 7, 7, "i2c0.irq_o"),
        ("i2s", "rib", 8, 8, "i2s.irq_o"),
        ("xpi", "rib", 9, 9, "xpi.irq_o"),
        ("uart1", "apb", 0, 10, "uart.irq_o"),
        ("pwm", "apb", 1, 11, "pwm.irq_o"),
        ("ps2", "apb", 2, 12, "ps2.irq_o"),
        ("rtc", "apb", 3, 13, "u_rtc_if.irq_o"),
        ("watchdog_reset", "apb", 4, 14, "u_wdg_if.rst_o"),
        ("advanced_timer", "apb", 5, 15, "u_tmr_if.irq_o"),
        ("reserved", "apb", 6, 16, "1'b0"),
    ]
    assert all(mapping[3] >= 17 for mapping in mappings[17:])


def test_topology_always_adds_the_user_apb_target(tmp_path: Path) -> None:
    generate(tmp_path)

    interfaces = (tmp_path / "rtl/soc_apb_interfaces.svh").read_text(encoding="utf-8")
    declarations = (tmp_path / "rtl/soc_apb_declarations.svh").read_text(encoding="utf-8")
    response = (tmp_path / "rtl/soc_apb_response_mux.svh").read_text(encoding="utf-8")
    formal_design = (ROOT / "rtl/mini/formal/rib2apb_formal.sv").read_text(encoding="utf-8")
    formal_properties = (ROOT / "rtl/mini/formal/rib2apb_formal_props.v").read_text(
        encoding="utf-8"
    )

    assert "apb4_if u_user_ip_apb_if (clk_i, rst_n_i);" in interfaces
    assert "localparam int NSLV = 10;" in declarations
    assert "s_psel_q[9]" in response
    assert "apb4_pure_if user_ip ();" in formal_design
    assert ".user_ip (user_ip)" in formal_design
    assert "logic [ 9:0] psel_comb" in formal_design
    assert "wire [ 9:0] psel_comb" in formal_properties


def test_topology_rejects_unknown_or_non_rib_regions(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["rib_targets"][0]["regions"] = ["UNKNOWN"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "unknown region" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["rib_targets"][0]["regions"] = ["SRAM"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "not an active rib region" in result.stderr


def test_topology_rejects_duplicate_region_and_disabled_owner(tmp_path: Path) -> None:
    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["rib_targets"][1]["regions"] = ["RIB_UART0"]
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "multiple targets" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["rib_targets"][15]["regions"] = ["RIB_SDIO"]
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
    document["apb_targets"][0]["region"] = "SRAM"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "not an active APB region" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["apb_targets"][8]["slot"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "APB target slot 0 is duplicated" in result.stderr


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
    document["irq_groups"][1]["name"] = "rib"
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group rib is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][1]["group_bit"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group rib bit 0 is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"][1]["core_bit"] = 0
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "core interrupt bit 0 is duplicated" in result.stderr

    document = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
    document["interrupts"].pop()
    result = validate(write_invalid_topology(tmp_path, document))
    assert result.returncode != 0
    assert "interrupt group apb does not cover every group bit" in result.stderr

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

    source_list = tmp_path / "soc_topology_rib.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map_output / 'rtl'}",
                f"+incdir+{topology_output / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/rib_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "tests/rtl/soc_topology_rib_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "soc_topology_rib_tb.v"
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
    simulation = tmp_path / "soc_topology_rib_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "soc_topology_rib_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "SoC topology RIB routing test passed" in result.stdout
