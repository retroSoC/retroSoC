"""PPALITE-P3 real Tiny DMA admission and integration checks."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from test_tiny_r2_p7 import COMMON, ROOT, run_rtl

TINY = ROOT / "rtl/tiny"
PPA = ROOT / "rtl/ip/ppalite"


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_dma_admission(tmp_path: Path, simulator: str) -> None:
    run_rtl(tmp_path, simulator, "ppalite_dma_guard_tb",
            [TINY / "top/ppalite_dma_guard.sv"],
            defines=[f"-I{ROOT / 'rtl/ip/peripheral'}", f"-I{ROOT / 'rtl/ip/ppalite'}"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_arm_dma_race(tmp_path: Path, simulator: str) -> None:
    sources = [
        COMMON / "interface/axi4_stream_if.sv",
        COMMON / "utils/fifo.sv",
        COMMON / "utils/spill_register.sv",
        COMMON / "utils/edge_det.sv",
        *[PPA / f"{name}.sv" for name in (
            "ppalite_if", "ppalite_fifo", "ppalite_decimator", "ppalite_packer",
            "ppalite_stream_guard", "ppalite_core", "ppalite_reg", "apb4_ppalite")],
        TINY / "top/ppalite_dma_guard.sv",
    ]
    run_rtl(tmp_path, simulator, "ppalite_arm_dma_race_tb", sources,
            defines=[f"-I{ROOT / 'rtl/ip/peripheral'}", f"-I{PPA}",
                     f"-I{COMMON / 'utils'}"])


def test_tiny_ppalite_topology_and_rcu() -> None:
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    memory = json.loads((TINY / "address_map/memory_map.json").read_text())
    regions = {row["symbol"]: row for row in memory["regions"]}
    assert regions["APB4_PPALITE"]["base"] == "0x1001E000"
    assert topology["fabric"]["target_count"] == 30
    assert topology["fabric"]["decode_error_target"] == 28
    assert topology["fabric"]["protocol_error_target"] == 29
    assert any(row["name"] == "ppalite" and row["regions"] == ["APB4_PPALITE"]
               for row in topology["apb_targets"])
    assert {row["core_bit"] for row in topology["interrupts"] if row["name"] == "ppalite"} == {27}
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert ".TargetMask (18'h37fff)" in top
    assert "s_leaf_rst_n[23]" in top
    assert "s_ppalite_active_ref" in top


def test_acceptance_image_is_explicit_and_isolated(tmp_path: Path) -> None:
    base = ["make", "--no-print-directory", "CONFIG=configs/ci/ics55-tiny.mk", "APP=ci_smoke",
            "TINY_PPALITE_P3_ACCEPTANCE=YES", "BUILD_TIMESTAMP=2026-11-01-10-00"]
    build = subprocess.run([*base, "-n", "firmware"], cwd=ROOT, text=True, capture_output=True,
                           check=False)
    assert build.returncode == 0, build.stdout + build.stderr
    assert "tiny_ppalite_p3.c" in build.stdout
    assert "crt/src/hal/ppalite.c" in build.stdout
    assert "crt/src/hal/ppalite_math.c" in build.stdout
    for override in ("TINY_P7_ACCEPTANCE=YES", "TINY_P8_ACCEPTANCE=YES",
                     "TINY_P9_ACCEPTANCE=YES", "TINY_P10_ACCEPTANCE=YES",
                     "TINY_SPI_P3_ACCEPTANCE=YES", "TINY_SPI_P4_ACCEPTANCE=YES",
                     "APP=bringup", "SOC=MINI"):
        result = subprocess.run([*base, override, "config"], cwd=ROOT, text=True,
                                capture_output=True, check=False)
        assert result.returncode != 0, override
