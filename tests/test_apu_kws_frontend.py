"""Differential tests for the committed APU-P7 frontend profile-1 BAM."""

from __future__ import annotations

import os
import re
import shutil
import struct
import subprocess
import sys
from fractions import Fraction
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import apu_kws_frontend as bam  # noqa: E402
import generate_apu_kws_rtl_constants as gen  # noqa: E402
from apu_kws_convert import import_tflite  # noqa: E402
from run_apu_p7_kws_rtl import (  # noqa: E402
    PCM_SOURCES,
    TFLITE,
    _load_manifest,
    _padded_pcm,
    _write_hex,
)

KWS01 = ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
ROM = ROOT / "rtl/ip/multimedia/apu_kws_rom.svh"
DUMP_TB = ROOT / "tests/rtl/apu_p7_frontend_dump_tb.sv"
OFFICIAL_SUBSET = (0, 1, 97, 194, 291, 388, 485, 563, 582, 679, 776, 873, 970)
MFCC_PATTERN = re.compile(r"^MFCC_HEX (\d+) ([0-9a-f]{980})$")
PEAK_PATTERN = re.compile(r"^PEAK (\d+) (\d+)$")
COMPLETE_PATTERN = re.compile(r"^APU_P7_FRONTEND_DUMP_COMPLETE windows=(\d+) first=(\d+)$")
_ROM_SIGNED = re.compile(r"\s*\d+'d(\d+):\s*(\w+)\s*=\s*(-)?\d+'sd(\d+);")
_ROM_UNSIGNED = re.compile(r"\s*\d+'d(\d+):\s*(\w+)\s*=\s*\d+'d(\d+);")
_ROM_LN2 = re.compile(r"ApuKwsLn2Q24\s*=\s*32'sd(\d+);")


def _signed8(value: int) -> int:
    return value - 256 if value >= 128 else value


def _rom_tables() -> tuple[dict[str, list[int]], int]:
    tables: dict[str, dict[int, int]] = {}
    ln2: int | None = None
    for line in ROM.read_text(encoding="ascii").splitlines():
        match = _ROM_SIGNED.match(line)
        if match:
            index, name, sign, value = match.groups()
            tables.setdefault(name, {})[int(index)] = -int(value) if sign else int(value)
            continue
        match = _ROM_UNSIGNED.match(line)
        if match:
            index, name, value = match.groups()
            tables.setdefault(name, {})[int(index)] = int(value)
            continue
        match = _ROM_LN2.search(line)
        if match:
            ln2 = int(match.group(1))
    assert ln2 is not None
    return {name: [words[i] for i in sorted(words)] for name, words in tables.items()}, ln2


def test_apu_p7_frontend_bam_constants_match_rom() -> None:
    """BAM tables equal the generator outputs and the ROM words the RTL consumes."""
    tables, ln2 = _rom_tables()
    twiddle_real, twiddle_imag = bam.twiddle_q30()
    generator_twiddle_real, generator_twiddle_imag = gen._twiddle()
    assert bam.hann_q30() == tuple(gen._hann())
    assert twiddle_real == tuple(generator_twiddle_real)
    assert twiddle_imag == tuple(generator_twiddle_imag)
    assert bam.mel_q30() == tuple(gen._mel_weights())
    assert bam.dct_q30() == tuple(gen._dct())
    assert bam.log_q24() == tuple(gen._log_rom())
    assert list(bam.hann_q30()) == tables["apu_kws_hann_q30"]
    assert list(twiddle_real) == tables["apu_kws_twiddle_real_q30"]
    assert list(twiddle_imag) == tables["apu_kws_twiddle_imag_q30"]
    assert list(bam.mel_q30()) == tables["apu_kws_mel_q30"]
    assert list(bam.dct_q30()) == tables["apu_kws_dct_q30"]
    assert list(bam.log_q24()) == tables["apu_kws_log_q24"]
    assert bam.ln2_q24() == ln2
    scale = struct.unpack("<f", struct.pack("<I", bam.QUANT_SCALE_BITS))[0]
    assert Fraction(scale) * (1 << 24) == bam.QUANT_DIVISOR
    assert bam.QUANT_DIVISOR == 0x0095AF17
    assert bam.QUANT_BIAS * bam.QUANT_DIVISOR == 0x3087C475


def test_apu_p7_frontend_bam_vs_official_features() -> None:
    """BAM tracks the official corpus within +-1 LSB, wrap bytes byte-exact."""
    if not PCM_SOURCES.is_dir() or not KWS01.is_dir():
        return
    records = _load_manifest()
    for index in OFFICIAL_SUBSET:
        official_path = KWS01 / records[index]["bin_name"]
        if not official_path.is_file():
            return
    for index in OFFICIAL_SUBSET:
        stages = bam.frontend_stages(bam.samples_from_pcm(_padded_pcm(records[index])))
        official = (KWS01 / records[index]["bin_name"]).read_bytes()
        assert len(official) == bam.FEATURE_BYTES
        assert len(stages.features) == bam.FEATURE_BYTES
        differing = [
            (position, actual, expected)
            for position, (actual, expected) in enumerate(zip(stages.features, official))
            if actual != expected
        ]
        for position, actual, expected in differing:
            assert abs(_signed8(actual) - _signed8(expected)) <= 1, (
                f"tst index {index} byte {position}: BAM {_signed8(actual)} vs "
                f"official {_signed8(expected)} exceeds +-1 LSB"
            )
        if index == 563:
            quantized = [value for row in stages.quantized for value in row]
            wraps = [
                position
                for position, value in enumerate(quantized)
                if value < -128 or value > 127
            ]
            assert len(wraps) == 15, f"tst_000563 wrap positions {wraps}"
            assert all(stages.features[position] == official[position] for position in wraps)


