"""Directed tests for the active AXI4 fabric adapters."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_axi42ribp_supports_bursts_backpressure_and_errors(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "axi42ribp_burst_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "axi42ribp_burst_tb",
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/mini/top/axi42ribp_burst.sv"),
            str(ROOT / "tests/rtl/axi42ribp_burst_tb.sv"),
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
    assert "AXI4 to RIBP burst bridge test passed" in result.stdout


def test_axi4_interconnect_classifies_decode_protocol_and_access_errors(
    tmp_path: Path,
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    memory_map = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    output = tmp_path / "axi4_interconnect_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "axi4_interconnect_tb",
            "-I" + str(memory_map / "rtl"),
            "-I" + str(ROOT / "rtl/mini/top"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/stream/round_robin_arbiter.sv"),
            str(ROOT / "rtl/mini/top/axi4_interconnect.sv"),
            str(ROOT / "rtl/mini/top/axi4_error_slave.sv"),
            str(ROOT / "tests/rtl/axi4_interconnect_tb.sv"),
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
    assert "AXI4 interconnect fault classification test passed" in result.stdout
