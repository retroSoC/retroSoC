"""NPU-P2 register shell and control-CDC unit tests (Icarus and Verilator)."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
MULTIMEDIA = ROOT / "rtl/ip/multimedia"

INCDIRS = [COMMON, COMMON / "interface", MULTIMEDIA]
COMMON_SOURCES = [
    COMMON / "interface/apb4_if.sv",
    COMMON / "interface/axi4_if.sv",
    COMMON / "utils/register.sv",
    COMMON / "utils/xchecker.sv",
    COMMON / "clkrst/rst_sync.sv",
    COMMON / "cdc/cdc_sync.sv",
    COMMON / "cdc/cdc_rst_ctrlr.sv",
    COMMON / "cdc/async_reqack.sv",
]
SHELL_SOURCES = [
    MULTIMEDIA / "npu_reg.sv",
    MULTIMEDIA / "npu_control_cdc.sv",
    MULTIMEDIA / "npu_core.sv",
    MULTIMEDIA / "apb4_npu.sv",
]


def _tools() -> dict[str, str]:
    tools: dict[str, str] = {}
    missing = []
    for name in ("iverilog", "vvp", "sv2v", "verilator"):
        path = shutil.which(name)
        if path is None:
            missing.append(name)
        else:
            tools[name] = path
    if missing:
        pytest.fail(f"required simulation tools missing: {', '.join(missing)}")
    return tools


def _build_iverilog(tools: dict[str, str], tmp_path: Path, name: str, top: str,
                    sources: list[Path]) -> Path:
    filelist = tmp_path / f"{name}.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                *(f"+incdir+{incdir}" for incdir in INCDIRS),
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / f"{name}.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / f"{name}.iverilog"
    subprocess.run(
        [tools["iverilog"], "-g2012", "-s", top, "-o", str(simulation), str(converted)],
        check=True,
    )
    return simulation


def _build_verilator(tools: dict[str, str], tmp_path: Path, name: str, top: str,
                     sources: list[Path]) -> Path:
    object_dir = tmp_path / f"obj-{name}"
    ccache_dir = tmp_path / f"ccache-{name}"
    ccache_dir.mkdir()
    subprocess.run(
        [
            tools["verilator"],
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            top,
            *(f"+incdir+{incdir}" for incdir in INCDIRS),
            *(str(source) for source in sources),
            "-Mdir",
            str(object_dir),
            "-o",
            "simv",
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
    return object_dir / "simv"


def _run_shell_test(tools: dict[str, str], simulator: str, tmp_path: Path, name: str,
                    top: str, testbench: Path, marker: str) -> None:
    sources = [*COMMON_SOURCES, *SHELL_SOURCES, testbench]
    if simulator == "iverilog":
        simulation = _build_iverilog(tools, tmp_path, name, top, sources)
        command = [tools["vvp"], str(simulation)]
    elif simulator == "verilator":
        command = [str(_build_verilator(tools, tmp_path, name, top, sources))]
    else:
        raise AssertionError(f"unknown simulator {simulator}")
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    assert marker in result.stdout


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_reg_shell(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    _run_shell_test(
        tools,
        simulator,
        tmp_path,
        f"npu_reg_{simulator}",
        "npu_reg_tb",
        ROOT / "tests/rtl/npu_reg_tb.sv",
        "NPU reg test passed",
    )


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_control_cdc(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    _run_shell_test(
        tools,
        simulator,
        tmp_path,
        f"npu_control_cdc_{simulator}",
        "npu_control_cdc_tb",
        ROOT / "tests/rtl/npu_control_cdc_tb.sv",
        "NPU control CDC test passed",
    )