def _compile_dump_tb(build_dir: Path) -> dict[str, Path | None]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    filelist = build_dir / "apu_p7_frontend_dump.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_stream_if.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(multimedia / "apu_kws_engine.sv"),
                str(DUMP_TB),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = build_dir / "apu_p7_frontend_dump.v"
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
    simv = build_dir / "apu_p7_frontend_dump_simv"
    subprocess.run(
        ["iverilog", "-g2012", "-s", "apu_p7_frontend_dump_tb", "-o", str(simv), str(converted)],
        check=True,
    )
    verilator_binary: Path | None = None
    if shutil.which("verilator") is not None:
        verilator_dir = build_dir / "verilator"
        ccache_dir = build_dir / "ccache"
        ccache_dir.mkdir(exist_ok=True)
        environment = {
            **os.environ,
            "CCACHE_DIR": str(ccache_dir),
            "CCACHE_TEMPDIR": str(ccache_dir),
        }
        subprocess.run(
            [
                "verilator",
                "--binary",
                "--timing",
                "-O3",
                "-Wno-fatal",
                "--top-module",
                "apu_p7_frontend_dump_tb",
                "--Mdir",
                str(verilator_dir),
                str(converted),
            ],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        verilator_binary = verilator_dir / "Vapu_p7_frontend_dump_tb"
    return {"icarus": simv, "verilator": verilator_binary}


def test_apu_p7_frontend_rtl_differential(tmp_path: Path) -> None:
    """RTL frontend MFCC bytes are bit-exact against the committed BAM."""
    if any(shutil.which(tool) is None for tool in ("iverilog", "vvp", "sv2v")):
        return
    if not PCM_SOURCES.is_dir() or not TFLITE.is_file():
        return
    verilator = shutil.which("verilator")
    # Icarus needs ~7 minutes per window on this engine; keep one window there.
    spans = [(0, 2), (563, 1)] if verilator is not None else [(563, 1)]
    indices = [index for first, count in spans for index in range(first, first + count)]
    records = _load_manifest()
    pcm_dir = tmp_path / "pcm"
    windows: dict[int, bytes] = {}
    for index in indices:
        padded = _padded_pcm(records[index])
        windows[index] = padded
        _write_hex(pcm_dir / f"pcm_{index:06d}.hex", padded)
    apum_hex = tmp_path / "kws_apum.hex"
    _write_hex(apum_hex, import_tflite(TFLITE))
    binaries = _compile_dump_tb(tmp_path)
    dumps: dict[int, tuple[bytes, int]] = {}
    for first, count in spans:
        plusargs = [
            f"+APUM_HEX={apum_hex}",
            f"+PCM_DIR={pcm_dir}",
            f"+WINDOW_COUNT={count}",
            f"+FIRST_INDEX={first}",
            "+MAX_WINDOW_CYCLES=4000000",
        ]
        command = (
            [str(binaries["verilator"]), *plusargs]
            if verilator is not None
            else ["vvp", str(binaries["icarus"]), *plusargs]
        )
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=3600)
        features: dict[int, bytes] = {}
        peaks: dict[int, int] = {}
        completed = 0
        for line in result.stdout.splitlines():
            mfcc_match = MFCC_PATTERN.match(line)
            if mfcc_match:
                features[int(mfcc_match.group(1))] = bytes.fromhex(mfcc_match.group(2))
                continue
            peak_match = PEAK_PATTERN.match(line)
            if peak_match:
                peaks[int(peak_match.group(1))] = int(peak_match.group(2))
                continue
            complete_match = COMPLETE_PATTERN.match(line)
            if complete_match:
                assert int(complete_match.group(1)) == count
                assert int(complete_match.group(2)) == first
                completed += 1
        assert completed == 1, f"dump simulator output lacks the completion marker:\n{result.stdout}"
        for index in range(first, first + count):
            assert index in features and index in peaks, f"window {index} dump missing"
            dumps[index] = (features[index], peaks[index])
    assert sorted(dumps) == indices
    for index in indices:
        stages = bam.frontend_stages(bam.samples_from_pcm(windows[index]))
        rtl_features, rtl_peak = dumps[index]
        assert stages.peak == rtl_peak, (
            f"window {index} peak: BAM {stages.peak} != RTL {rtl_peak}"
        )
        assert stages.features == rtl_features, (
            f"window {index}: RTL frontend MFCC bytes are not bit-exact against the BAM"
        )
