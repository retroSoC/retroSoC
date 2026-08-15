"""Directed tests for the ESP-PSRAM64H controller and its handwritten ABI."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_psram_controller_data_integrity_and_fault_isolation(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    generated = tmp_path / "generated"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    output = tmp_path / "psram_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "psram_tb",
            "-I" + str(generated / "rtl"),
            "-I" + str(ROOT / "rtl/ip/memory"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ribp_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/ip/memory/psram_pkg.sv"),
            str(ROOT / "rtl/ip/memory/psram_axi4.sv"),
            str(ROOT / "rtl/ip/memory/psram_core.sv"),
            str(ROOT / "rtl/ip/memory/psram_phy.sv"),
            str(ROOT / "rtl/ip/memory/psram_reg.sv"),
            str(ROOT / "rtl/ip/memory/ribp_psram.sv"),
            str(ROOT / "rtl/mini/dv/model/ESP_PSRAM64H.sv"),
            str(ROOT / "tests/rtl/psram_tb.sv"),
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
    assert "PSRAM controller integration test passed" in result.stdout


def test_psram_handwritten_register_offsets_match_hal() -> None:
    rtl_text = (ROOT / "rtl/ip/memory/psram_define.svh").read_text(encoding="utf-8")
    hal_text = (ROOT / "crt/src/hal/psram.c").read_text(encoding="utf-8")
    rtl_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"`define\s+RIBP_PSRAM_([A-Z0-9_]+)\s+12'h([0-9A-Fa-f]+)",
            rtl_text,
        )
    }
    hal_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+RS_PSRAM_([A-Z0-9_]+)_OFFSET\s+UINT32_C\(0x([0-9A-Fa-f]+)\)",
            hal_text,
        )
    }

    assert hal_offsets
    for name, value in hal_offsets.items():
        rtl_name = "CHIP0_ID_LO" if name == "CHIP_ID_BASE" else name
        assert rtl_offsets[rtl_name] == value
