"""Directed GA2D Phase 2 fabric and lifecycle verification."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_ga2d_p2_preserves_deferred_apb_irq_and_payload_boundaries() -> None:
    memory_map = json.loads(
        (ROOT / "rtl/mini/address_map/memory_map.json").read_text(encoding="utf-8")
    )
    regions = {region["symbol"]: region for region in memory_map["regions"]}
    topology = json.loads(
        (ROOT / "rtl/mini/integration/soc_topology.json").read_text(encoding="utf-8")
    )
    apb4_system = (ROOT / "rtl/mini/top/apb4_system.sv").read_text(encoding="utf-8")
    top = (ROOT / "rtl/mini/top/retrosoc.sv").read_text(encoding="utf-8")

    assert regions["APB4_GA"] == {
        "symbol": "APB4_GA",
        "base": "0x10012000",
        "size": "0x00001000",
        "route": "reserved",
        "kind": "reserved",
        "public": False,
        "user_access": "none",
    }
    assert all("ga2d" not in interrupt["name"].lower() for interrupt in topology["interrupts"])
    assert not list((ROOT / "rtl/ip/multimedia").glob("ga2d_*.sv"))
    assert ".ResourceCount(9)" in apb4_system
    assert "1'b0, resource_irq_i[6:5], s_ext_h_irq_raw, resource_irq_i[4:0]" in apb4_system
    assert "resource_irq_lp_o     = {s_resource_irq_lp[7:6], s_resource_irq_lp[4:0]}" in apb4_system
    assert "s_ga2d_source_safe_idle && s_resource_idle_pclk[8]" in top
    assert "s_ga2d_source_safe_idle && s_resource_block_ack_pclk[8]" in top


def test_ga2d_p2_bridge_prefix_lifecycle_and_recovery(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

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
    assert "GA2D P2 bridge, ID7, lifecycle, flush, and reset test passed" in result.stdout
