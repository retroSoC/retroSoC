"""Required GA2D Phase 5 APB4 shell and private-DMA RTL verification."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def _require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        pytest.fail(f"GA2D P5 RTL tests require {name}")
    return path


def _generate_memory_map(tmp_path: Path) -> Path:
    output = tmp_path / "memory_map"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(output),
            "--have-sram-if",
            "YES",
            "--sram-size-kib",
            "32",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return output / "rtl"


def _ga2d_sources(
    testbench: str, memory_map: Path, *, sv2v_filelist: bool = False
) -> list[str]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    include_prefix = "+incdir+" if sv2v_filelist else "-I"
    return [
        include_prefix + str(memory_map),
        include_prefix + str(common),
        include_prefix + str(common / "interface"),
        include_prefix + str(multimedia),
        str(common / "interface/apb4_if.sv"),
        str(common / "interface/axi4_if.sv"),
        str(common / "utils/register.sv"),
        str(common / "utils/fifo.sv"),
        str(common / "stream/round_robin_arbiter.sv"),
        str(multimedia / "ga2d_pkg.sv"),
        str(multimedia / "ga2d_addr_gen.sv"),
        str(multimedia / "ga2d_axi4_master.sv"),
        str(multimedia / "ga2d_dma.sv"),
        str(multimedia / "ga2d_pixel.sv"),
        str(multimedia / "ga2d_core.sv"),
        str(multimedia / "ga2d_reg.sv"),
        str(multimedia / "apb4_ga2d.sv"),
        str(ROOT / "tests/rtl" / testbench),
    ]


def _run_verilator_test(
    tmp_path: Path, top_module: str, testbench: str, success_marker: str
) -> None:
    verilator = _require_tool("verilator")
    output = tmp_path / top_module
    memory_map = _generate_memory_map(tmp_path)
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
            *_ga2d_sources(testbench, memory_map),
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


def _run_iverilog_test(
    tmp_path: Path, top_module: str, testbench: str, success_marker: str
) -> None:
    iverilog = _require_tool("iverilog")
    vvp = _require_tool("vvp")
    _require_tool("sv2v")
    memory_map = _generate_memory_map(tmp_path)
    source_list = tmp_path / f"{top_module}.fl"
    source_list.write_text(
        "\n".join((*_ga2d_sources(testbench, memory_map, sv2v_filelist=True), "")),
        encoding="utf-8",
    )
    converted = tmp_path / f"{top_module}.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    simulation = tmp_path / top_module
    subprocess.run(
        [iverilog, "-g2012", "-s", top_module, "-o", str(simulation), str(converted)],
        check=True,
        capture_output=True,
        text=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert success_marker in result.stdout


def test_ga2d_p5_apb_shell(tmp_path: Path) -> None:
    _run_verilator_test(
        tmp_path,
        "ga2d_tb",
        "ga2d_tb.sv",
        "GA2D P5 APB shell test passed",
    )


def test_ga2d_p5_wrapper_lifecycle(tmp_path: Path) -> None:
    _run_verilator_test(
        tmp_path,
        "ga2d_wrapper_tb",
        "ga2d_wrapper_tb.sv",
        "GA2D P5 wrapper lifecycle test passed",
    )
