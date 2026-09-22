#!/usr/bin/env python3
"""Run the frozen KWS/VWW deployment sets through both production RTL simulators."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

from npu_compiler_p0 import compile_kws, compile_vww, vww_input_bytes  # noqa: E402
from npu_executor import execute_job, relocate_descriptors  # noqa: E402
from test_npu_rtl_p3 import COMMON_SOURCES, MEM_BASE, _build_sim, _tools  # noqa: E402
from test_npu_rtl_p4 import OPERATOR_TB, P4_SOURCES, _image_hex  # noqa: E402

MEMORY_BYTES = 0x80000
KWS_FEATURES = ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
VWW_CORPUS = ROOT / ".cache/retrosoc/sources/npu-vww-corpus"
REJECTED = re.compile(
    r"(?:\bFAIL(?:ED)?\b|\bFATAL\b|assertion failed|%Error|SIM_TEST_FAIL|SIM_TEST_TIMEOUT)",
    re.IGNORECASE,
)


def file_identity(path: Path) -> dict[str, int | str]:
    payload = path.read_bytes()
    return {"path": str(path), "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest()}


def git_identity() -> dict[str, object]:
    revision = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = bool(subprocess.check_output(
        ["git", "-C", str(ROOT), "status", "--porcelain"], text=True
    ).strip())
    return {"revision": revision, "dirty": dirty}


def tool_identity(path: str, version_arg: str) -> dict[str, str]:
    completed = subprocess.run(
        [path, version_arg], text=True, capture_output=True, check=False
    )
    version = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0 or not version:
        raise RuntimeError(f"cannot identify simulator tool: {path}")
    return {"path": path, "version": version}


def rejected_markers(log: str) -> list[str]:
    return sorted({match.group(0) for match in REJECTED.finditer(log)})


def align(value: int, boundary: int = 64) -> int:
    return (value + boundary - 1) & ~(boundary - 1)


def samples() -> dict[str, list[Path]]:
    kws = json.loads((ROOT / "docs/ip/npu-kws-manifest.json").read_text())
    vww = json.loads((ROOT / "docs/ip/npu-vww-manifest.json").read_text())
    kws_hashes = {item["name"]: item["sha256"] for item in kws["inputs"]}
    paths = {"kws": [KWS_FEATURES / name for name in kws["rtl_sample_ids"]], "vww": []}
    by_name = {}
    vww_hashes = {}
    for line in (ROOT / "docs/ip/npu-vww-corpus.tsv").read_text().splitlines():
        _index, name, jpeg, _label, _jpeg_sha, bin_sha = line.split("\t")
        by_name[name] = VWW_CORPUS / Path(jpeg).parent / name
        vww_hashes[name] = bin_sha
    paths["vww"] = [by_name[name] for name in vww["rtl_sample_ids"]]
    frozen = {
        "kws": [line.split("\t")[1]
                for line in (ROOT / "docs/ip/apu-kws-corpus.tsv").read_text().splitlines()],
        "vww": [line.split("\t")[1]
                for line in (ROOT / "docs/ip/npu-vww-corpus.tsv").read_text().splitlines()],
    }
    for workload, selected in paths.items():
        if len(selected) != 10 or len({path.name for path in selected}) != 10:
            raise RuntimeError(f"{workload} must provide ten distinct frozen RTL samples")
        if [path.name for path in selected] != sorted(frozen[workload])[:10]:
            raise RuntimeError(f"{workload} RTL samples are not the first ten bytewise IDs")
        for path in selected:
            if not path.is_file():
                raise RuntimeError(f"missing required {workload} input: {path}")
            expected_hash = (kws_hashes if workload == "kws" else vww_hashes)[path.name]
            actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual_hash != expected_hash:
                raise RuntimeError(
                    f"{workload} frozen input hash mismatch for {path.name}: {actual_hash}"
                )
    return paths


def emit_case(directory: Path, workload: str, path: Path, case_index: int) -> tuple[list[str], dict]:
    job = compile_kws() if workload == "kws" else compile_vww()
    source_data = path.read_bytes()
    input_data = source_data if workload == "kws" else vww_input_bytes(source_data)
    descriptor_offset = 0
    weights_offset = align(len(job.descriptors) * 128)
    params_offset = align(weights_offset + len(job.weights))
    arena_offset = align(params_offset + len(job.params))
    end = arena_offset + job.arena_bytes
    if end > MEMORY_BYTES:
        raise RuntimeError(f"{workload} deployment needs {end} bytes, BFM has {MEMORY_BYTES}")
    bases = {
        "descriptors": MEM_BASE + descriptor_offset,
        "weights": MEM_BASE + weights_offset,
        "params": MEM_BASE + params_offset,
        "arena": MEM_BASE + arena_offset,
    }
    descriptors = relocate_descriptors(job, bases)
    memory = bytearray([0xA5] * MEMORY_BYTES)
    for index, descriptor in enumerate(descriptors):
        memory[index * 128:(index + 1) * 128] = descriptor.to_bytes()
    memory[weights_offset:weights_offset + len(job.weights)] = job.weights
    memory[params_offset:params_offset + len(job.params)] = job.params
    memory[arena_offset + job.input_offset:arena_offset + job.input_offset + len(input_data)] = input_data
    result = execute_job(job, input_data, bases=bases)
    npu_layers = result.layers[:len(descriptors)]
    trace = []
    for descriptor, tensor in zip(descriptors, npu_layers, strict=True):
        block = bytes(value & 0xFF for value in tensor.data)
        for tile_y in range(0, descriptor.oh, descriptor.tile_h):
            rows = min(descriptor.tile_h, descriptor.oh - tile_y)
            for tile_x in range(0, descriptor.ow, descriptor.tile_w):
                cols = min(descriptor.tile_w, descriptor.ow - tile_x)
                for position in range(rows * cols):
                    oy = tile_y + position // cols
                    ox = tile_x + position % cols
                    offset = (oy * descriptor.output_row_bytes) + (ox * descriptor.cout)
                    for channel in range(descriptor.cout):
                        trace.append((descriptor.output_base + offset + channel,
                                      block[(oy * descriptor.ow + ox) * descriptor.cout + channel]))
    folder = directory / workload / f"{case_index:02d}-{path.name}"
    folder.mkdir(parents=True, exist_ok=True)
    image = folder / "memory.hex"
    golden = folder / "final.hex"
    trace_path = folder / "writes.hex"
    _image_hex(image, bytes(memory))
    final = bytes(value & 0xFF for value in npu_layers[-1].data)
    _image_hex(golden, final)
    trace_path.write_text("".join(f"{address:08x}{value:02x}\n" for address, value in trace))
    plusargs = [
        f"+IMG={image}", f"+GOLD={golden}", f"+BASE={bases['descriptors']:x}",
        f"+COUNT={len(descriptors)}", f"+JOBID={0x50000000 + case_index:x}",
        "+TIMEOUT=72000000", "+SCEN=0", "+FCODE=0", "+FDESC=ffffffff",
        "+FADDR=0", "+CODE=1", f"+MACS={job.report['totals']['useful_macs']}",
        f"+GOLD_BASE={descriptors[-1].output_base:x}", f"+GOLD_BYTES={len(final)}",
        f"+TRACE={trace_path}", f"+TRACE_BYTES={len(trace)}",
    ]
    record = {
        "workload": workload, "input": path.name,
        "source_input_sha256": hashlib.sha256(source_data).hexdigest(),
        "input_sha256": hashlib.sha256(input_data).hexdigest(),
        "descriptors": len(descriptors), "write_trace_bytes": len(trace),
        "final_sha256": hashlib.sha256(final).hexdigest(),
        "layer_sha256": [hashlib.sha256(bytes(value & 0xFF for value in tensor.data)).hexdigest()
                         for tensor in npu_layers],
        "artifacts": {name: file_identity(artifact) for name, artifact in (
            ("memory", image), ("final", golden), ("write_trace", trace_path)
        )},
        "artifact_dir": str(folder), "plusargs": plusargs,
    }
    (folder / "case.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    return plusargs, record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=3600)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--config-digest", required=True)
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--lock", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error("--jobs must be within 1..8")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    lock = args.lock.resolve()
    source_paths = sorted({path.resolve() for path in [
        Path(__file__), ROOT / "scripts/npu_compiler.py",
        ROOT / "scripts/npu_compiler_p0.py", ROOT / "scripts/npu_executor.py",
        ROOT / "scripts/npu_model.py", ROOT / "scripts/npu_reference.py",
        OPERATOR_TB, *COMMON_SOURCES, *P4_SOURCES,
    ]})
    report = {
        "schema": 1, "phase": "NPU-P5", "verification_ids": ["NPU-V014"],
        "verdict": "INCOMPLETE", "simulators": {}, "cases": [],
        "profile": args.profile, "config_digest": args.config_digest, "pdk": args.pdk,
        "command": [sys.executable, *sys.argv], "git": git_identity(),
        "lock": file_identity(lock),
        "implementation": {str(path.relative_to(ROOT)): file_identity(path)
                           for path in source_paths},
        "coverage": {
            "selection": "first ten bytewise corpus IDs per frozen model manifest",
            "comparison": "every accepted output byte in production tile-write order",
            "dma": "production npu_dma with integrated MaxBurstBeats=8",
            "skipped": 0,
        },
        "simulator_builds": {},
    }
    report_path = output / "qualification-p5-rtl.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    try:
        case_args = []
        for workload, selected in samples().items():
            for index, path in enumerate(selected):
                plusargs, record = emit_case(output / "artifacts", workload, path, index)
                case_args.append((workload, path.name, plusargs))
                report["cases"].append(record)
        tools = _tools()
        report["tools"] = {
            "iverilog": tool_identity(tools["iverilog"], "-V"),
            "vvp": tool_identity(tools["vvp"], "-V"),
            "verilator": tool_identity(tools["verilator"], "--version"),
        }
        run_id = str(int(time.time()))
        for simulator in ("iverilog", "verilator"):
            build = output / f"build-{simulator}-{run_id}"
            build.mkdir()
            command = _build_sim(tools, simulator, build, f"npu_p5_{simulator}",
                                 "npu_operator_tb", OPERATOR_TB, P4_SOURCES)
            report["simulator_builds"][simulator] = {
                "directory": str(build), "run_prefix": command,
                "sources": [str(path) for path in [*COMMON_SOURCES, *P4_SOURCES, OPERATOR_TB]],
            }
            def run_case(case):
                workload, name, plusargs = case
                started = time.monotonic()
                full_command = [*command, *plusargs]
                timed_out = False
                try:
                    completed = subprocess.run(
                        full_command, text=True, capture_output=True,
                        timeout=args.timeout_seconds, check=False,
                    )
                    returncode = completed.returncode
                    log_text = completed.stdout + completed.stderr
                except subprocess.TimeoutExpired as error:
                    timed_out = True
                    returncode = None
                    stdout = error.stdout or ""
                    stderr = error.stderr or ""
                    log_text = ((stdout.decode() if isinstance(stdout, bytes) else stdout) +
                                (stderr.decode() if isinstance(stderr, bytes) else stderr))
                log = output / f"{simulator}-{workload}-{name}.log"
                log.write_text(log_text)
                rejected = rejected_markers(log_text)
                passed = (not timed_out and returncode == 0 and
                          "NPU operator test passed" in log_text and not rejected)
                record = {"workload": workload, "input": name,
                    "status": "PASS" if passed else "FAIL", "exit_code": returncode,
                    "timed_out": timed_out, "rejected_markers": rejected,
                    "duration_seconds": round(time.monotonic() - started, 3),
                    "command": full_command, "log": file_identity(log)}
                return record

            with ThreadPoolExecutor(max_workers=args.jobs) as executor:
                simulator_records = list(executor.map(run_case, case_args))
            report["simulators"][simulator] = simulator_records
            report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            failed = [record for record in simulator_records if record["status"] != "PASS"]
            if failed:
                raise RuntimeError(
                    f"{simulator} model qualification failed: {failed[0]['workload']}/"
                    f"{failed[0]['input']}"
                )
        report["summary"] = {
            "cases": len(report["cases"]),
            "passes": sum(len(records) for records in report["simulators"].values()),
            "failures": 0, "skipped": 0,
        }
        report["verdict"] = "PASS"
    except Exception as error:  # record every required-input/tool/simulator failure
        report["verdict"] = "FAIL"
        report["error"] = str(error)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"NPU-P5 RTL qualification: {report['verdict']} ({report_path})")
    return 0 if report["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
