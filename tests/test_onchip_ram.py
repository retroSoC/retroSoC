"""Directed verification for the configurable native-AXI4 on-chip SRAM."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
CAPACITIES_KIB = (4, 16, 32, 64, 128)


@pytest.mark.parametrize("capacity_kib", CAPACITIES_KIB)
def test_onchip_ram_axi4_capacity_protocol_and_performance(
    tmp_path: Path, capacity_kib: int
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    generated = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
            "--have-sram-if",
            "YES",
            "--sram-size-kib",
            str(capacity_kib),
        ],
        check=True,
    )
    output = tmp_path / f"onchip_ram_{capacity_kib}"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "onchip_ram_tb",
            f"-GCapacityKiB={capacity_kib}",
            "+define+PDK_BEHAV",
            "+define+SV_ASSRT_DISABLE",
            "-I" + str(generated / "rtl"),
            "-I" + str(ROOT / "rtl/mini/top"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/tech/ram.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram_reg.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram.sv"),
            str(ROOT / "tests/rtl/onchip_ram_tb.sv"),
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
    assert f"on-chip SRAM AXI4 test passed capacity_kib={capacity_kib}" in result.stdout


@pytest.mark.parametrize("capacity_kib", (4, 32))
def test_onchip_ram_native_axi64_width_ids_and_lanes(
    tmp_path: Path, capacity_kib: int
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    generated = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
            "--have-sram-if",
            "YES",
            "--sram-size-kib",
            str(capacity_kib),
        ],
        check=True,
    )
    output = tmp_path / f"onchip_ram64_{capacity_kib}"
    ccache_tmp = tmp_path / "ccache64"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "onchip_ram64_tb",
            f"-GCapacityKiB={capacity_kib}",
            "+define+PDK_BEHAV",
            "+define+SV_ASSRT_DISABLE",
            "-I" + str(generated / "rtl"),
            "-I" + str(ROOT / "rtl/mini/top"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/tech/ram.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram_reg.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram.sv"),
            str(ROOT / "tests/rtl/onchip_ram64_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj64"),
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
    assert "native AXI64 on-chip SRAM test passed" in result.stdout


def test_absent_onchip_ram_reports_capability_and_decode_errors(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    generated = tmp_path / "memory_map"
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
    output = tmp_path / "onchip_ram_absent"
    ccache_tmp = tmp_path / "ccache-absent"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "onchip_ram_absent_tb",
            "+define+SV_ASSRT_DISABLE",
            "-I" + str(generated / "rtl"),
            "-I" + str(ROOT / "rtl/mini/top"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/tech/ram.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram_reg.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram.sv"),
            str(ROOT / "tests/rtl/onchip_ram_absent_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj-absent"),
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
    assert "absent on-chip SRAM test passed" in result.stdout


def test_ihp130_wrapper_uses_functional_1024x32_macro(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "tc_sram_ihp130"
    ccache_tmp = tmp_path / "ccache-ihp130"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "tc_sram_1024x32_tb",
            "+define+PDK_IHP130",
            "+define+HAVE_SRAM_MACRO",
            "+define+FUNCTIONAL",
            "+define+SYNTHESIS",
            str(
                ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/"
                "RM_IHPSG13_1P_core_behavioral_bm_bist.v"
            ),
            str(
                ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog/"
                "RM_IHPSG13_1P_1024x32_c2_bm_bist.v"
            ),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "tests/rtl/tc_sram_1024x32_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj-ihp130"),
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
    assert "1024x32 SRAM wrapper test passed" in result.stdout

    wrapper = (ROOT / "rtl/tech/tc_sram.sv").read_text(encoding="utf-8")
    assert "RM_IHPSG13_1P_1024x32_c2_bm_bist" in wrapper
    assert "RM_IHPSG13_1P_1024x64_c2_bm_bist" not in wrapper


@pytest.mark.parametrize("macro", (False, True))
def test_jpeg_workspace_sram_wrappers(tmp_path: Path, macro: bool) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / ("jpeg_workspace_macro" if macro else "jpeg_workspace_behavioral")
    ccache_tmp = tmp_path / ("ccache-jpeg-macro" if macro else "ccache-jpeg-behavioral")
    ccache_tmp.mkdir()
    command = [
        verilator,
        "--binary",
        "--timing",
        "-Wno-fatal",
        "--top-module",
        "tc_sram_jpeg_workspace_tb",
    ]
    if macro:
        sram_root = (
            ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog"
        )
        command.extend(
            [
                "+define+PDK_IHP130",
                "+define+HAVE_SRAM_MACRO",
                "+define+FUNCTIONAL",
                "+define+SYNTHESIS",
                str(sram_root / "RM_IHPSG13_1P_core_behavioral_bm_bist.v"),
                str(sram_root / "RM_IHPSG13_2P_core_behavioral_ideal.v"),
                str(sram_root / "RM_IHPSG13_1P_64x64_c2_bm_bist.v"),
                str(sram_root / "RM_IHPSG13_2P_64x32_c2.v"),
            ]
        )
    command.extend(
        [
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "tests/rtl/tc_sram_jpeg_workspace_tb.sv"),
            "-Mdir",
            str(tmp_path / ("obj-jpeg-macro" if macro else "obj-jpeg-behavioral")),
            "-o",
            str(output),
        ]
    )
    subprocess.run(
        command,
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
    assert "JPEG SRAM workspace wrapper test passed" in result.stdout


def test_ics55_wrapper_preserves_active_low_controls_and_byte_masks(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "tc_sram_ics55"
    ccache_tmp = tmp_path / "ccache-ics55"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "tc_sram_1024x32_tb",
            "+define+PDK_ICS55",
            "+define+HAVE_SRAM_MACRO",
            str(ROOT / "tests/rtl/ics55_onchip_sram_stub.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "tests/rtl/tc_sram_1024x32_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj-ics55"),
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
    assert "1024x32 SRAM wrapper test passed" in result.stdout


@pytest.mark.parametrize(
    ("pdk", "model"),
    (
        ("GF180", "gf180_sram_sim_cells.sv"),
        ("SKY130", "sky130_sram_sim_cells.sv"),
    ),
)
def test_open_pdk_sram_wrappers_preserve_depth_and_byte_masks(
    tmp_path: Path, pdk: str, model: str
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / f"tc_sram_{pdk.lower()}"
    ccache_tmp = tmp_path / f"ccache-{pdk.lower()}"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "tc_sram_1024x32_tb",
            f"+define+PDK_{pdk}",
            "+define+HAVE_SRAM_MACRO",
            "+define+SV_ASSRT_DISABLE",
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/tech/ram.sv"),
            str(ROOT / "rtl/tech" / model),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "tests/rtl/tc_sram_1024x32_tb.sv"),
            "-Mdir",
            str(tmp_path / f"obj-{pdk.lower()}"),
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
    assert "1024x32 SRAM wrapper test passed" in result.stdout


def test_native_axi4_burst_reaches_peak_and_removes_bridge_overhead(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    generated = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
            "--have-sram-if",
            "YES",
            "--sram-size-kib",
            "4",
        ],
        check=True,
    )
    output = tmp_path / "onchip_ram_perf"
    ccache_tmp = tmp_path / "ccache-perf"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "onchip_ram_perf_tb",
            "+define+PDK_BEHAV",
            "+define+SV_ASSRT_DISABLE",
            "-I" + str(generated / "rtl"),
            "-I" + str(ROOT / "rtl/mini/top"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/ram_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/xchecker.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/tech/ram.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "rtl/mini/top/axi42ram.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram_reg.sv"),
            str(ROOT / "rtl/mini/top/onchip_ram.sv"),
            str(ROOT / "tests/rtl/onchip_ram_perf_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj-perf"),
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
    assert "on-chip SRAM burst cycles native=16 legacy=18" in result.stdout
