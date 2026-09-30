#!/usr/bin/env python3
"""Run the APU-P7 concurrent decode + continuous KWS zero-xrun RTL qualification.

Builds tests/rtl/apu_p7_concurrent_tb.sv once (sv2v + Icarus), then runs the
frozen concurrency matrix: continuous RX KWS concurrent with looped WAV/FLAC
decode streamed to I2S TX under the active P5 ready-memory qualification
(64-word prefill, then ready memory without injected stalls). Each scenario
requires zero codec underrun, zero I2S RX/KWS overrun, every full uninterrupted
scheduled KWS window completed before its successor, and matching
byte/frame/cycle/stall scoreboards. Writes the concurrent.json report and exits
nonzero on any violation or missing input. Nothing is downloaded.

Prerequisites (no network access is used by this script):
- Icarus Verilog (iverilog/vvp) and sv2v on PATH.
- The deterministic P5 codec bundle `apu-p5.apumc`, built once with
  `make CONFIG=configs/ci/ihp130.mk apu-p5-bundle` (writes
  build/<variant>/apu/p5/apu-p5.apumc). Pass it with --apumc or let the newest
  build/*/apu/p5/apu-p5.apumc be auto-discovered.
- The locked P7 TFLite model under .cache/retrosoc/sources/apu-mlperf-tiny
  (installed by the shared P7 reference setup); the APUM image is derived
  locally with scripts/apu_kws_convert.py. --apum accepts a prebuilt image.

The frozen release gate is 60 simulated seconds per scenario at 48 MHz PCLK
(--seconds 60). The default is a short development run; --smoke selects the
minimal single-scenario matrix for pytest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import crc8, crc16, decode_flac, decode_wav, process_pcm  # noqa: E402
from apu_kws import APUM_PAYLOAD_CRC, APUM_SHA256  # noqa: E402
from generate_apu_kws_rtl_constants import build_apuc  # noqa: E402

PCLK_HZ = 48_000_000
FULL_GATE_SECONDS = 60.0
FULL_GATE_CYCLES = int(FULL_GATE_SECONDS * PCLK_HZ)
FLAC_CONSTANT = -2
CONTRACT_REVISION = "apu-kws-convert/1.0.0"
DEFAULT_TFLITE = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)
BUNDLE_PREREQUISITE = "make CONFIG=configs/ci/ihp130.mk apu-p5-bundle"
PROFILE = "configs/ci/ihp130.mk"

RESULT_PATTERN = re.compile(
    r"CONCURRENT_RESULT "
    r"rate=(?P<rate>\d+) "
    r"precision=(?P<precision>\d+) "
    r"seconds_ms=(?P<seconds_ms>\d+) "
    r"duration_cycles=(?P<duration_cycles>\d+) "
    r"jobs=(?P<jobs>\d+) "
    r"wav_jobs=(?P<wav_jobs>\d+) "
    r"flac_jobs=(?P<flac_jobs>\d+) "
    r"tx_words=(?P<tx_words>\d+) "
    r"consumed=(?P<consumed>\d+) "
    r"underrun=(?P<underrun>\d+) "
    r"rx_overrun=(?P<rx_overrun>\d+) "
    r"kws_overrun=(?P<kws_overrun>\d+) "
    r"kws_frames=(?P<kws_frames>\d+) "
    r"kws_windows=(?P<kws_windows>\d+) "
    r"rx_words=(?P<rx_words>\d+) "
    r"codec_input_bytes=(?P<codec_input_bytes>\d+) "
    r"codec_output_bytes=(?P<codec_output_bytes>\d+) "
    r"codec_frames=(?P<codec_frames>\d+) "
    r"codec_cycles=(?P<codec_cycles>\d+) "
    r"dma_read_stalls=(?P<dma_read_stalls>\d+) "
    r"dma_write_stalls=(?P<dma_write_stalls>\d+) "
    r"stream_stalls=(?P<stream_stalls>\d+) "
    r"active_cycles=(?P<active_cycles>\d+) "
    r"elapsed_cycles=(?P<elapsed_cycles>\d+) "
    r"scoreboard=(?P<scoreboard>\w+)"
)


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def _hex_words(path: Path, payload: bytes, words: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    for index in range(words):
        chunk = payload[index * 4 : index * 4 + 4]
        lines.append(f"{int.from_bytes(chunk.ljust(4, bytes(1)), 'little'):08x}\n")
    path.write_text("".join(lines), encoding="utf-8")


def _run_command(command: list[str], *, timeout: int | None = None) -> dict[str, Any]:
    started = time.monotonic()
    try:
        process = subprocess.run(
            command, cwd=ROOT, check=False, capture_output=True, text=True, timeout=timeout
        )
        return {
            "command": command,
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": process.returncode,
            "stdout": process.stdout,
            "stderr": process.stderr,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode("utf-8", errors="replace") if error.stdout else ""
        stderr = error.stderr.decode("utf-8", errors="replace") if error.stderr else ""
        return {
            "command": command,
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": 124,
            "stdout": stdout,
            "stderr": stderr,
            "timed_out": True,
        }


def _tool_version(name: str, flag: str = "--version") -> dict[str, Any]:
    path = shutil.which(name)
    if path is None:
        return {"path": None, "version": None}
    probe = _run_command([path, flag], timeout=30)
    first_line = (probe["stdout"] or probe["stderr"]).splitlines()
    return {
        "path": path,
        "version": first_line[0].strip() if first_line else "unknown",
        "sha256": _sha256_file(Path(path)),
    }


def _git_revision() -> tuple[str, bool]:
    revision = _run_command(["git", "rev-parse", "HEAD"], timeout=30)
    dirty = _run_command(["git", "status", "--porcelain"], timeout=30)
    return (
        revision["stdout"].strip() if revision["exit_code"] == 0 else "unknown",
        bool(dirty["stdout"].strip()) if dirty["exit_code"] == 0 else True,
    )


def _production_sources() -> list[Path]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    names = (
        "apu_microcode_pkg.sv",
        "apu_dma.sv",
        "apu_ring_scheduler.sv",
        "apu_stream_router.sv",
        "apu_control_store.sv",
        "apu_proof_memo.sv",
        "apu_microcode_loader.sv",
        "apu_local_sram.sv",
        "apu_kws_coeff_store.sv",
        "apu_kws_coeff_loader.sv",
        "apu_kws_engine.sv",
        "apu_kws_sram_client.sv",
        "apu_kws_model_loader.sv",
        "apu_bitstream_engine.sv",
        "apu_entropy_engine.sv",
        "apu_reconstruction_engine.sv",
        "apu_transform_engine.sv",
        "apu_resampler.sv",
        "apu_kernel_engine.sv",
        "apu_primitive_dispatcher.sv",
        "apu_codec_sequencer.sv",
        "apu_codec_transport.sv",
        "apu_codec_controller.sv",
        "apu_reg.sv",
        "apb4_apu.sv",
    )
    return [
        common / "interface/apb4_if.sv",
        common / "interface/axi4_if.sv",
        common / "interface/axi4_stream_if.sv",
        common / "utils/register.sv",
        common / "utils/fifo.sv",
        ROOT / "rtl/tech/tc_sram.sv",
        ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
        *(multimedia / name for name in names),
        ROOT / "tests/rtl/apu_p7_concurrent_tb.sv",
    ]


def _verification_sources() -> dict[str, str]:
    inputs = [
        *_production_sources(),
        ROOT / "rtl/ip/multimedia/apu_define.svh",
        ROOT / "scripts/apu_codecs.py",
        ROOT / "scripts/apu_kws.py",
        ROOT / "scripts/apu_kws_convert.py",
        ROOT / "scripts/rtl/convt_sv2v.py",
        Path(__file__).resolve(),
    ]
    return {
        path.relative_to(ROOT).as_posix(): _sha256_file(path)
        for path in sorted(inputs)
        if path.is_file()
    }


def _resolve_apumc(apumc: Path | None) -> Path:
    if apumc is not None:
        resolved = apumc.resolve()
        if not resolved.is_file():
            raise SystemExit(f"APUMC bundle not found: {resolved}\nprerequisite: {BUNDLE_PREREQUISITE}")
        return resolved
    candidates = sorted(
        ROOT.glob("build/*/apu/p5/apu-p5.apumc"), key=lambda path: path.stat().st_mtime
    )
    if not candidates:
        raise SystemExit(
            "no APUMC bundle found below build/*/apu/p5/\n"
            f"prerequisite: {BUNDLE_PREREQUISITE}"
        )
    return candidates[-1].resolve()


def _resolve_apum(apum: Path | None) -> tuple[bytes, str]:
    if apum is not None:
        resolved = apum.resolve()
        if not resolved.is_file():
            raise SystemExit(f"APUM model image not found: {resolved}")
        payload = resolved.read_bytes()
        return payload, str(resolved)
    if not DEFAULT_TFLITE.is_file():
        raise SystemExit(
            f"locked P7 TFLite model not installed: {DEFAULT_TFLITE}\n"
            "prerequisite: make CONFIG=configs/ci/ihp130.mk setup-apu-kws-reference"
        )
    from apu_kws_convert import import_tflite

    payload = import_tflite(DEFAULT_TFLITE)
    return payload, f"generated:{DEFAULT_TFLITE}"


def _wav_payload(rate: int, bits: int, frames: int, seed: int) -> bytes:
    block_align = 2 * (bits // 8)
    state = seed | 1
    data = bytearray()
    for frame in range(frames):
        for channel in range(2):
            state = (1103515245 * state + 12345 + channel + frame) & 0x7FFFFFFF
            value = ((state >> 8) & ((1 << bits) - 1)) - (1 << (bits - 1))
            data.extend(value.to_bytes(bits // 8, "little", signed=True))
    header = bytearray()
    header.extend(b"RIFF")
    header.extend((36 + len(data)).to_bytes(4, "little"))
    header.extend(b"WAVE")
    header.extend(b"fmt ")
    header.extend((16).to_bytes(4, "little"))
    header.extend((1).to_bytes(2, "little"))
    header.extend((2).to_bytes(2, "little"))
    header.extend(rate.to_bytes(4, "little"))
    header.extend((rate * block_align).to_bytes(4, "little"))
    header.extend(block_align.to_bytes(2, "little"))
    header.extend(bits.to_bytes(2, "little"))
    header.extend(b"data")
    header.extend(len(data).to_bytes(4, "little"))
    return bytes(header + data)


def _flac_payload(rate: int, bits: int, block: int) -> bytes:
    streaminfo = bytearray(34)
    streaminfo[0:2] = block.to_bytes(2, "big")
    streaminfo[2:4] = block.to_bytes(2, "big")
    streaminfo[10:18] = ((rate << 44) | ((bits - 1) << 36) | block).to_bytes(8, "big")
    size_code = 4 if bits == 16 else 6
    frame_header = ((0x3FFE << 18) | (7 << 12) | (size_code << 1)).to_bytes(4, "big")
    frame_header += b"\x00" + (block - 1).to_bytes(2, "big")
    frame_header += bytes([crc8(frame_header)])
    frame = frame_header + b"\x00" + FLAC_CONSTANT.to_bytes(bits // 8, "big", signed=True)
    frame += crc16(frame).to_bytes(2, "big")
    return b"fLaC" + bytes([0x80, 0, 0, 34]) + bytes(streaminfo) + frame


def _expected_pcm(
    source: bytes, *, is_wav: bool, rate: int, bits: int, resample: bool
) -> tuple[list[int], int]:
    decoded = decode_wav(source, strict=True) if is_wav else decode_flac(source, strict=True)
    processed = process_pcm(
        decoded, output_rate=rate, output_channels=2, output_bits=bits, resample=resample,
        i2s=True,
    )
    payload = processed.payload
    if len(payload) % 4 != 0:
        raise RuntimeError("BAM PCM payload is not word aligned")
    words = [
        int.from_bytes(payload[offset : offset + 4], "little")
        for offset in range(0, len(payload), 4)
    ]
    return words, processed.frames


def _write_pattern_hex(path: Path, words: list[int]) -> None:
    padded = list(words) + [0] * (16384 - len(words))
    path.write_text("".join(f"{word:08x}\n" for word in padded), encoding="utf-8")


def _compile(build_dir: Path) -> dict[str, Any]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    filelist = build_dir / "apu_p7_concurrent.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                *(str(source) for source in _production_sources()),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = build_dir / "apu_p7_concurrent.v"
    conversion = _run_command(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        timeout=900,
    )
    if conversion["exit_code"] != 0:
        raise RuntimeError(f"sv2v conversion failed: {conversion['stderr'][-2000:]}")
    binary = build_dir / "apu_p7_concurrent_sim"
    icarus = _run_command(
        [
            "iverilog",
            "-g2012",
            "-s",
            "apu_p7_concurrent_tb",
            "-o",
            str(binary),
            str(converted),
        ],
        timeout=900,
    )
    if icarus["exit_code"] != 0:
        raise RuntimeError(f"Icarus compile failed: {icarus['stderr'][-2000:]}")
    result = {
        "status": "passed",
        "filelist": str(filelist),
        "converted": str(converted),
        "converted_sha256": _sha256_file(converted),
        "binary": str(binary),
        "sv2v": conversion,
        "icarus": icarus,
    }
    _write_json(build_dir / "compile.json", result)
    return result


def _kws_schedule(rx_words: int, precision: int, rate: int) -> tuple[int, int, int]:
    words_per_frame = 2 if precision == 24 else 1
    decimation = 6 if rate == 96000 else 3
    samples_16k = (rx_words // words_per_frame) // decimation
    frames = (samples_16k - 480) // 320 + 1 if samples_16k >= 480 else 0
    windows = (samples_16k - 16000) // 1600 + 1 if samples_16k >= 16000 else 0
    return samples_16k, frames, windows


def _check_scenario(
    scenario: dict[str, Any], parsed: dict[str, Any], workloads: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    rate = scenario["rate_hz"]
    precision = scenario["precision_bits"]
    if parsed["scoreboard"] != "match":
        errors.append("testbench scoreboard did not match")
    for field in ("underrun", "rx_overrun", "kws_overrun"):
        if parsed[field] != 0:
            errors.append(f"{field}={parsed[field]} violates the zero-xrun gate")
    expected_rx_words = scenario["duration_cycles"] // scenario["frame_period"]
    if parsed["rx_words"] != expected_rx_words:
        errors.append(f"rx_words={parsed['rx_words']} != expected {expected_rx_words}")
    samples_16k, kws_frames, kws_windows = _kws_schedule(parsed["rx_words"], precision, rate)
    scenario["kws_16k_samples"] = samples_16k
    scenario["expected_kws_frames"] = kws_frames
    scenario["expected_kws_windows"] = kws_windows
    if parsed["kws_frames"] != kws_frames:
        errors.append(f"kws_frames={parsed['kws_frames']} != expected {kws_frames}")
    if parsed["kws_windows"] != kws_windows:
        errors.append(f"kws_windows={parsed['kws_windows']} != expected {kws_windows}")
    if parsed["jobs"] != parsed["wav_jobs"] + parsed["flac_jobs"]:
        errors.append("job accounting mismatch")
    if parsed["wav_jobs"] < 1 or parsed["flac_jobs"] < 1:
        errors.append("WAV and FLAC workloads must both run in every scenario")
    expected_tx = (
        parsed["wav_jobs"] * workloads["wav_out_words"]
        + parsed["flac_jobs"] * workloads["flac_out_words"]
    )
    if parsed["tx_words"] != expected_tx or parsed["consumed"] != expected_tx:
        errors.append(f"tx_words/consumed != expected {expected_tx}")
    expected_input = (
        parsed["wav_jobs"] * workloads["wav_bytes"]
        + parsed["flac_jobs"] * workloads["flac_bytes"]
    )
    if parsed["codec_input_bytes"] != expected_input:
        errors.append(f"codec_input_bytes != expected {expected_input}")
    if parsed["codec_output_bytes"] != expected_tx * 4:
        errors.append(f"codec_output_bytes != expected {expected_tx * 4}")
    expected_frames = (
        parsed["wav_jobs"] * workloads["wav_frames"]
        + parsed["flac_jobs"] * workloads["flac_frames"]
    )
    if parsed["codec_frames"] != expected_frames:
        errors.append(f"codec_frames != expected {expected_frames}")
    return errors


def _run_scenario(
    scenario: dict[str, Any],
    compile_result: dict[str, Any],
    artifacts: dict[str, str],
    workloads: dict[str, Any],
    timeout: int,
) -> dict[str, Any]:
    scenario_dir = Path(artifacts["scenario_dir"])
    log_path = scenario_dir / "run.log"
    command = [
        "vvp",
        compile_result["binary"],
        f"+APUMC_HEX={artifacts['apumc_hex']}",
        f"+APUM_HEX={artifacts['apum_hex']}",
        f"+APUC_HEX={artifacts['apuc_hex']}",
        f"+WAV_HEX={scenario_dir / 'wav.hex'}",
        f"+FLAC_HEX={scenario_dir / 'flac.hex'}",
        f"+WAV_PCM_HEX={scenario_dir / 'wav_pcm.hex'}",
        f"+FLAC_PCM_HEX={scenario_dir / 'flac_pcm.hex'}",
        f"+WAV_BYTES={workloads['wav_bytes']}",
        f"+WAV_FRAMES={workloads['wav_frames']}",
        f"+WAV_OUT_WORDS={workloads['wav_out_words']}",
        f"+WAV_SOURCE_RATE={workloads['wav_source_rate']}",
        f"+FLAC_BYTES={workloads['flac_bytes']}",
        f"+FLAC_FRAMES={workloads['flac_frames']}",
        f"+FLAC_OUT_WORDS={workloads['flac_out_words']}",
        f"+RATE={scenario['rate_hz']}",
        f"+PRECISION={scenario['precision_bits']}",
        f"+DURATION_CYCLES={scenario['duration_cycles']}",
        f"+SECONDS_MS={scenario['seconds_ms']}",
        f"+MAX_CYCLES={scenario['max_cycles']}",
        f"+SEED={scenario['seed']}",
        "+WORKLOAD_MASK=3",
    ]
    execution = _run_command(command, timeout=timeout)
    log_path.write_text(execution["stdout"] + execution["stderr"], encoding="utf-8")
    result: dict[str, Any] = {
        "scenario": scenario["id"],
        "command": command,
        "log": str(log_path),
        "exit_code": execution["exit_code"],
        "timed_out": execution["timed_out"],
        "wall_seconds": execution["duration_seconds"],
        "timeout_seconds": timeout,
        "status": "failed",
        "errors": [],
    }
    match = RESULT_PATTERN.search(execution["stdout"])
    if execution["exit_code"] != 0 or match is None:
        tail = (execution["stdout"] + execution["stderr"]).strip().splitlines()[-8:]
        result["errors"].append(
            "simulator failed" if execution["exit_code"] != 0 else "no CONCURRENT_RESULT line"
        )
        result["log_tail"] = tail
        return result
    parsed: dict[str, Any] = {
        name: int(value) for name, value in match.groupdict().items() if name != "scoreboard"
    }
    parsed["scoreboard"] = match.group("scoreboard")
    result["result"] = parsed
    result["simulated_cycles_per_wall_second"] = (
        round(parsed["elapsed_cycles"] / execution["duration_seconds"], 3)
        if execution["duration_seconds"] > 0
        else None
    )
    errors = _check_scenario(scenario, parsed, workloads)
    result["errors"] = errors
    result["status"] = "passed" if not errors else "failed"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--apumc", type=Path, default=None)
    parser.add_argument("--apum", type=Path, default=None)
    parser.add_argument(
        "--seconds",
        type=float,
        default=0.5,
        help="simulated seconds per scenario; the frozen release gate is 60",
    )
    parser.add_argument("--smoke", action="store_true", help="minimal single-scenario matrix")
    parser.add_argument(
        "--rates",
        type=int,
        nargs="+",
        default=None,
        choices=(48000, 96000),
        help="I2S rates to run (default both, or 48000 in --smoke)",
    )
    parser.add_argument(
        "--precisions",
        type=int,
        nargs="+",
        default=None,
        choices=(16, 24),
        help="output precisions to run (default both, or 16 in --smoke)",
    )
    parser.add_argument(
        "--smoke-seconds",
        type=float,
        default=0.03,
        help="simulated seconds per scenario in --smoke mode (kept short for pytest)",
    )
    parser.add_argument(
        "--job-frames",
        type=int,
        default=None,
        help="stereo frames per WAV/FLAC job (default 512 in --smoke, else 4096)",
    )
    parser.add_argument("--timeout-seconds", type=int, default=14400)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    build_dir = args.build_dir.resolve()
    build_dir.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve() if args.output else build_dir / "concurrent.json"

    for tool in ("iverilog", "vvp", "sv2v"):
        if shutil.which(tool) is None:
            raise SystemExit(f"required tool not on PATH: {tool}")
    if args.seconds <= 0 or args.smoke_seconds <= 0:
        raise SystemExit("--seconds/--smoke-seconds must be positive")
    seconds = args.smoke_seconds if args.smoke else args.seconds
    job_frames = args.job_frames
    if job_frames is None:
        job_frames = 512 if args.smoke else 4096
    if job_frames < 64 or job_frames > 4096:
        raise SystemExit("--job-frames must be within 64..4096")
    apumc_path = _resolve_apumc(args.apumc)
    apumc_payload = apumc_path.read_bytes()
    apum_payload, apum_source = _resolve_apum(args.apum)
    if len(apum_payload) != 32768:
        raise SystemExit(f"APUM image must be 32768 bytes, got {len(apum_payload)}")
    apum_sha256 = _sha256_bytes(apum_payload)
    apum_matches_freeze = apum_sha256 == APUM_SHA256

    if args.smoke and (args.rates is not None or args.precisions is not None):
        raise SystemExit("--smoke selects its own minimal matrix; do not combine with --rates/--precisions")
    rates = tuple(args.rates) if args.rates is not None else ((48000,) if args.smoke else (48000, 96000))
    precisions = (
        tuple(args.precisions) if args.precisions is not None else ((16,) if args.smoke else (16, 24))
    )
    scenarios: list[dict[str, Any]] = []
    for rate in rates:
        for precision in precisions:
            precision_id = "s16" if precision == 16 else "s24_32"
            duration_cycles = int(round(seconds * PCLK_HZ))
            frame_period = PCLK_HZ // rate // (2 if precision == 24 else 1)
            if duration_cycles % frame_period != 0:
                raise SystemExit(
                    f"--seconds {seconds} does not divide the {rate}-Hz/{precision}-bit "
                    "I2S frame cadence; choose a duration with millisecond resolution"
                )
            # WAV workload: the P5-qualified playback shapes. A 44.1 kHz
            # stereo S16 source resampled to 48 kHz for the 48 kHz I2S
            # scenarios, and an 8 kHz stereo S16 source resampled to 96 kHz
            # for the 96 kHz scenarios (the PLAYBACK_44100_48000 /
            # PLAYBACK_8000_96000 qualification shapes). Source frame counts
            # are multiples of 147 for the exact 160/147 output ratio.
            wav_source_rate = 44100 if rate == 48000 else 8000
            if wav_source_rate == 44100:
                wav_source_frames = max(147, 147 * (job_frames // 147))
            else:
                wav_source_frames = job_frames
            wav = _wav_payload(wav_source_rate, 16, wav_source_frames, args.seed)
            flac = _flac_payload(rate, precision, job_frames)
            wav_pcm, wav_frames = _expected_pcm(
                wav, is_wav=True, rate=rate, bits=precision, resample=True
            )
            flac_pcm, flac_frames = _expected_pcm(
                flac, is_wav=False, rate=rate, bits=precision, resample=False
            )
            if flac_frames != job_frames:
                raise SystemExit("FLAC BAM frame count mismatch")
            if len(wav_pcm) != wav_frames * (2 if precision == 24 else 1):
                raise SystemExit("WAV BAM PCM word count mismatch")
            if len(flac_pcm) != flac_frames * (2 if precision == 24 else 1):
                raise SystemExit("FLAC BAM PCM word count mismatch")
            pair_cycles = (wav_frames + flac_frames) * (PCLK_HZ // rate)
            if duration_cycles < pair_cycles:
                raise SystemExit(
                    f"--seconds {seconds} at {rate}-Hz/{precision}-bit cannot fit one "
                    f"WAV+FLAC job pair ({pair_cycles} playback cycles); increase "
                    "--seconds or reduce --job-frames"
                )
            scenarios.append(
                {
                    "id": f"{rate}-{precision_id}",
                    "rate_hz": rate,
                    "precision_bits": precision,
                    "seconds": seconds,
                    "seconds_ms": int(round(seconds * 1000)),
                    "duration_cycles": duration_cycles,
                    "max_cycles": duration_cycles + 400_000_000,
                    "frame_period": frame_period,
                    "seed": args.seed,
                    "wav": wav,
                    "flac": flac,
                    "wav_pcm": wav_pcm,
                    "flac_pcm": flac_pcm,
                    "workloads": {
                        "wav_bytes": len(wav),
                        "flac_bytes": len(flac),
                        "wav_sha256": _sha256_bytes(wav),
                        "flac_sha256": _sha256_bytes(flac),
                        "wav_source_rate": wav_source_rate,
                        "wav_source_frames": wav_source_frames,
                        "wav_frames": wav_frames,
                        "flac_frames": flac_frames,
                        "wav_out_words": len(wav_pcm),
                        "flac_out_words": len(flac_pcm),
                    },
                }
            )

    apumc_hex = build_dir / "apu-p5.hex"
    _hex_words(apumc_hex, apumc_payload, 16384)
    apum_hex = build_dir / "kws-apum.hex"
    _hex_words(apum_hex, apum_payload, 8192)
    apuc_hex = build_dir / "kws-apuc.hex"
    apuc_payload, _layout = build_apuc(apum_payload)
    _hex_words(apuc_hex, apuc_payload, 15376)
    artifacts = {
        "apumc_hex": str(apumc_hex),
        "apum_hex": str(apum_hex),
        "apuc_hex": str(apuc_hex),
        "scenario_dir": "",
    }

    started = time.monotonic()
    compile_result = _compile(build_dir)

    scenario_results: list[dict[str, Any]] = []
    failures: list[str] = []
    for scenario in scenarios:
        scenario_dir = build_dir / "scenarios" / scenario["id"]
        scenario_dir.mkdir(parents=True, exist_ok=True)
        _hex_words(scenario_dir / "wav.hex", scenario["wav"], 8192)
        _hex_words(scenario_dir / "flac.hex", scenario["flac"], 1024)
        _write_pattern_hex(scenario_dir / "wav_pcm.hex", scenario["wav_pcm"])
        _write_pattern_hex(scenario_dir / "flac_pcm.hex", scenario["flac_pcm"])
        workloads = scenario["workloads"]
        artifacts["scenario_dir"] = str(scenario_dir)
        scenario_results.append(
            _run_scenario(scenario, compile_result, artifacts, workloads, args.timeout_seconds)
        )
        status = scenario_results[-1]["status"]
        print(f"APU-P7 concurrent: {scenario['id']} {status}", flush=True)
        _write_json(scenario_dir / "result.json", scenario_results[-1])
        if status != "passed":
            failures.extend(f"{scenario['id']}: {error}" for error in scenario_results[-1]["errors"])

    git_revision, git_dirty = _git_revision()
    cycles_per_second = [
        item["simulated_cycles_per_wall_second"]
        for item in scenario_results
        if item.get("simulated_cycles_per_wall_second")
    ]
    slowest = min(cycles_per_second) if cycles_per_second else None
    projected_per_config = (
        round(FULL_GATE_CYCLES / slowest, 1) if slowest else None
    )
    full_matrix_configs = 4
    projection = {
        "full_gate_seconds_per_config": FULL_GATE_SECONDS,
        "full_gate_cycles_per_config": FULL_GATE_CYCLES,
        "full_matrix_configs": full_matrix_configs,
        "measured_min_cycles_per_wall_second": slowest,
        "projected_wall_seconds_per_config": projected_per_config,
        "projected_wall_seconds_full_matrix": (
            round(projected_per_config * full_matrix_configs, 1) if projected_per_config else None
        ),
        "projected_full_matrix_exceeds_12h": (
            bool(projected_per_config * full_matrix_configs > 12 * 3600)
            if projected_per_config
            else None
        ),
    }
    aggregate = {
        "scenarios": len(scenario_results),
        "jobs": sum(item["result"]["jobs"] for item in scenario_results if "result" in item),
        "codec_underruns": sum(
            item["result"]["underrun"] for item in scenario_results if "result" in item
        ),
        "rx_overruns": sum(
            item["result"]["rx_overrun"] for item in scenario_results if "result" in item
        ),
        "kws_overruns": sum(
            item["result"]["kws_overrun"] for item in scenario_results if "result" in item
        ),
        "codec_input_bytes": sum(
            item["result"]["codec_input_bytes"] for item in scenario_results if "result" in item
        ),
        "codec_output_bytes": sum(
            item["result"]["codec_output_bytes"] for item in scenario_results if "result" in item
        ),
        "codec_frames": sum(
            item["result"]["codec_frames"] for item in scenario_results if "result" in item
        ),
        "codec_cycles": sum(
            item["result"]["codec_cycles"] for item in scenario_results if "result" in item
        ),
    }
    report = {
        "schema_version": 1,
        "phase": "APU-P7",
        "report": "concurrent",
        "gate": "concurrent WAV/FLAC decode with continuous RX KWS zero-xrun",
        "status": "passed" if not failures else "failed",
        "success": not failures,
        "release_qualifying": bool(
            not failures
            and not args.smoke
            and seconds >= FULL_GATE_SECONDS
            and set(rates) == {48000, 96000}
            and set(precisions) == {16, 24}
        ),
        "mode": "smoke" if args.smoke else "full-matrix",
        "seconds_per_scenario": seconds,
        "job_frames_per_workload": job_frames,
        "required_full_gate_seconds": FULL_GATE_SECONDS,
        "pclk_hz": PCLK_HZ,
        "git_revision": git_revision,
        "git_dirty": git_dirty,
        "command": [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
        "seed": args.seed,
        "profile": PROFILE,
        "bundle_prerequisite": BUNDLE_PREREQUISITE,
        "inputs": {
            "apumc": {
                "path": str(apumc_path),
                "bytes": len(apumc_payload),
                "sha256": _sha256_bytes(apumc_payload),
            },
            "apum": {
                "path": apum_source,
                "bytes": len(apum_payload),
                "sha256": apum_sha256,
                "payload_crc32": f"0x{APUM_PAYLOAD_CRC:08x}",
                "matches_locked_freeze": apum_matches_freeze,
            },
            "tflite": {
                "path": str(DEFAULT_TFLITE),
                "sha256": _sha256_file(DEFAULT_TFLITE) if DEFAULT_TFLITE.is_file() else None,
            },
        },
        "converter": {
            "path": "scripts/apu_kws_convert.py",
            "sha256": _sha256_file(ROOT / "scripts/apu_kws_convert.py"),
            "contract_revision": CONTRACT_REVISION,
        },
        "bam": {
            "path": "scripts/apu_codecs.py",
            "sha256": _sha256_file(ROOT / "scripts/apu_codecs.py"),
        },
        "rtl_revision": git_revision,
        "verification_sources": _verification_sources(),
        "simulator": {
            "name": "icarus",
            "iverilog": _tool_version("iverilog", "-V"),
            "vvp": _tool_version("vvp", "-V"),
        },
        "tools": {
            "sv2v": _tool_version("sv2v", "--version"),
            "python": platform.python_version(),
        },
        "compile": compile_result,
        "harness": {
            "axi_model": "ready memory, no injected stalls",
            "playback_prefill_words": 64,
            "playback_fifo_words": 1024,
            "router_fifo_words": 64,
            "rx_model": "one I2S frame word per cadence tick, never re-presented",
            "kws_config": "0x0180 (threshold 128, debounce 1)",
        },
        "matrix": [
            {
                "scenario": scenario["id"],
                "rate_hz": scenario["rate_hz"],
                "precision_bits": scenario["precision_bits"],
                "seconds": scenario["seconds"],
                "workloads": {
                    "wav": {
                        "shape": "resample" if scenario["workloads"]["wav_source_rate"]
                        != scenario["rate_hz"] else "passthrough",
                        "source_rate_hz": scenario["workloads"]["wav_source_rate"],
                        "source_precision_bits": 16,
                        "source_channels": 2,
                        "source_frames_per_job": scenario["workloads"]["wav_source_frames"],
                        "output_frames_per_job": scenario["workloads"]["wav_frames"],
                        "sha256": scenario["workloads"]["wav_sha256"],
                    },
                    "flac": {
                        "shape": "mono-constant",
                        "rate_hz": scenario["rate_hz"],
                        "precision_bits": scenario["precision_bits"],
                        "block_frames": scenario["workloads"]["flac_frames"],
                        "output_frames_per_job": scenario["workloads"]["flac_frames"],
                        "sha256": scenario["workloads"]["flac_sha256"],
                    },
                },
            }
            for scenario in scenarios
        ],
        "scenarios": scenario_results,
        "aggregate_counts": aggregate,
        "full_gate_projection": projection,
        "artifacts": {
            "build_dir": str(build_dir),
            "apumc_hex": str(apumc_hex),
            "apum_hex": str(apum_hex),
            "report": str(output),
        },
        "errors": failures,
        "wall_seconds": round(time.monotonic() - started, 3),
    }
    _write_json(output, report)
    print(f"APU-P7 concurrent report: {output} ({'passed' if not failures else 'failed'})")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
