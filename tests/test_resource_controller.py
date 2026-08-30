"""Directed verification for the Mini Resource Controller."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_resource_controller_ownership_irq_and_cache_handshake(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "resource_controller_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "resource_controller_tb",
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/mini/top/resource_controller.sv"),
            str(ROOT / "tests/rtl/resource_controller_tb.sv"),
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
    assert "Resource Controller ownership, IRQ, and cache handshake test passed" in result.stdout
