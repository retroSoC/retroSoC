"""NPU-P1 compute-core RTL differential tests on Icarus Verilog and Verilator.

Golden vectors are generated at test time from the pinned numerical oracle in
scripts/npu_reference.py, so the RTL is checked bit-exactly against numerical
profile 1. Both simulators must pass; missing tools fail the test loudly.
"""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_reference import (  # noqa: E402
    INT32_MAX,
    INT32_MIN,
    ArithmeticFault,
    multiply_by_quantized_multiplier,
)

MULTIMEDIA = ROOT / "rtl/ip/multimedia"
NPU_PKG = MULTIMEDIA / "npu_pkg.sv"
MAC_TB = ROOT / "tests/rtl/npu_mac_array_tb.sv"
ACC_TB = ROOT / "tests/rtl/npu_accumulator_tb.sv"
REQ_TB = ROOT / "tests/rtl/npu_requantizer_tb.sv"

MAC_PASS_MARKER = "NPU mac array test passed"
ACC_PASS_MARKER = "NPU accumulator test passed"
REQ_PASS_MARKER = "NPU requantizer test passed"


def _to_int8(value: int) -> int:
    return value - 256 if value >= 128 else value


def _require_tools() -> tuple[str, str, str, str]:
    tools = {
        "iverilog": shutil.which("iverilog"),
        "vvp": shutil.which("vvp"),
        "sv2v": shutil.which("sv2v"),
        "verilator": shutil.which("verilator"),
    }
    missing = [name for name, path in tools.items() if path is None]
    if missing:
        pytest.fail(f"NPU RTL compute tests require missing tools: {', '.join(missing)}")
    return tools["iverilog"], tools["vvp"], tools["sv2v"], tools["verilator"]


