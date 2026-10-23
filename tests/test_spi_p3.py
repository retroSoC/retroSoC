"""SPI-P3 Tiny topology, origin qualification, and SDK integration checks."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def test_tiny_spi_topology_and_capability() -> None:
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    memory = json.loads((TINY / "address_map/memory_map.json").read_text())
    regions = {row["symbol"]: row for row in memory["regions"]}
    assert regions["APB4_SPI"]["base"] == "0x1001D000"
    assert topology["fabric"]["target_count"] == 29
    assert topology["fabric"]["decode_error_target"] == 27
    assert topology["fabric"]["protocol_error_target"] == 28
    assert {row["core_bit"] for row in topology["interrupts"] if row["name"] == "spi"} == {25}
    assert any(row["name"] == "spi" and row["regions"] == ["APB4_SPI"]
               for row in topology["apb_targets"])
    assert topology["dma_request_mask"] == "0x339ff"


def test_tiny_spi_routes_and_lifecycle() -> None:
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    routes = {row["pin"]: row for row in topology["gpio_alt_functions"]}
    assert routes[27]["alt0"]["do"] == "s_spi_sck"
    assert routes[28]["alt1"]["do"] == "s_spi_mosi"
    assert routes[30]["alt1"]["inputs"] == ["s_spi_miso"]
    assert routes[31]["alt1"]["do"] == "s_spi_cs_n"
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert ".TargetMask (17'h17fff)" in top
    assert ".EnableSpi(1'b1)" in re.sub(r"\s+", "", top)
    assert ".EnableOriginQualifier" in top
    assert "s_periph_idle[16] = s_spi_lifecycle_idle" in top


def test_spi_origin_bridge_and_dma_alias_contract() -> None:
    bridge = (TINY / "top/tiny_axi42apb4.sv").read_text()
    async_bridge = (TINY / "top/tiny_apb_async_bridge.sv").read_text()
    target = (TINY / "top/tiny_axi4_target.sv").read_text()
    dma = (ROOT / "rtl/ip/peripheral/dma_core.sv").read_text()
    assert "origin_o" in bridge and "channel_o" in bridge
    assert "src_origin_i" in async_bridge and "dst_origin_o" in async_bridge
    assert "s_selected == 2'd1" in target and "4'b0100" in target
    assert "SpiTxAddress" in dma and "SpiRxAddress" in dma
    assert "s_cfg_dst_addr[channel] != SpiTxAddress" in dma
    assert "s_cfg_src_addr[channel] != SpiRxAddress" in dma


def test_spi_hal_is_bounded_and_discoverable() -> None:
    header = (ROOT / "crt/include/retrosoc/hal/spi.h").read_text()
    source = (ROOT / "crt/src/hal/spi.c").read_text()
    math = (ROOT / "crt/src/hal/spi_math.c").read_text()
    assert "rs_spi_probe" in header and "rs_spi_probe" in source
    assert "rs_spi_abort" in header and "rs_spi_recover" in header
    assert "rs_timeout_t timeout" in header
    assert "UINT64_C(2)" in math
    assert "RS_ENOTSUP" in source
