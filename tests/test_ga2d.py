"""Directed GA2D Phase 3 APB4 shell verification."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def run_ga2d_rtl_test(
    tmp_path: Path, top_module: str, testbench: str, success_marker: str
) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        pytest.fail("GA2D P3 RTL tests require Verilator")

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    output = tmp_path / top_module
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            top_module,
            "-I" + str(common),
            "-I" + str(common / "interface"),
            "-I" + str(multimedia),
            str(common / "interface/apb4_if.sv"),
            str(common / "utils/register.sv"),
            str(multimedia / "ga2d_pkg.sv"),
            str(multimedia / "ga2d_reg.sv"),
            str(multimedia / "apb4_ga2d.sv"),
            str(ROOT / "tests/rtl" / testbench),
            "-Mdir",
            str(tmp_path / "obj"),
            "-o",
            str(output),
        ],
        check=True,
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "CCACHE_DIR": str(ccache_tmp),
            "CCACHE_TEMPDIR": str(ccache_tmp),
        },
    )
    result = subprocess.run([output], check=True, capture_output=True, text=True)
    assert success_marker in result.stdout


def test_ga2d_p3_apb_shell(tmp_path: Path) -> None:
    run_ga2d_rtl_test(
        tmp_path,
        "ga2d_tb",
        "ga2d_tb.sv",
        "GA2D P3 APB shell test passed",
    )


def test_ga2d_p3_wrapper_lifecycle(tmp_path: Path) -> None:
    run_ga2d_rtl_test(
        tmp_path,
        "ga2d_wrapper_tb",
        "ga2d_wrapper_tb.sv",
        "GA2D P3 wrapper lifecycle test passed",
    )