def _run_icarus(
    tmp_path: Path,
    iverilog: str,
    vvp: str,
    sv2v: str,
    top: str,
    sources: list[Path],
    plusargs: list[str],
) -> str:
    del sv2v  # convt_sv2v.py resolves the executable itself
    source_list = tmp_path / f"{top}.fl"
    source_list.write_text(
        "\n".join(
            ["+define+SV_ASSRT_DISABLE", *(str(source) for source in sources), ""]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / f"{top}.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / f"{top}_iverilog"
    subprocess.run(
        [iverilog, "-g2012", "-s", top, "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation), *plusargs],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def _run_verilator(
    tmp_path: Path, verilator: str, top: str, sources: list[Path], plusargs: list[str]
) -> str:
    object_dir = tmp_path / f"{top}_obj"
    ccache_dir = tmp_path / f"{top}_ccache"
    ccache_dir.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            top,
            "-Mdir",
            str(object_dir),
            "-o",
            "simv",
            *(str(source) for source in sources),
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
    result = subprocess.run(
        [str(object_dir / "simv"), *plusargs],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def _run_dual(
    tmp_path: Path, top: str, rtl: list[Path], plusargs: list[str], marker: str
) -> None:
    iverilog, vvp, sv2v, verilator = _require_tools()
    sources = [NPU_PKG, *rtl]
    icarus_stdout = _run_icarus(
        tmp_path, iverilog, vvp, sv2v, top, sources + [ROOT / "tests/rtl" / f"{top}.sv"], plusargs
    )
    assert marker in icarus_stdout, f"Icarus run of {top} did not pass"
    verilator_stdout = _run_verilator(
        tmp_path, verilator, top, sources + [ROOT / "tests/rtl" / f"{top}.sv"], plusargs
    )
    assert marker in verilator_stdout, f"Verilator run of {top} did not pass"


def _mac_expected(
    a_bytes: list[int], w_bytes: list[int], in_zero: int, a_valid: int, w_valid: int
) -> list[int]:
    products = []
    for position in range(8):
        centered = _to_int8(a_bytes[position]) - in_zero
        for channel in range(8):
            if ((a_valid >> position) & 1) and ((w_valid >> channel) & 1):
                products.append(centered * _to_int8(w_bytes[channel]))
            else:
                products.append(0)
    return products


def _mac_vectors(tmp_path: Path) -> tuple[Path, int]:
    """Write 5 + 64 words per item; see tests/rtl/npu_mac_array_tb.sv for the format."""
    rng = random.Random(0x9C1A55)
    items: list[tuple[list[int], list[int], int, int, int]] = []
    directed = [
        ([0x00] * 8, [0x00] * 8, 0, 0xFF, 0xFF),
        ([0xFF] * 8, [0xFF] * 8, 0, 0xFF, 0xFF),
        ([0xFF] * 8, [0xFF] * 8, -128, 0xFF, 0xFF),
        ([0x00] * 8, [0x80] * 8, 127, 0xFF, 0xFF),
        ([0x00] * 8, [0x7F] * 8, -128, 0xFF, 0xFF),
        ([0x80] * 8, [0x7F] * 8, 127, 0xFF, 0xFF),
        ([0x7F] * 8, [0x80] * 8, -128, 0xFF, 0xFF),
        ([0x53] * 8, [0xD6] * 8, 83, 0xFF, 0xFF),
        ([0x2C] * 8, [0x19] * 8, 83, 0xFF, 0xFF),
        ([0x11, 0xEE, 0x5A, 0xA5, 0x00, 0xFF, 0x7F, 0x80],
         [0x01, 0xFE, 0x40, 0xC0, 0x10, 0xF0, 0x08, 0x88], 0, 0xFF, 0xFF),
        ([0x40] * 8, [0x40] * 8, 0, 0x00, 0xFF),
        ([0x40] * 8, [0x40] * 8, 0, 0xFF, 0x00),
        ([0x40] * 8, [0x40] * 8, 0, 0x00, 0x00),
        ([0x55] * 8, [0x2A] * 8, -5, 0x01, 0xFF),
        ([0x55] * 8, [0x2A] * 8, -5, 0x7F, 0xFF),
        ([0x55] * 8, [0x2A] * 8, -5, 0xFF, 0x01),
        ([0x55] * 8, [0x2A] * 8, -5, 0xFF, 0x7F),
        ([0x55] * 8, [0x2A] * 8, -5, 0x80, 0x80),
        ([0x55] * 8, [0x2A] * 8, -5, 0xAA, 0x55),
        ([0x55] * 8, [0x2A] * 8, -5, 0xFF, 0x09),
    ]
    items.extend(directed)
    for _ in range(40):
        items.append(
            (
                [rng.randrange(256) for _ in range(8)],
                [rng.randrange(256) for _ in range(8)],
                rng.randint(-128, 127),
                rng.randrange(256),
                rng.randrange(256),
            )
        )

    words: list[int] = []
    for a_bytes, w_bytes, in_zero, a_valid, w_valid in items:
        a_packed = sum(byte << (8 * lane) for lane, byte in enumerate(a_bytes))
        w_packed = sum(byte << (8 * lane) for lane, byte in enumerate(w_bytes))
        flags = ((in_zero & 0xFF) << 16) | (a_valid << 8) | w_valid
        words.append(a_packed & 0xFFFFFFFF)
        words.append((a_packed >> 32) & 0xFFFFFFFF)
        words.append(w_packed & 0xFFFFFFFF)
        words.append((w_packed >> 32) & 0xFFFFFFFF)
        words.append(flags)
        for product in _mac_expected(a_bytes, w_bytes, in_zero, a_valid, w_valid):
            words.append(product & 0xFFFFFFFF)

    vector_path = tmp_path / "npu_mac_array_vectors.hex"
    vector_path.write_text("\n".join(f"{word:08x}" for word in words) + "\n", encoding="utf-8")
    return vector_path, len(items)


def _requantizer_expected(
    acc: int, multiplier: int, shift: int, zout: int, act_min: int, act_max: int
) -> tuple[int, int]:
    try:
        quantized = multiply_by_quantized_multiplier(acc, multiplier, shift)
    except ArithmeticFault:
        return 0, 1
    return max(act_min, min(act_max, quantized + zout)), 0


def _requantizer_vectors(tmp_path: Path) -> tuple[Path, int]:
    """Write 8 words per item; see tests/rtl/npu_requantizer_tb.sv for the format."""
    rng = random.Random(0x5EED1234)
    full = (-128, 127)
    cases: list[tuple[int, int, int, int, int, int]] = [
        # acc, multiplier, shift, zout, act_min, act_max
        (0, 1 << 30, 0, 0, *full),
        (1, 1 << 30, 0, 0, *full),
        (-1, 1 << 30, 0, 0, *full),
        (INT32_MAX, INT32_MAX, 0, 0, *full),
        (INT32_MIN, INT32_MAX, 0, 0, *full),
        (INT32_MIN, INT32_MAX, -1, 0, *full),
        (INT32_MIN, 1 << 30, 0, 0, *full),
        (12345, 0, 0, 0, *full),  # flushed multiplier (m = 0)
        (-54321, 0, 0, 5, *full),
        (1000, 0x50000000, -31, 0, *full),
        (1000, 0x50000000, -1, 0, *full),
        (1000, 0x50000000, 1, 0, *full),
        (3, 0x60000000, 30, 0, *full),
        # RoundingDivideByPOT negative ties and rounding directions.
        (5, INT32_MAX, -2, 0, *full),
        (-5, INT32_MAX, -2, 0, *full),
        (7, INT32_MAX, -3, 0, *full),
        (-7, INT32_MAX, -3, 0, *full),
        (3, 1 << 29, 0, 0, *full),
        (-3, 1 << 29, 0, 0, *full),
        (1, 1 << 29, -1, 0, *full),
        (-1, 1 << 29, -1, 0, *full),
        (INT32_MIN, INT32_MAX, -31, 0, *full),
        (INT32_MAX, INT32_MAX, -31, 0, *full),
        # Checked left shift: boundaries and overflows.
        (0x40000000, 1 << 30, 2, 0, *full),  # 2^30 << 2 overflows
        (INT32_MAX, 1 << 30, 1, 0, *full),
        (INT32_MIN, 1 << 30, 1, 0, *full),
        (-(1 << 30), 1 << 30, 1, 0, *full),  # exactly -2^31, no fault
        (-(1 << 30), 1 << 30, 2, 0, *full),  # -2^32, fault
        (1, 1 << 30, 30, 0, *full),
        (-1, 1 << 30, 30, 0, *full),
        # Output zero-point edges and activation clamps.
        (0, 1 << 30, 0, -128, *full),
        (0, 1 << 30, 0, 127, *full),
        (-200, INT32_MAX, 0, 127, *full),
        (200, INT32_MAX, 0, -128, *full),
        (100000, INT32_MAX, 0, 0, -10, 10),
        (-100000, INT32_MAX, 0, 0, -10, 10),
        (50, INT32_MAX, 0, 0, 0, 0),
        (-50, INT32_MAX, 0, 3, 3, 3),
        (0, INT32_MAX, 0, 127, -128, 0),
        (0, INT32_MAX, 0, -128, 0, 127),
    ]
    for _ in range(200):
        act_low = rng.randint(-128, 127)
        act_high = rng.randint(-128, 127)
        cases.append(
            (
                rng.randint(INT32_MIN, INT32_MAX),
                rng.choice(
                    [0, 1, rng.randint(0, INT32_MAX), rng.randint(1 << 29, INT32_MAX), INT32_MAX]
                ),
                rng.randint(-31, 30),
                rng.randint(-128, 127),
                min(act_low, act_high),
                max(act_low, act_high),
            )
        )

    words: list[int] = []
    for acc, multiplier, shift, zout, act_min, act_max in cases:
        expected, fault = _requantizer_expected(acc, multiplier, shift, zout, act_min, act_max)
        words.extend(
            value & 0xFFFFFFFF
            for value in (acc, multiplier, shift, zout, act_min, act_max, expected, fault)
        )

    vector_path = tmp_path / "npu_requantizer_vectors.hex"
    vector_path.write_text("\n".join(f"{word:08x}" for word in words) + "\n", encoding="utf-8")
    return vector_path, len(cases)


def test_npu_mac_array_dual_simulator(tmp_path: Path) -> None:
    vector_path, vector_count = _mac_vectors(tmp_path)
    _run_dual(
        tmp_path,
        "npu_mac_array_tb",
        [MULTIMEDIA / "npu_mac_array.sv"],
        [f"+VECTORS={vector_path}", f"+VECTOR_COUNT={vector_count}"],
        MAC_PASS_MARKER,
    )


def test_npu_accumulator_dual_simulator(tmp_path: Path) -> None:
    _run_dual(
        tmp_path,
        "npu_accumulator_tb",
        [MULTIMEDIA / "npu_accumulator.sv"],
        [],
        ACC_PASS_MARKER,
    )


def test_npu_requantizer_dual_simulator(tmp_path: Path) -> None:
    vector_path, vector_count = _requantizer_vectors(tmp_path)
    assert vector_count > 200
    _run_dual(
        tmp_path,
        "npu_requantizer_tb",
        [MULTIMEDIA / "npu_requantizer.sv"],
        [f"+VECTORS={vector_path}", f"+VECTOR_COUNT={vector_count}"],
        REQ_PASS_MARKER,
    )
