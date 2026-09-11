#!/usr/bin/env python3
"""Run the pinned APU-P5 FLAC corpus through identical production RTL fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
INPUT_BASE = 0x40000000
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
MIGRATABLE_VERIFICATION_SHA256 = {
    "ff529cb4ae848f1dfe05e0f2b9b3d9dc93f2d98e9810e0c48a769b38e85d21dd",
    "5bd8606e74da174cb235eb0fc56b4d5e95a7bf6ab2f0218d466467c052b25ba1",
}
RESULT_PATTERN = re.compile(
    r"APU_P5_CORPUS_RESULT "
    r"status=(?P<status>[0-9a-fA-F]{8}) "
    r"input_used=(?P<input_used>[0-9a-fA-F]{8}) "
    r"output_bytes=(?P<output_bytes>[0-9a-fA-F]{8}) "
    r"frames=(?P<frames>[0-9a-fA-F]{8}) "
    r"source_info=(?P<source_info>[0-9a-fA-F]{8}) "
    r"cycles=(?P<cycles>[0-9a-fA-F]{8}) "
    r"detail=(?P<detail>[0-9a-fA-F]{8}) "
    r"error_status=(?P<error_status>[0-9a-fA-F]{8}) "
    r"error_address=(?P<error_address>[0-9a-fA-F]{8}) "
    r"error_detail=(?P<error_detail>[0-9a-fA-F]{8}) "
    r"elapsed=(?P<elapsed>[0-9]+)"
)
RESULT_FIELDS = (
    "status",
    "input_used",
    "output_bytes",
    "frames",
    "source_info",
    "cycles",
    "detail",
    "error_status",
    "error_address",
    "error_detail",
)


def _subprocess_text(value: str | bytes | None) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value or ""


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


def _run_command(command: list[str], *, cwd: Path, timeout: int | None = None) -> dict[str, Any]:
    started = time.monotonic()
    try:
        process = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        exit_code = process.returncode
        stdout = process.stdout
        stderr = process.stderr
        timed_out = False
    except subprocess.TimeoutExpired as error:
        exit_code = 124
        stdout = _subprocess_text(error.stdout)
        stderr = _subprocess_text(error.stderr)
        timed_out = True
    return {
        "command": command,
        "duration_seconds": round(time.monotonic() - started, 3),
        "exit_code": exit_code,
        "stdout": stdout,
        "stderr": stderr,
        "timed_out": timed_out,
    }


def _production_sources() -> list[Path]:
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    names = (
        "apu_microcode_pkg.sv",
        "apu_dma.sv",
        "apu_ring_scheduler.sv",
        "apu_stream_router.sv",
        "apu_control_store.sv",
        "apu_microcode_loader.sv",
        "apu_local_sram.sv",
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
        ROOT / "tests/rtl/apu_p5_corpus_tb.sv",
    ]


def _verification_sha256() -> str:
    inputs = [
        *_production_sources(),
        ROOT / "rtl/ip/multimedia/apu_define.svh",
        Path(__file__).resolve(),
    ]
    digest = hashlib.sha256()
    for path in sorted(inputs):
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def _truth_sha256(record: dict[str, Any]) -> str:
    """Hash the canonical BAM/libFLAC truth fields for one corpus record."""
    truth_record = dict(record)
    truth_record.pop("production_rtl", None)
    canonical = json.dumps(truth_record, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _compile(build_dir: Path, bundle: Path) -> tuple[dict[str, Path], dict[str, Any]]:
    tools = {name: shutil.which(name) for name in ("iverilog", "vvp", "verilator")}
    missing = [name for name, path in tools.items() if path is None]
    if missing:
        raise RuntimeError(f"missing required APU-P5 corpus tools: {', '.join(missing)}")
    build_dir.mkdir(parents=True, exist_ok=True)
    multimedia = ROOT / "rtl/ip/multimedia"
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    filelist = build_dir / "apu_p5_corpus.fl"
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
    converted = build_dir / "apu_p5_corpus.v"
    conversion = _run_command(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        cwd=ROOT,
    )
    if conversion["exit_code"] != 0:
        raise RuntimeError(f"APU-P5 corpus sv2v failed: {conversion['stderr']}")

    image_hex = build_dir / "apu-p5.hex"
    payload = bundle.read_bytes()
    image_hex.write_text(
        "".join(
            f"{int.from_bytes(payload[offset : offset + 4].ljust(4, bytes(1)), 'little'):08x}\n"
            for offset in range(0, 16384 * 4, 4)
        ),
        encoding="utf-8",
    )
    icarus_binary = build_dir / "apu_p5_corpus_icarus"
    icarus = _run_command(
        [
            str(tools["iverilog"]),
            "-g2012",
            "-s",
            "apu_p5_corpus_tb",
            "-o",
            str(icarus_binary),
            str(converted),
        ],
        cwd=ROOT,
    )
    if icarus["exit_code"] != 0:
        raise RuntimeError(f"APU-P5 corpus Icarus compile failed: {icarus['stderr']}")

    verilator_dir = build_dir / "verilator"
    ccache_dir = build_dir / "ccache"
    ccache_dir.mkdir(exist_ok=True)
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    started = time.monotonic()
    verilator = subprocess.run(
        [
            str(tools["verilator"]),
            "--binary",
            "--timing",
            "-O3",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_corpus_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )
    verilator_result = {
        "command": verilator.args,
        "duration_seconds": round(time.monotonic() - started, 3),
        "exit_code": verilator.returncode,
        "stdout": verilator.stdout,
        "stderr": verilator.stderr,
    }
    if verilator.returncode != 0:
        raise RuntimeError(f"APU-P5 corpus Verilator compile failed: {verilator.stderr}")
    compile_result = {
        "schema_version": 1,
        "status": "passed",
        "bundle_sha256": _sha256_file(bundle),
        "verification_sha256": _verification_sha256(),
        "fixture": "tests/rtl/apu_p5_corpus_tb.sv",
        "production_sources": [str(path.relative_to(ROOT)) for path in _production_sources()],
        "sv2v": conversion,
        "icarus": icarus,
        "verilator": verilator_result,
    }
    _write_json(build_dir / "result-compile.json", compile_result)
    return {
        "image": image_hex,
        "vvp": Path(str(tools["vvp"])),
        "icarus": icarus_binary,
        "verilator": verilator_dir / "Vapu_p5_corpus_tb",
    }, compile_result


def _case_id(index: int, record: dict[str, Any]) -> str:
    digest = record["sha256"][:12]
    return f"{index:03d}-{digest}"


def _can_reuse_result(
    cached: dict[str, Any],
    source_sha256: str,
    bundle_sha256: str,
    verification_sha256: str,
    truth_sha256: str,
) -> bool:
    return (
        cached.get("status") == "passed"
        and cached.get("source_sha256") == source_sha256
        and cached.get("bundle_sha256") == bundle_sha256
        and cached.get("verification_sha256") == verification_sha256
        and cached.get("truth_sha256") == truth_sha256
    )


def _can_migrate_pass_result(
    cached: dict[str, Any],
    source_sha256: str,
    bundle_sha256: str,
    truth_sha256: str,
) -> bool:
    """Reuse a pass from the pre-WALLCLOCK_NS fixture after a harness-only fix."""
    command = cached.get("command", [])
    return (
        cached.get("status") == "passed"
        and cached.get("source_sha256") == source_sha256
        and cached.get("bundle_sha256") == bundle_sha256
        and cached.get("verification_sha256") in MIGRATABLE_VERIFICATION_SHA256
        and cached.get("truth_sha256") == truth_sha256
        and isinstance(command, list)
        and "+WALLCLOCK_NS=0" not in command
    )


def _case_parameters(record: dict[str, Any], source: Path) -> dict[str, int]:
    truth = record["production_truth"]
    geometry = record.get("geometry")
    bits = int(geometry["bits"]) if geometry is not None else 16
    pcm_format = 1 if bits == 24 else 0
    samples = int(geometry.get("samples") or 0) if geometry is not None else 0
    channels = int(geometry["channels"]) if geometry is not None else 2
    potential_output = samples * channels * (4 if bits == 24 else 2)
    fallback_output = min(0x0FFFFFFC, max(4, source.stat().st_size * 16))
    output_capacity = max(4, int(truth["output_bytes"]), potential_output, fallback_output)
    output_capacity = min(0x0FFFFFFC, (output_capacity + 3) & ~3)
    estimated_cycles = max(
        5_000_000,
        samples * 5000,
        source.stat().st_size * 200,
    )
    return {
        "input_bytes": source.stat().st_size,
        "input_config": 0,
        "output_config": pcm_format << 19,
        "output_capacity": output_capacity,
        "max_cycles": min(1_900_000_000, estimated_cycles),
    }


def _parse_result(stdout: str) -> dict[str, int]:
    match = RESULT_PATTERN.search(stdout)
    if match is None:
        raise RuntimeError("simulator did not emit APU_P5_CORPUS_RESULT")
    result = {name: int(match.group(name), 16) for name in RESULT_FIELDS}
    result["elapsed"] = int(match.group("elapsed"), 10)
    return result


def _record_execution_failure(
    *,
    simulator: str,
    source_sha256: str,
    bundle_sha256: str,
    verification_sha256: str,
    truth_sha256: str,
    command: list[str],
    timeout: int,
    max_cycles: int,
    log_path: Path,
    duration_seconds: float,
    reason: str,
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "status": "failed",
        "simulator": simulator,
        "source_sha256": source_sha256,
        "bundle_sha256": bundle_sha256,
        "verification_sha256": verification_sha256,
        "truth_sha256": truth_sha256,
        "command": command,
        "timeout_seconds": timeout,
        "max_cycles": max_cycles,
        "duration_seconds": duration_seconds,
        "log": str(log_path),
        "execution_errors": [reason],
    }


def _check_truth(record: dict[str, Any], result: dict[str, int], pcm_sha256: str) -> None:
    truth = record["production_truth"]
    success = truth["status"] == "success"
    if bool(result["status"] & (1 << 1)) != success:
        raise RuntimeError("JOB_STATUS.DONE does not match BAM")
    if bool(result["status"] & (1 << 2)) == success:
        raise RuntimeError("JOB_STATUS.ERROR does not match BAM")
    expected_code = int(truth["code"])
    expected_stage = int(truth["stage"])
    expected_detail = (2 << 24) | (int(truth["warnings"]) << 16) | int(truth["reason"])
    if ((result["status"] >> 8) & 0x3F) != expected_code:
        raise RuntimeError("JOB_STATUS error code does not match BAM")
    if ((result["status"] >> 14) & 0xF) != expected_stage:
        raise RuntimeError("JOB_STATUS stage does not match BAM")
    if result["detail"] != expected_detail:
        raise RuntimeError("JOB_DETAIL does not match BAM")
    for field in ("input_used", "output_bytes", "frames", "source_info"):
        if truth[field] is not None and result[field] != int(truth[field]):
            raise RuntimeError(f"{field} does not match BAM")
    if pcm_sha256 != truth["pcm_sha256"]:
        raise RuntimeError("PCM SHA-256 does not match BAM")
    if success:
        if result["error_status"] & 1:
            raise RuntimeError("successful corpus job unexpectedly set first error")
    else:
        if not result["error_status"] & 1:
            raise RuntimeError("failed corpus job did not set first error")
        if ((result["error_status"] >> 1) & 0x3F) != expected_code:
            raise RuntimeError("ERROR_STATUS code does not match BAM")
        if ((result["error_status"] >> 7) & 0xF) != expected_stage:
            raise RuntimeError("ERROR_STATUS stage does not match BAM")
        if result["error_address"] != INPUT_BASE + int(truth["error_offset"]):
            raise RuntimeError("ERROR_ADDRESS does not match BAM")
        if result["error_detail"] != expected_detail:
            raise RuntimeError("ERROR_DETAIL does not match BAM")


def _run_case(
    simulator: str,
    executable: Path,
    vvp: Path,
    image: Path,
    source: Path,
    record: dict[str, Any],
    case_dir: Path,
    timeout: int,
    bundle_sha256: str,
    verification_sha256: str,
) -> dict[str, Any]:
    result_path = case_dir / f"result-{simulator}.json"
    source_sha256 = record["sha256"]
    truth_sha256 = _truth_sha256(record)
    if result_path.is_file():
        cached = json.loads(result_path.read_text(encoding="utf-8"))
        if _can_reuse_result(
            cached, source_sha256, bundle_sha256, verification_sha256, truth_sha256
        ):
            return cached
        if _can_migrate_pass_result(cached, source_sha256, bundle_sha256, truth_sha256):
            cached["migrated_from_verification_sha256"] = cached["verification_sha256"]
            cached["migration_reason"] = "wallclock-and-sequential-output-harness-only"
            cached["verification_sha256"] = verification_sha256
            cached["truth_sha256"] = truth_sha256
            _write_json(result_path, cached)
            return cached
    parameters = _case_parameters(record, source)
    output = case_dir / f"output-{simulator}.pcm"
    command = ([str(vvp), str(executable)] if simulator == "icarus" else [str(executable)]) + [
        f"+IMAGE={image}",
        f"+INPUT={source}",
        f"+OUTPUT={output}",
        f"+INPUT_BYTES={parameters['input_bytes']}",
        f"+INPUT_CONFIG={parameters['input_config']:x}",
        f"+OUTPUT_CONFIG={parameters['output_config']:x}",
        f"+OUTPUT_CAPACITY={parameters['output_capacity']}",
        f"+MAX_CYCLES={parameters['max_cycles']}",
        "+WALLCLOCK_NS=0",
    ]
    execution = _run_command(command, cwd=ROOT, timeout=timeout)
    log_path = case_dir / f"{simulator}.log"
    log_path.write_text(execution["stdout"] + execution["stderr"], encoding="utf-8")
    if execution["exit_code"] != 0:
        result = _record_execution_failure(
            simulator=simulator,
            source_sha256=source_sha256,
            bundle_sha256=bundle_sha256,
            verification_sha256=verification_sha256,
            truth_sha256=truth_sha256,
            command=command,
            timeout=timeout,
            max_cycles=parameters["max_cycles"],
            log_path=log_path,
            duration_seconds=execution["duration_seconds"],
            reason="simulator timeout" if execution["timed_out"] else "simulator failed",
        )
        _write_json(result_path, result)
        return result
    try:
        parsed = _parse_result(execution["stdout"])
    except RuntimeError as error:
        result = _record_execution_failure(
            simulator=simulator,
            source_sha256=source_sha256,
            bundle_sha256=bundle_sha256,
            verification_sha256=verification_sha256,
            truth_sha256=truth_sha256,
            command=command,
            timeout=timeout,
            max_cycles=parameters["max_cycles"],
            log_path=log_path,
            duration_seconds=execution["duration_seconds"],
            reason=str(error),
        )
        _write_json(result_path, result)
        return result
    pcm_sha256 = _sha256_file(output) if output.is_file() else EMPTY_SHA256
    output_size = output.stat().st_size if output.is_file() else 0
    if output_size != parsed["output_bytes"]:
        result = _record_execution_failure(
            simulator=simulator,
            source_sha256=source_sha256,
            bundle_sha256=bundle_sha256,
            verification_sha256=verification_sha256,
            truth_sha256=truth_sha256,
            command=command,
            timeout=timeout,
            max_cycles=parameters["max_cycles"],
            log_path=log_path,
            duration_seconds=execution["duration_seconds"],
            reason=(
                f"{simulator} output size {output_size} does not match "
                f"RESULT_OUTPUT_BYTES {parsed['output_bytes']}"
            ),
        )
        if output.is_file():
            output.unlink()
        _write_json(result_path, result)
        return result
    truth_errors: list[str] = []
    try:
        _check_truth(record, parsed, pcm_sha256)
    except RuntimeError as error:
        truth_errors.append(str(error))
    if output.is_file():
        output.unlink()
    result = {
        "schema_version": 1,
        "status": "passed" if not truth_errors else "failed",
        "simulator": simulator,
        "source_sha256": source_sha256,
        "bundle_sha256": bundle_sha256,
        "verification_sha256": verification_sha256,
        "truth_sha256": truth_sha256,
        "command": command,
        "timeout_seconds": timeout,
        "max_cycles": parameters["max_cycles"],
        "duration_seconds": execution["duration_seconds"],
        "log": str(log_path),
        "pcm_sha256": pcm_sha256,
        "result": parsed,
        "truth_errors": truth_errors,
    }
    _write_json(result_path, result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument(
        "--category", action="append", choices=("supported", "unsupported", "malformed"), default=[]
    )
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=int, default=14400)
    parser.add_argument("--allow-partial", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.resolve().read_text(encoding="utf-8"))
    bundle = args.bundle.resolve()
    corpus = args.corpus.resolve()
    build_dir = args.build_dir.resolve()
    output = args.output.resolve()
    if args.jobs < 1:
        raise SystemExit("--jobs must be positive")
    records = manifest["files"]
    selected = [
        record
        for record in records
        if (not args.case or record["path"] in args.case)
        and (not args.category or record["expected"] in args.category)
    ]
    unknown = sorted(set(args.case) - {record["path"] for record in selected})
    if unknown:
        raise SystemExit(f"unknown corpus cases: {', '.join(unknown)}")
    if len(selected) != len(records) and not args.allow_partial:
        raise SystemExit("partial corpus selection requires --allow-partial")

    executables, compile_result = _compile(build_dir, bundle)
    bundle_sha256 = compile_result["bundle_sha256"]
    verification_sha256 = compile_result["verification_sha256"]
    work: list[tuple[int, dict[str, Any], str]] = []
    indices = {record["path"]: index for index, record in enumerate(records)}
    for record in selected:
        for simulator in ("icarus", "verilator"):
            work.append((indices[record["path"]], record, simulator))

    results: dict[tuple[str, str], dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = {}
        for index, record, simulator in work:
            case_dir = build_dir / "cases" / _case_id(index, record)
            case_dir.mkdir(parents=True, exist_ok=True)
            future = executor.submit(
                _run_case,
                simulator,
                executables[simulator],
                executables["vvp"],
                executables["image"],
                corpus / record["path"],
                record,
                case_dir,
                args.timeout_seconds,
                bundle_sha256,
                verification_sha256,
            )
            futures[future] = (record["path"], simulator)
        for future in as_completed(futures):
            key = futures[future]
            results[key] = future.result()
            print(f"APU-P5 corpus RTL: {key[1]} {results[key]['status']} {key[0]}", flush=True)

    failures: list[str] = []
    for record in records:
        if record["path"] not in {item["path"] for item in selected}:
            continue
        icarus = results[(record["path"], "icarus")]
        verilator = results[(record["path"], "verilator")]
        agreement = (
            "result" in icarus
            and "result" in verilator
            and all(
                icarus["result"][field] == verilator["result"][field]
                for field in (*RESULT_FIELDS, "elapsed")
            )
            and icarus["pcm_sha256"] == verilator["pcm_sha256"]
        )
        if not agreement:
            failures.append(f"Icarus/Verilator disagreement for {record['path']}")
        for simulator, result in (("icarus", icarus), ("verilator", verilator)):
            if result["status"] != "passed":
                errors = result.get("truth_errors", result.get("execution_errors", []))
                failures.append(
                    f"{simulator} truth mismatch for {record['path']}: " + ", ".join(errors)
                )
        record["production_rtl"] = {
            "agreement": agreement,
            "icarus": icarus,
            "verilator": verilator,
        }
    manifest["production_rtl"] = {
        "schema_version": 1,
        "complete": len(selected) == len(records),
        "case_count": len(selected),
        "simulator_runs": len(work),
        "bundle_sha256": bundle_sha256,
        "fixture": "tests/rtl/apu_p5_corpus_tb.sv",
        "compile_result": str(build_dir / "result-compile.json"),
        "status": "passed" if not failures else "failed",
        "failure_count": len(failures),
        "failures": failures,
    }
    _write_json(output, manifest)
    print(f"APU-P5 production RTL corpus: {len(selected)} files -> {output}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
