"""PIOLITE-P3 Tiny topology, USER GPIO and lifecycle integration checks."""
from __future__ import annotations

import json
from pathlib import Path

from scripts.check_clock_reset_domains import validate as validate_clocks
from scripts.generate_tiny import generate_bindings, read_topology

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def test_tiny_piolite_topology_and_capability(tmp_path: Path) -> None:
    topology = read_topology(TINY / "integration/soc_topology.json",
                             TINY / "address_map/memory_map.json")
    regions = {row["symbol"]: row for row in json.loads(
        (TINY / "address_map/memory_map.json").read_text())["regions"]}
    assert regions["APB4_PIOLITE"] == {
        "symbol": "APB4_PIOLITE", "base": "0x1001C000", "size": "0x00001000",
        "route": "apb4_periph", "kind": "active", "public": True, "user_access": "none",
    }
    assert topology["apb_targets"][-1] == {"name": "piolite", "regions": ["APB4_PIOLITE"]}
    assert topology["fabric"]["target_count"] == 31
    assert topology["fabric"]["decode_error_target"] == 29
    assert topology["fabric"]["protocol_error_target"] == 30
    assert {row["core_bit"] for row in topology["interrupts"] if row["name"] == "piolite"} == {24}

    generate_bindings(topology, tmp_path)
    constants = (tmp_path / "rtl/tiny_topology.svh").read_text()
    assert "`define RETROSOC_TINY__LEAF_COUNT 25" in constants
    assert "`define RETROSOC_TINY__TARGET_PIOLITE 28" in constants
    interfaces = (tmp_path / "rtl/tiny_apb_interfaces.svh").read_text()
    assert "tiny_peripheral_leaf u_piolite_lifecycle" in interfaces
    assert ".gate_i(s_gate_request[15])" in interfaces
    assert ".reset_i(s_local_reset[15])" in interfaces
    assert ".rst_n_i(s_leaf_rst_n[24])" in interfaces
    irq = (tmp_path / "include/retrosoc/generated/irq_metadata.h").read_text()
    assert "RS_SOC_IRQ_PIOLITE UINT32_C(24)" in irq
    assert "RS_SOC_EXT_IRQ_PIOLITE UINT32_C(22)" in irq
    features = (tmp_path / "include/retrosoc/generated/soc_features.h").read_text()
    assert "RS_SOC_HAS_PIOLITE 1U" in features


def test_piolite_clock_reset_inventory() -> None:
    inventory = json.loads((TINY / "integration/clock_reset_domains.json").read_text())
    assert inventory["reset_distribution"]["leaf_names"][-1] == "piolite"
    assert len(inventory["reset_distribution"]["leaf_names"]) == 25
    assert inventory["generated_apb_crossings"]["destinations"]["peripheral"][-1] == "piolite"
    validate_clocks(TINY / "integration/clock_reset_domains.json", ROOT)


def test_piolite_product_wiring_and_filelists() -> None:
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert "apb4_piolite u_piolite" in top
    assert ".filter_enable_i (u_user_gpio_if.filter_enable_i)" in top
    assert ".gpio_value_o    (u_user_gpio_if.do_o)" in top
    assert ".gpio_oe_o       (u_user_gpio_if.oe_o)" in top
    assert "s_periph_idle[15] = s_piolite_lifecycle_idle && !(|s_gpio_user_select)" in top
    assert "assign u_user_gpio_if.do_o" not in top
    assert "assign u_user_gpio_if.oe_o" not in top
    user_gpio = (ROOT / "rtl/ip/peripheral/user_gpio_if.sv").read_text()
    gpio_core = (ROOT / "rtl/ip/peripheral/gpio_core.sv").read_text()
    assert "input di_i, input filter_enable_i" in user_gpio
    assert "assign user_gpio.filter_enable_i = filter_enable_i" in gpio_core

    sources = (TINY / "filelist/ip.fl").read_text().splitlines()
    expected = [
        "piolite_pkg", "piolite_if", "piolite_imem", "piolite_fifo", "piolite_sm",
        "piolite_core", "piolite_gpio_guard", "piolite_dma_adapter", "piolite_reg", "apb4_piolite",
    ]
    positions = [sources.index(f"/ip/piolite/{name}.sv") for name in expected]
    assert positions == sorted(positions)
    assert "+incdir+/ip/piolite" in (TINY / "filelist/inc.fl").read_text().splitlines()
