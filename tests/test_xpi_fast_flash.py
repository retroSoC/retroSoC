"""Directed verification for the Verilator-only XPI fast flash backend."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_xpi_fast_flash_model_protocol(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "xpi_fast_flash_model_tb"
    obj_dir = tmp_path / "obj"
    ccache_dir = tmp_path / "ccache"
    ccache_dir.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "xpi_fast_flash_model_tb",
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-I" + str(ROOT / "rtl/ip/storage"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/storage/xpi_pkg.sv"),
            str(ROOT / "rtl/mini/dv/verilator/rtl/flash_read_byte_binder.sv"),
            str(ROOT / "rtl/mini/dv/verilator/rtl/xpi_fast_flash_model.sv"),
            str(ROOT / "tests/rtl/xpi_fast_flash_model_tb.sv"),
            str(ROOT / "tests/rtl/xpi_fast_flash_dpi.cpp"),
            "-Mdir",
            str(obj_dir),
            "-o",
            str(output),
        ],
        check=True,
        text=True,
        capture_output=True,
        env={
            **os.environ,
            "CCACHE_DIR": str(ccache_dir),
            "CCACHE_TEMPDIR": str(ccache_dir),
        },
    )
    result = subprocess.run([output], check=True, text=True, capture_output=True)
    assert "XPI fast flash model test passed" in result.stdout
