#!/usr/bin/env python3
"""Run the locked APU-P7 KWS 1000-window corpus through the production RTL path."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_kws import (  # noqa: E402
    APUM_BYTES,
    APUM_PAYLOAD_CRC,
    APUM_SHA256,
    CORPUS_SHA256,
    TFLITE_SHA256,
    image_sha256,
    parse_apum,
)
from apu_kws_convert import TfliteError, import_tflite  # noqa: E402
from generate_apu_kws_rtl_constants import build_apuc  # noqa: E402
from setup_apu_kws_reference import REQUIRED_ARCHIVE, REQUIRED_SOURCES  # noqa: E402

MANIFEST = ROOT / "docs/ip/apu-kws-corpus.tsv"
PCM_SOURCES = ROOT / ".cache/retrosoc/sources/apu-kws-pcm"
KWS01 = ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
Y_LABELS = KWS01 / "y_labels.csv"
Y_LABELS_SHA256 = "6cb3709762d53fe64eb00eaf4a75796248bb3c1386f1d1f93ccdb07b071e9698"
AGGREGATE_PCM_SHA256 = "abd1ff2c988ac168dd68c29f934d95114d1094d7818d79fe73adb166ac009bee"
TFLITE = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)
FIXTURE = ROOT / "tests/rtl/apu_p7_accuracy_tb.sv"
ROM = ROOT / "rtl/ip/multimedia/apu_kws_rom.svh"
WINDOW_COUNT = 1000
WINDOW_BYTES = 32000
WINDOW_SAMPLES = 16000
MINIMUM_TOP1 = 900
CLASS_COUNT = 12
SETUP_HINT = "install the locked P7 inputs with `make setup-apu-kws-reference`"
RESULT_PATTERN = re.compile(r"^KWS_RESULT (\d+) (\d+) (\d+) (\d+)$", re.MULTILINE)
COMPLETE_PATTERN = re.compile(r"^APU_P7_ACCURACY_COMPLETE windows=(\d+) first=(\d+)$", re.MULTILINE)
VARIANT_PATTERN = re.compile(r"^(?P<profile>.+)-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-[0-9a-f]{6,}$")


class QualificationError(RuntimeError):
    """A locked input, tool, or simulation step failed closed."""


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


def _require_file(path: Path, description: str) -> Path:
    if not path.is_file():
        raise QualificationError(f"missing {description}: {path}; {SETUP_HINT}")
    return path


def _git_identity(paths: list[Path] | None = None) -> dict[str, Any]:
    command = ["git", "-C", str(ROOT)]
    revision = subprocess.run(
        [*command, "rev-parse", "HEAD"], text=True, capture_output=True, check=False
    )
    status_command = [*command, "status", "--porcelain"]
    if paths is not None:
        status_command.extend(("--", *[str(path) for path in paths]))
    status = subprocess.run(status_command, text=True, capture_output=True, check=False)
    return {
        "git_revision": revision.stdout.strip() if revision.returncode == 0 else None,
        "git_dirty": (bool(status.stdout.strip()) if status.returncode == 0 else None),
    }


def _tool_version(command: list[str]) -> str | None:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        return None
    line = (result.stdout or result.stderr).splitlines()
    return line[0].strip() if line else None


def _load_manifest() -> list[dict[str, Any]]:
    _require_file(MANIFEST, "locked PCM manifest")
    raw = MANIFEST.read_bytes()
    text = raw.replace(b"\r\n", b"\n") if b"\r\n" in raw else raw
    if _sha256_bytes(text) != CORPUS_SHA256:
        raise QualificationError(
            f"stale locked PCM manifest: {MANIFEST} canonical-text SHA-256 mismatch; {SETUP_HINT}"
        )
    lines = text.decode("ascii").split("\n")
    if lines[-1] != "":
        raise QualificationError("locked PCM manifest is missing its trailing LF")
    rows = lines[:-1]
    if len(rows) != WINDOW_COUNT:
        raise QualificationError(f"locked PCM manifest has {len(rows)} rows, expected 1000")
    records: list[dict[str, Any]] = []
    for index, row in enumerate(rows):
        fields = row.split("\t")
        if len(fields) != 6:
            raise QualificationError(f"locked PCM manifest row {index} does not have 6 columns")
        bin_name, relpath, class_text, wav_sha256, pcm_sha256 = fields[1:]
        if fields[0] != f"{index:06d}":
            raise QualificationError(f"locked PCM manifest row {index} is out of order")
        if relpath.startswith("/") or ".." in Path(relpath).parts:
            raise QualificationError(f"locked PCM manifest row {index} has an unsafe path")
        class_id = int(class_text)
        if not 0 <= class_id < CLASS_COUNT:
            raise QualificationError(f"locked PCM manifest row {index} class out of range")
        records.append(
            {
                "index": index,
                "bin_name": bin_name,
                "relpath": relpath,
                "class_id": class_id,
                "wav_sha256": wav_sha256,
                "pcm_sha256": pcm_sha256,
            }
        )
    return records


def _load_labels(records: list[dict[str, Any]]) -> list[int]:
    _require_file(Y_LABELS, "official y_labels.csv")
    if _sha256_file(Y_LABELS) != Y_LABELS_SHA256:
        raise QualificationError(f"stale official y_labels.csv: {Y_LABELS}; {SETUP_HINT}")
    lines = Y_LABELS.read_text(encoding="ascii").splitlines()
    if len(lines) != WINDOW_COUNT:
        raise QualificationError(f"official y_labels.csv has {len(lines)} rows, expected 1000")
    labels: list[int] = []
    for record, line in zip(records, lines):
        name, total, label = line.split(",")
        if name != record["bin_name"] or int(total) != CLASS_COUNT:
            raise QualificationError(
                f"official y_labels.csv row {record['index']} does not match the PCM manifest"
            )
        if int(label) != record["class_id"]:
            raise QualificationError(
                f"official y_labels.csv row {record['index']} label disagrees with the PCM manifest"
            )
        labels.append(int(label))
    return labels


def _padded_pcm(record: dict[str, Any]) -> bytes:
    source = _require_file(PCM_SOURCES / record["relpath"], "locked source WAV")
    wav = source.read_bytes()
    if _sha256_bytes(wav) != record["wav_sha256"]:
        raise QualificationError(f"source WAV SHA-256 mismatch: {source}; {SETUP_HINT}")
    if len(wav) < 12 or wav[0:4] != b"RIFF" or wav[8:12] != b"WAVE":
        raise QualificationError(f"source WAV is not RIFF/WAVE: {source}")
    fmt: bytes | None = None
    data: bytes | None = None
    offset = 12
    while offset + 8 <= len(wav):
        chunk_size = struct.unpack_from("<I", wav, offset + 4)[0]
        body = wav[offset + 8 : offset + 8 + chunk_size]
        if len(body) != chunk_size:
            raise QualificationError(f"source WAV chunk is truncated: {source}")
        if wav[offset : offset + 4] == b"fmt ":
            fmt = body
        elif wav[offset : offset + 4] == b"data":
            data = body
        offset += 8 + chunk_size + (chunk_size & 1)
    if fmt is None or len(fmt) < 16 or data is None:
        raise QualificationError(f"source WAV lacks fmt/data chunks: {source}")
    audio_format, channels, rate, _byte_rate, _align, bits = struct.unpack_from("<HHIIHH", fmt)
    if (audio_format, channels, rate, bits) != (1, 1, WINDOW_SAMPLES, 16):
        raise QualificationError(f"source WAV is not mono/16000/S16 PCM: {source}")
    if len(data) > WINDOW_BYTES or len(data) % 2 != 0:
        raise QualificationError(f"source WAV exceeds one 16000-sample window: {source}")
    padded = data + bytes(WINDOW_BYTES - len(data))
    if _sha256_bytes(padded) != record["pcm_sha256"]:
        raise QualificationError(f"padded PCM SHA-256 mismatch for row {record['index']}: {source}")
    return padded


def _write_hex(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(
            f"{int.from_bytes(payload[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(payload), 4)
        ),
        encoding="ascii",
    )


def _production_sources() -> list[Path]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    return [
        common / "interface/axi4_stream_if.sv",
        multimedia / "apu_kws_sram_client.sv",
        multimedia / "apu_kws_coeff_store.sv",
        multimedia / "apu_kws_engine.sv",
        ROOT / "tests/rtl/apu_kws_coeff_fixture.sv",
        FIXTURE,
    ]


def _rtl_inputs() -> list[Path]:
    return [
        *_production_sources(),
        ROOT / "rtl/ip/multimedia/apu_define.svh",
        ROM,
        Path(__file__).resolve(),
    ]


def _verification_sha256() -> str:
    digest = hashlib.sha256()
    for path in sorted(_rtl_inputs()):
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def _subprocess_text(value: str | bytes | None) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value or ""


def _run_command(command: list[str], *, timeout: int | None = None) -> dict[str, Any]:
    started = time.monotonic()
    try:
        process = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
        return {
            "command": command,
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": process.returncode,
            "stdout": process.stdout,
            "stderr": process.stderr,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as error:
        return {
            "command": command,
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": 124,
            "stdout": _subprocess_text(error.stdout),
            "stderr": _subprocess_text(error.stderr),
            "timed_out": True,
        }


def _compile(build_dir: Path, simulator: str) -> dict[str, Any]:
    tools = {name: shutil.which(name) for name in ("sv2v", "iverilog", "vvp")}
    missing = [name for name, path in tools.items() if path is None]
    if missing:
        raise QualificationError(f"missing required simulators: {', '.join(missing)}")
    tools["verilator"] = shutil.which("verilator")
    if simulator == "verilator" and tools["verilator"] is None:
        raise QualificationError("--simulator verilator requires verilator on PATH")
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    filelist = build_dir / "apu_p7_accuracy.fl"
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
    converted = build_dir / "apu_p7_accuracy.v"
    conversion = _run_command(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ]
    )
    if conversion["exit_code"] != 0:
        raise QualificationError(f"APU-P7 accuracy sv2v failed: {conversion['stderr']}")
    simv = build_dir / "apu_p7_accuracy_simv"
    compile_result = _run_command(
        [tools["iverilog"], "-g2012", "-s", "apu_p7_accuracy_tb", "-o", str(simv), str(converted)]
    )
    if compile_result["exit_code"] != 0:
        raise QualificationError(f"APU-P7 accuracy Icarus compile failed: {compile_result['stderr']}")
    verilator_binary: Path | None = None
    verilator_log: dict[str, Any] | None = None
    if tools["verilator"] is not None:
        verilator_dir = build_dir / "verilator"
        ccache_dir = build_dir / "ccache"
        ccache_dir.mkdir(exist_ok=True)
        environment = {
            **os.environ,
            "CCACHE_DIR": str(ccache_dir),
            "CCACHE_TEMPDIR": str(ccache_dir),
        }
        started = time.monotonic()
        process = subprocess.run(
            [
                str(tools["verilator"]),
                "--binary",
                "--timing",
                "-O3",
                "-Wno-fatal",
                "--top-module",
                "apu_p7_accuracy_tb",
                "--Mdir",
                str(verilator_dir),
                str(converted),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        verilator_log = {
            "command": list(process.args),
            "duration_seconds": round(time.monotonic() - started, 3),
            "exit_code": process.returncode,
            "stdout": process.stdout,
            "stderr": process.stderr,
        }
        if process.returncode != 0:
            if simulator == "verilator":
                raise QualificationError(
                    f"APU-P7 accuracy Verilator compile failed: {process.stderr}"
                )
        else:
            verilator_binary = verilator_dir / "Vapu_p7_accuracy_tb"
    if simulator == "verilator" and verilator_binary is None:
        raise QualificationError("Verilator compile did not produce a simulation binary")
    return {
        "tools": tools,
        "filelist": filelist,
        "converted": converted,
        "simv": simv,
        "verilator": verilator_binary,
        "sv2v_log": conversion,
        "iverilog_log": compile_result,
        "verilator_log": verilator_log,
    }


def _profile_name(build_dir: Path, override: str | None) -> str:
    if override:
        return override
    parts = build_dir.resolve().parts
    if len(parts) >= 4 and parts[-2:] == ("apu", "kws") and parts[-4] == "build":
        match = VARIANT_PATTERN.match(parts[-3])
        if match:
            return match.group("profile")
    return "standalone"


def _parse_predictions(stdout: str, window_count: int) -> list[dict[str, int]]:
    predictions: dict[int, dict[str, int]] = {}
    for match in RESULT_PATTERN.finditer(stdout):
        index, class_id, score, hit = (int(value) for value in match.groups())
        if index in predictions:
            raise QualificationError(f"duplicated utterance index {index} in simulator output")
        if class_id >= CLASS_COUNT:
            raise QualificationError(f"simulator emitted invalid class {class_id}")
        predictions[index] = {"index": index, "predicted": class_id, "score": score, "hit": hit}
    complete = COMPLETE_PATTERN.search(stdout)
    if complete is None or int(complete.group(1)) != window_count or int(complete.group(2)) != 0:
        raise QualificationError("simulator did not emit the expected completion marker")
    expected = set(range(window_count))
    observed = set(predictions)
    if observed != expected:
        raise QualificationError(
            f"skipped utterances: missing {sorted(expected - observed)[:8]} "
            f"unexpected {sorted(observed - expected)[:8]}"
        )
    return [predictions[index] for index in sorted(predictions)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--max-windows", type=int, default=0,
                        help="run only the first N locked windows (0 = all 1000)")
    parser.add_argument("--report", type=str, default="accuracy.json")
    parser.add_argument("--profile", type=str, default=None)
    parser.add_argument("--timeout-seconds", type=int, default=21600)
    parser.add_argument("--max-window-cycles", type=int, default=4000000)
    parser.add_argument(
        "--simulator",
        choices=("auto", "iverilog", "verilator"),
        default="auto",
        help="run simulator; auto prefers Verilator (Icarus is ~400x slower per window)",
    )
    args = parser.parse_args()
    if not 0 <= args.max_windows <= WINDOW_COUNT:
        raise SystemExit("--max-windows must be within 0..1000")
    window_count = WINDOW_COUNT if args.max_windows == 0 else args.max_windows
    build_dir = args.build_dir.resolve()
    started_utc = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    report_path = build_dir / args.report

    try:
        records = _load_manifest()
        labels = _load_labels(records)
        image = import_tflite(_require_file(TFLITE, "locked kws_ref_model.tflite"))
        parse_apum(image)
        pcm_dir = build_dir / "pcm"
        aggregate = hashlib.sha256()
        for record in records[:window_count]:
            padded = _padded_pcm(record)
            aggregate.update(padded)
            _write_hex(pcm_dir / f"pcm_{record['index']:06d}.hex", padded)
        aggregate_sha256 = aggregate.hexdigest()
        if window_count == WINDOW_COUNT and aggregate_sha256 != AGGREGATE_PCM_SHA256:
            raise QualificationError(
                "aggregate padded PCM SHA-256 does not match the frozen 1000-window value"
            )
        apum_hex = build_dir / "kws_apum.hex"
        _write_hex(apum_hex, image)
        apuc_hex = build_dir / "kws_apuc.hex"
        apuc, _layout = build_apuc(image)
        _write_hex(apuc_hex, apuc)
        built = _compile(build_dir, args.simulator)
    except (OSError, TfliteError, ValueError, QualificationError) as error:
        raise SystemExit(str(error)) from error

    selected = (
        "verilator"
        if (args.simulator == "verilator" or (args.simulator == "auto" and built["verilator"]))
        else "icarus"
    )
    plusargs = [
        f"+APUM_HEX={apum_hex}",
        f"+APUC_HEX={apuc_hex}",
        f"+PCM_DIR={pcm_dir}",
        f"+WINDOW_COUNT={window_count}",
        "+FIRST_INDEX=0",
        f"+MAX_WINDOW_CYCLES={args.max_window_cycles}",
    ]
    command = (
        [str(built["verilator"]), *plusargs]
        if selected == "verilator"
        else [str(built["tools"]["vvp"]), str(built["simv"]), *plusargs]
    )
    execution = _run_command(command, timeout=args.timeout_seconds)
    log_path = build_dir / "sim.log"
    log_path.write_text(execution["stdout"] + execution["stderr"], encoding="utf-8")

    failure: str | None = None
    predictions: list[dict[str, int]] = []
    if execution["timed_out"]:
        failure = f"simulator timeout after {args.timeout_seconds} seconds"
    elif execution["exit_code"] != 0:
        failure = f"simulator failed with exit code {execution['exit_code']}"
    else:
        try:
            predictions = _parse_predictions(execution["stdout"], window_count)
        except QualificationError as error:
            failure = str(error)

    for prediction in predictions:
        prediction["expected"] = labels[prediction["index"]]
    correct = sum(1 for item in predictions if item["predicted"] == item["expected"])
    incorrect = [item["index"] for item in predictions if item["predicted"] != item["expected"]]
    per_class = [
        {"class_id": class_id, "total": 0, "correct": 0, "incorrect": 0}
        for class_id in range(CLASS_COUNT)
    ]
    confusion = [[0] * CLASS_COUNT for _ in range(CLASS_COUNT)]
    for item in predictions:
        expected, predicted = item["expected"], item["predicted"]
        confusion[expected][predicted] += 1
        per_class[expected]["total"] += 1
        if expected == predicted:
            per_class[expected]["correct"] += 1
        else:
            per_class[expected]["incorrect"] += 1
    gate_applies = window_count == WINDOW_COUNT
    gate_passed = correct >= MINIMUM_TOP1
    success = failure is None and (not gate_applies or gate_passed)
    if failure is None and gate_applies and not gate_passed:
        failure = f"top-1 accuracy {correct}/1000 is below the required 900/1000"

    rtl_inputs = _rtl_inputs()
    report: dict[str, Any] = {
        "schema_version": 1,
        "report": "accuracy",
        "target": "p7",
        "profile": _profile_name(build_dir, args.profile),
        "success": success,
        "failure": failure,
        "gate": {
            "window_count": WINDOW_COUNT,
            "minimum_top1": MINIMUM_TOP1,
            "applies": gate_applies,
            "passed": gate_passed if gate_applies else None,
        },
        "seed": 0,
        "command": [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
        "started_utc": started_utc,
        "duration_seconds": round(time.monotonic() - started, 3),
        "counts": {
            "windows_requested": window_count,
            "windows_completed": len(predictions),
            "top1_correct": correct,
            "top1_accuracy": round(correct / len(predictions), 6) if predictions else 0.0,
            "hits": sum(item["hit"] for item in predictions),
            "incorrect": len(incorrect),
        },
        "per_class": per_class,
        "confusion_matrix": confusion,
        "incorrect_indices": incorrect,
        "predictions": predictions,
        "inputs": {
            "manifest": {
                "path": str(MANIFEST.relative_to(ROOT)),
                "sha256": CORPUS_SHA256,
            },
            "y_labels": {"path": str(Y_LABELS.relative_to(ROOT)), "sha256": Y_LABELS_SHA256},
            "tflite": {"path": str(TFLITE.relative_to(ROOT)), "sha256": TFLITE_SHA256},
            "pcm_sources": {
                "path": str(PCM_SOURCES.relative_to(ROOT)),
                "windows": window_count,
                "source_sha256_verified": True,
                "padded_pcm_sha256_verified": True,
                "aggregate_padded_pcm_sha256": aggregate_sha256,
            },
            "reference_sources": REQUIRED_SOURCES,
            "reference_archives": REQUIRED_ARCHIVE,
        },
        "converter": {
            "path": "scripts/apu_kws_convert.py",
            "sha256": _sha256_file(ROOT / "scripts/apu_kws_convert.py"),
            "contract_revision": "apu-kws-convert/1.0.0",
            **_git_identity(),
        },
        "reference": {
            "path": "scripts/apu_kws.py",
            "sha256": _sha256_file(ROOT / "scripts/apu_kws.py"),
        },
        "rtl": {
            **_git_identity(rtl_inputs),
            "fixture": str(FIXTURE.relative_to(ROOT)),
            "verification_sha256": _verification_sha256(),
            "sources": [
                {"path": str(path.relative_to(ROOT)), "sha256": _sha256_file(path)}
                for path in rtl_inputs
            ],
        },
        "model": {
            "apum_sha256": image_sha256(image),
            "payload_crc": f"0x{APUM_PAYLOAD_CRC:08x}",
            "bytes": APUM_BYTES,
            "frozen_sha256": APUM_SHA256,
        },
        "rom": {"path": str(ROM.relative_to(ROOT)), "sha256": _sha256_file(ROM)},
        "tools": {
            "python": sys.version.split()[0],
            "sv2v": _tool_version([str(built["tools"]["sv2v"]), "--version"]),
            "iverilog": _tool_version([str(built["tools"]["iverilog"]), "-V"]),
            "vvp": _tool_version([str(built["tools"]["vvp"]), "-V"]),
            "verilator": (
                _tool_version([str(built["tools"]["verilator"]), "--version"])
                if built["tools"]["verilator"] is not None
                else None
            ),
        },
        "simulation": {
            "simulator": selected,
            "command": command,
            "exit_code": execution["exit_code"],
            "timed_out": execution["timed_out"],
            "duration_seconds": execution["duration_seconds"],
            "log": str(log_path),
        },
        "artifacts": {
            "build_dir": str(build_dir),
            "report": str(report_path),
            "apum_hex": str(apum_hex),
            "pcm_dir": str(pcm_dir),
            "filelist": str(built["filelist"]),
            "converted": str(built["converted"]),
            "simv": str(built["simv"]),
            "verilator": str(built["verilator"]) if built["verilator"] is not None else None,
        },
    }
    _write_json(report_path, report)
    if gate_applies:
        verdict = f"gate 900/1000 {'PASS' if gate_passed else 'FAIL'}"
    else:
        verdict = "subset, gate not applied"
    print(f"APU-P7 KWS accuracy: top-1 {correct}/{len(predictions)} ({verdict})")
    print(f"report: {report_path}")
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
