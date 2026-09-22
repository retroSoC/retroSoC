"""NPU-P1 memory, patch packer and vector RTL unit tests (Icarus and Verilator)."""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
MULTIMEDIA = ROOT / "rtl/ip/multimedia"
SRAM_MODEL_ROOT = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog"
SRAM_MACRO_MODELS = [
    SRAM_MODEL_ROOT / "RM_IHPSG13_1P_core_behavioral_bm_bist.v",
    SRAM_MODEL_ROOT / "RM_IHPSG13_1P_1024x32_c2_bm_bist.v",
]
BEHAV_DEFINES = ("PDK_BEHAV",)
MACRO_DEFINES = ("PDK_IHP130", "HAVE_SRAM_MACRO", "FUNCTIONAL", "SYNTHESIS")


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


def _build_iverilog(
    tools: dict[str, str],
    tmp_path: Path,
    name: str,
    sources: list[Path],
    top: str,
    defines: tuple[str, ...],
    extra_sources: list[Path] | None = None,
) -> Path:
    filelist = tmp_path / f"{name}.fl"
    filelist.write_text(
        "\n".join(
            [
                *(f"+define+{define}" for define in defines),
                "+define+SV_ASSRT_DISABLE",
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
    command = [
        tools["iverilog"],
        "-g2012",
        "-s",
        top,
        "-o",
        str(simulation),
        str(converted),
    ]
    if extra_sources:
        command.extend(("-DFUNCTIONAL", "-DSYNTHESIS"))
        command.extend(str(source) for source in extra_sources)
    subprocess.run(command, check=True)
    return simulation


def _build_verilator(
    tools: dict[str, str],
    tmp_path: Path,
    name: str,
    sources: list[Path],
    top: str,
    defines: tuple[str, ...],
) -> Path:
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
            *(f"+define+{define}" for define in defines),
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


def _build(
    tools: dict[str, str],
    simulator: str,
    tmp_path: Path,
    name: str,
    sources: list[Path],
    top: str,
    defines: tuple[str, ...],
    extra_sources: list[Path] | None = None,
) -> list[str]:
    if simulator == "iverilog":
        simulation = _build_iverilog(
            tools, tmp_path, name, sources, top, defines, extra_sources
        )
        return [tools["vvp"], str(simulation)]
    if simulator == "verilator":
        simv = _build_verilator(
            tools, tmp_path, name, [*(extra_sources or []), *sources], top, defines
        )
        return [str(simv)]
    raise AssertionError(f"unknown simulator {simulator}")


def _run(command: list[str], plusargs: tuple[str, ...] = ()) -> str:
    result = subprocess.run(
        [*command, *plusargs], check=True, text=True, capture_output=True
    )
    return result.stdout


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
@pytest.mark.parametrize("variant", ("behav", "macro"))
def test_npu_local_sram(tmp_path: Path, simulator: str, variant: str) -> None:
    tools = _tools()
    for model in SRAM_MACRO_MODELS:
        assert model.is_file()
    sources = [
        MULTIMEDIA / "npu_pkg.sv",
        ROOT / "rtl/tech/tc_sram.sv",
        MULTIMEDIA / "npu_local_sram.sv",
        ROOT / "tests/rtl/npu_local_sram_tb.sv",
    ]
    defines = BEHAV_DEFINES if variant == "behav" else MACRO_DEFINES
    extra = [] if variant == "behav" else SRAM_MACRO_MODELS
    command = _build(
        tools,
        simulator,
        tmp_path,
        f"npu_local_sram_{variant}",
        sources,
        "npu_local_sram_tb",
        defines,
        extra_sources=extra,
    )
    assert "NPU_LOCAL_SRAM_PASS" in _run(command)


def _pack_golden(mode: int, k: int, m: int, channels: int, in_zero: int, raw: bytes) -> list[int]:
    fill = in_zero & 0xFF
    rows = []
    if mode == 0:
        assert len(raw) == m * k
        for row in range(k):
            value = 0
            for lane in range(8):
                byte = raw[lane * k + row] if lane < m else fill
                value |= byte << (8 * lane)
            rows.append(value)
    else:
        assert len(raw) == m * k * 8
        for row in range(m * k):
            value = 0
            for lane in range(8):
                byte = raw[row * 8 + lane] if lane < channels else fill
                value |= byte << (8 * lane)
            rows.append(value)
    return rows


def _packer_cases() -> list[tuple[int, int, int, int, int]]:
    cases = []
    for m in (1, 7, 8):
        for k in (1, 9, 1024):
            for in_zero in (-128, 0, 83, 127):
                cases.append((0, k, m, 8, in_zero))
    for m, channels in ((1, 8), (3, 5)):
        for in_zero in (-128, 0, 83, 127):
            cases.append((1, 9, m, channels, in_zero))
    return cases


def _packer_plusargs(
    tmp_path: Path, case_index: int, case: tuple[int, int, int, int, int]
) -> tuple[str, ...]:
    mode, k, m, channels, in_zero = case
    rng = random.Random(0x5EED0000 + case_index)
    raw_byte_count = m * k if mode == 0 else m * k * 8
    raw = bytes(rng.randrange(256) for _ in range(raw_byte_count))
    words = [0] * ((raw_byte_count + 3) // 4)
    for index, byte in enumerate(raw):
        words[index // 4] |= byte << (8 * (index % 4))
    raw_path = tmp_path / f"packer_raw_{case_index}.hex"
    raw_path.write_text("\n".join(f"{word:08x}" for word in words) + "\n", encoding="utf-8")
    rows = _pack_golden(mode, k, m, channels, in_zero, raw)
    expected_path = tmp_path / f"packer_expected_{case_index}.hex"
    expected_path.write_text(
        "\n".join(f"{row:016x}" for row in rows) + "\n", encoding="utf-8"
    )
    return (
        f"+MODE={mode}",
        f"+K={k}",
        f"+M={m}",
        f"+CHANNELS={channels}",
        f"+IN_ZERO={in_zero & 0xFF}",
        f"+ROWS={len(rows)}",
        f"+RAW={raw_path}",
        f"+EXPECTED={expected_path}",
    )


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_patch_packer(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    sources = [
        MULTIMEDIA / "npu_pkg.sv",
        MULTIMEDIA / "npu_patch_packer.sv",
        ROOT / "tests/rtl/npu_patch_packer_tb.sv",
    ]
    command = _build(
        tools,
        simulator,
        tmp_path,
        "npu_patch_packer",
        sources,
        "npu_patch_packer_tb",
        BEHAV_DEFINES,
    )
    cases = _packer_cases()
    assert len(cases) == 44
    for case_index, case in enumerate(cases):
        plusargs = _packer_plusargs(tmp_path, case_index, case)
        output = _run(command, plusargs)
        assert "NPU_PATCH_PACKER_PASS" in output, f"case {case} failed"


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_vector(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    sources = [
        MULTIMEDIA / "npu_pkg.sv",
        MULTIMEDIA / "npu_vector.sv",
        ROOT / "tests/rtl/npu_vector_tb.sv",
    ]
    command = _build(
        tools,
        simulator,
        tmp_path,
        "npu_vector",
        sources,
        "npu_vector_tb",
        BEHAV_DEFINES,
    )
    assert "NPU_VECTOR_PASS" in _run(command)
