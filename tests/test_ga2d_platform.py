"""Directed GA2D Phase 2 fabric/lifecycle and Phase 5 datapath boundaries."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def test_ga2d_p5_preserves_the_real_private_axi64_master_and_irq_route() -> None:
    memory_map = json.loads(
        (ROOT / "rtl/mini/address_map/memory_map.json").read_text(encoding="utf-8")
    )
    regions = {region["symbol"]: region for region in memory_map["regions"]}
    topology = json.loads(
        (ROOT / "rtl/mini/integration/soc_topology.json").read_text(encoding="utf-8")
    )
    apb4_periph = (ROOT / "rtl/mini/top/apb4_periph.sv").read_text(encoding="utf-8")
    apb4_system = (ROOT / "rtl/mini/top/apb4_system.sv").read_text(encoding="utf-8")
    data_plane = (ROOT / "rtl/mini/top/soc_data_plane.sv").read_text(encoding="utf-8")
    top = (ROOT / "rtl/mini/top/retrosoc.sv").read_text(encoding="utf-8")

    assert "APB4_GA" not in regions
    assert regions["APB4_GA2D"] == {
        "symbol": "APB4_GA2D",
        "base": "0x10012000",
        "size": "0x00001000",
        "route": "apb4_periph",
        "kind": "active",
        "public": True,
        "user_access": "none",
    }
    assert topology["apb4_periph_targets"][-1] == {
        "slot": 28,
        "name": "ga2d",
        "timed_interface": "u_ga2d_apb4_if",
        "pure_interface": "u_ga2d_apb4_pure_if",
        "region": "APB4_GA2D",
    }
    assert topology["interrupts"][-1]["name"] == "ga2d"
    assert topology["interrupts"][-1]["group_bit"] == 24
    assert topology["interrupts"][-1]["core_bit"] == 32
    assert topology["interrupts"][-1]["signal"] == "resource_irq_lp_i[7]"
    assert {
        "ga2d_pkg.sv",
        "ga2d_addr_gen.sv",
        "ga2d_axi4_master.sv",
        "ga2d_dma.sv",
        "ga2d_pixel.sv",
        "ga2d_core.sv",
        "ga2d_reg.sv",
        "apb4_ga2d.sv",
    } <= {path.name for path in (ROOT / "rtl/ip/multimedia").glob("*ga2d*.sv")}
    assert ".ResourceCount(9)" in apb4_system
    assert "resource_irq_i[7]" in apb4_system
    assert "s_resource_irq_lp[8]" in apb4_system
    assert "s_hp_plic_source[11] = resource_irq_hp_i[7];" in apb4_periph
    assert "s_ga2d_idle && s_ga2d_source_safe_idle && s_resource_idle_pclk[8]" in top
    assert "s_ga2d_idle && s_ga2d_source_safe_idle && s_resource_block_ack_pclk[8]" in top
    assert "axi4_master_idle u_ga2d_master_idle" not in top
    assert "axi4_if.master" in apb4_periph
    assert "ga2d_axi4" in apb4_periph
    assert "ga2d_axi4" in top
    assert "core_safe_idle" in apb4_periph
    assert "assign s_ga2d_core_safe_idle = ga2d_core_safe_idle_i;" in data_plane
    lp_data_cdc = data_plane.split(") u_lp_data_cdc (", 1)[1].split(");", 1)[0]
    assert ".clear_i     (1'b0)" in lp_data_cdc
    assert "HP lifecycle flush invalidates HP transport" in lp_data_cdc


def test_ga2d_p5_preserves_p2_bridge_prefix_lifecycle_and_recovery(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        pytest.fail("GA2D P5 platform lifecycle test requires Verilator")

    topology = tmp_path / "topology"
    memory_map = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/integration/generate_soc_topology.py"),
            "--map",
            str(ROOT / "rtl/mini/integration/soc_topology.json"),
            "--memory-map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(topology),
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "YES",
            "--sram-size-kib",
            "32",
        ],
        check=True,
    )

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    top = ROOT / "rtl/mini/top"
    output = tmp_path / "ga2d_platform_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "ga2d_platform_tb",
            "-I" + str(topology / "rtl"),
            "-I" + str(memory_map / "rtl"),
            "-I" + str(common),
            "-I" + str(common / "cdc"),
            "-I" + str(common / "interface"),
            str(common / "interface/apb4_if.sv"),
            str(common / "interface/axi4_if.sv"),
            str(common / "interface/axi4_addr_gen.sv"),
            str(common / "utils/register.sv"),
            str(common / "utils/fifo.sv"),
            str(common / "utils/xchecker.sv"),
            str(common / "utils/spill_register.sv"),
            str(common / "utils/bin2gray.sv"),
            str(common / "utils/gray2bin.sv"),
            str(common / "stream/round_robin_arbiter.sv"),
            str(common / "cdc/cdc_sync.sv"),
            str(common / "cdc/cdc_rst_ctrlr.sv"),
            str(common / "cdc/cdc_2phase.sv"),
            str(common / "clkrst/rst_sync.sv"),
            str(top / "soc_common_cdc.sv"),
            str(top / "axi4_connector.sv"),
            str(top / "axi4_master_idle.sv"),
            str(top / "axi4_async_bridge.sv"),
            str(top / "axi4_address_gate.sv"),
            str(top / "axi4_upsizer_32to64.sv"),
            str(top / "axi4_id_prefix.sv"),
            str(top / "axi4_data_crossbar.sv"),
            str(top / "axi4_target_guard.sv"),
            str(top / "fabric_monitor.sv"),
            str(top / "axi4_error_slave.sv"),
            str(top / "axi4_downsizer_64to32.sv"),
            str(top / "hp_axi4_mux3.sv"),
            str(top / "soc_data_plane.sv"),
            str(ROOT / "tests/rtl/ga2d_platform_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj"),
            "-o",
            str(output),
        ],
        check=True,
        text=True,
        capture_output=True,
        env={
            **os.environ,
            "CCACHE_DIR": str(ccache_tmp),
            "CCACHE_TEMPDIR": str(ccache_tmp),
        },
    )
    result = subprocess.run([output], check=True, text=True, capture_output=True)
    assert "GA2D P2 bridge, ID7, lifecycle, flush, LP retention, and reset test passed" in result.stdout
