"""Directed verification for the Mini Data Plane Fabric Monitor."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_fabric_monitor_counts_snapshots_and_clears(tmp_path: Path) -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        return

    output = tmp_path / "fabric_monitor_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "fabric_monitor_tb",
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/mini/top/fabric_monitor.sv"),
            str(ROOT / "tests/rtl/fabric_monitor_tb.sv"),
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
    assert "Fabric Monitor counter, snapshot, and clear test passed" in result.stdout


def test_fabric_monitor_registers_match_hal() -> None:
    rtl = (ROOT / "rtl/mini/top/fabric_monitor.sv").read_text(encoding="utf-8")
    hal = (ROOT / "crt/src/hal/fabric_monitor.c").read_text(encoding="utf-8")
    for value in ("00C", "010", "014", "018", "01C", "020", "100", "300"):
        assert value in rtl
        assert value in hal
