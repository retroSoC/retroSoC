"""NPU-P6 corpus packaging and fail-closed qualification report tests."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import npu_p6_corpus as corpus  # noqa: E402
import npu_p6_report as report  # noqa: E402
import run_npu_p6_netlist as netlist  # noqa: E402
import run_npu_p6_verilator as verilator  # noqa: E402


def _case(index: int, workload: str = "kws") -> corpus.CorpusCase:
    input_data = bytes([index & 0xFF]) * corpus.INPUT_BYTES[workload]
    terminal_data = bytes([(index + 1) & 0xFF]) * corpus.OUTPUT_BYTES[workload]
    softmax_data = bytes([(index + 2) & 0xFF]) * corpus.OUTPUT_BYTES[workload]
    return corpus.CorpusCase(
        index=index,
        name=f"case-{index}",
        label=index % 2,
        input_data=input_data,
        terminal_data=terminal_data,
        softmax_data=softmax_data,
        input_sha256=hashlib.sha256(input_data).hexdigest(),
        terminal_sha256=hashlib.sha256(terminal_data).hexdigest(),
        softmax_sha256=hashlib.sha256(softmax_data).hexdigest(),
    )


def test_corpus_shard_header_and_payload_are_deterministic() -> None:
    cases = [_case(100), _case(101)]
    digest = "5a" * 32
    first = corpus.encode_shard("kws", 1, 10, cases, digest)
    second = corpus.encode_shard("kws", 1, 10, cases, digest)
    assert first == second
    fields = corpus.HEADER.unpack_from(first)
    assert fields[:10] == (
        corpus.MAGIC, 2, 1, 1, 10, 100, 2, 490, 12, corpus.CASE_HEADER.size + 516
    )
    payload = first[corpus.HEADER_BYTES :]
    assert fields[10] == zlib.crc32(payload) & 0xFFFFFFFF
    assert fields[11] == bytes.fromhex(digest)
    assert struct.unpack_from("<II", payload) == (100, 0)
    assert len(payload) == 2 * fields[9]
    assert struct.unpack_from("<II", payload, fields[9]) == (101, 1)


def test_corpus_shard_rejects_reordered_cases() -> None:
    with pytest.raises(ValueError, match="contiguous"):
        corpus.encode_shard("kws", 0, 1, [_case(0), _case(2)], "00" * 32)


def test_p0_layer_container_is_parsed_before_selecting_goldens() -> None:
    first = b"abc"
    second = b"de"
    payload = (
        b"NPO1"
        + struct.pack("<I", 2)
        + struct.pack("<II", 7, len(first))
        + first
        + struct.pack("<II", 9, len(second))
        + second
    )
    metadata = [
        {"bytes": len(first), "framework_sha256": hashlib.sha256(first).hexdigest()},
        {"bytes": len(second), "framework_sha256": hashlib.sha256(second).hexdigest()},
    ]
    assert corpus._decode_layers(payload, metadata) == [first, second]
    with pytest.raises(ValueError, match="hash"):
        corpus._decode_layers(payload, [metadata[0], {**metadata[1], "framework_sha256": "0" * 64}])


def _case_line() -> str:
    fields = {
        "workload": "kws",
        "shard": "0",
        "index": "0",
        "cache": "cold",
        "contention": "ga2d-copy-32x32768-rgb565",
        "label": "7",
        "reference_cycles": "0x200",
        "npu_cycles": "0x100",
        "input_copy_cycles": "0x20",
        "npu_wait_cycles": "0xf0",
        "softmax_cycles": "0x10",
        "active_cycles": "0xe0",
        "clock_pause_cycles": "0",
        "useful_macs": "0x1000",
        "pack_cycles": "0x10",
        "bank_stall_cycles": "0",
        "dma_read_bytes": "0x2000",
        "dma_write_bytes": "0x100",
        "dma_stall_cycles": "2",
        "requant_stall_cycles": "3",
        "retired_descriptors": "11",
        "reference_class": "7",
        "npu_class": "7",
        "status": "PASS",
    }
    return verilator.CASE_PREFIX + " ".join(f"{name}={value}" for name, value in fields.items())


def test_verilator_case_parser_is_exact_and_cycle_accounted() -> None:
    parsed = verilator.parse_case_line(_case_line())
    assert parsed["reference_cycles"] == 0x200
    assert parsed["npu_cycles"] == 0x100
    broken = _case_line().replace("npu_cycles=0x100", "npu_cycles=0x101")
    with pytest.raises(ValueError, match="wait plus Softmax"):
        verilator.parse_case_line(broken)


def test_compiler_comparison_explains_material_cycle_difference() -> None:
    estimate = {
        "artifact": {"path": "npu.json", "bytes": 1, "sha256": "0" * 64},
        "cycle_model": "analytical model",
        "per_inference": {
            "active_cycles": 100,
            "dma_read_bytes": 20,
            "dma_write_bytes": 10,
            "useful_macs": 80,
            "pack_cycles": 8,
            "retired_descriptors": 2,
        },
    }
    counters = {
        "active_cycles": 300,
        "dma_read_bytes": 40,
        "dma_write_bytes": 20,
        "useful_macs": 160,
        "pack_cycles": 16,
        "retired_descriptors": 4,
    }
    comparison = verilator.compare_compiler_estimates(estimate, counters, 2)
    assert comparison["metrics"]["active_cycles"]["material_difference"] is True
    assert comparison["metrics"]["active_cycles"]["measured_to_estimated_ratio"] == 1.5
    assert "no-overlap" in comparison["metrics"]["active_cycles"]["explanation"]
    assert comparison["metrics"]["dma_read_bytes"]["material_difference"] is False


def test_stdcell_functional_view_removes_timing_state(tmp_path: Path) -> None:
    source = tmp_path / "cells.v"
    output = tmp_path / "functional.v"
    source.write_text(
        "module cell(Q, CLK);\n"
        "output Q; input CLK;\n"
        "reg notifier;\n"
        "wire delayed_CLK; buf(Q, delayed_CLK);\n"
        "specify\n(CLK => Q) = 1;\nendspecify\n"
        "endmodule\n"
    )
    netlist.write_functional_stdcell(source, output)
    text = output.read_text()
    assert "specify" not in text and "delayed_" not in text
    assert "wire notifier = 1'b0;" in text


def _performance(path: Path, speedup: float = 2.0) -> None:
    workloads = {}
    for name in ("kws", "vww"):
        compiler_manifest = path.parent / f"{name}-npu.json"
        compiler_manifest.write_text("{}\n")
        cases = [
            {
                "index": index,
                "status": "PASS",
                "reference_cycles": 200,
                "npu_cycles": 100,
                "npu_wait_cycles": 90,
                "softmax_cycles": 10,
                "reference_class": index % 2,
                "npu_class": index % 2,
                "active_cycles": 100,
                "dma_read_bytes": 20,
                "dma_write_bytes": 10,
                "useful_macs": 80,
                "pack_cycles": 8,
                "retired_descriptors": 2,
                "cache": "cold" if index % 100 == 0 else "steady",
                "contention": "ga2d-copy-32x32768-rgb565" if index < 10 else "none",
            }
            for index in range(1000)
        ]
        estimates = {
            "active_cycles": 100,
            "dma_read_bytes": 20,
            "dma_write_bytes": 10,
            "useful_macs": 80,
            "pack_cycles": 8,
            "retired_descriptors": 2,
        }
        compiler_comparison = {
            "artifact": report.identity(compiler_manifest),
            "cycle_model": "analytical model",
            "material_threshold_percent": 10,
            "metrics": {
                metric: {
                    "estimated_per_inference": value,
                    "expected_total": value * len(cases),
                    "measured_total": value * len(cases),
                    "measured_mean": value,
                    "measured_to_estimated_ratio": 1.0,
                    "material_difference": False,
                    "explanation": "within threshold",
                }
                for metric, value in estimates.items()
            },
        }
        workloads[name] = {
            "cases": cases,
            "speedup": speedup,
            "skipped": 0,
            "mismatches": 0,
            "compiler_comparison": compiler_comparison,
        }
    path.write_text(json.dumps({
        "phase": "NPU-P6", "verification_ids": ["NPU-V016"], "verdict": "PASS",
        "summary": {"skipped": 0}, "workloads": workloads,
    }))


def test_performance_report_requires_complete_two_times_corpora(tmp_path: Path) -> None:
    path = tmp_path / "performance.json"
    _performance(path)
    assert set(report.validate_performance(path)["workloads"]) == {"kws", "vww"}
    data = json.loads(path.read_text())
    data["workloads"]["vww"]["cases"].pop()
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="1000 cases"):
        report.validate_performance(path)


def test_performance_report_rejects_subtarget_speedup(tmp_path: Path) -> None:
    path = tmp_path / "performance.json"
    _performance(path, speedup=1.99)
    data = json.loads(path.read_text())
    for case in data["workloads"]["vww"]["cases"]:
        case["reference_cycles"] = 199
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="2.0-times"):
        report.validate_performance(path)


def test_performance_report_requires_compiler_comparison(tmp_path: Path) -> None:
    path = tmp_path / "performance.json"
    _performance(path)
    data = json.loads(path.read_text())
    del data["workloads"]["kws"]["compiler_comparison"]
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="compiler comparison"):
        report.validate_performance(path)


@pytest.mark.parametrize("marker", report.REJECTED)
def test_log_rejects_failure_markers(tmp_path: Path, marker: str) -> None:
    path = tmp_path / "sim.log"
    path.write_text(f"NPU_P6_PASS\n{marker}\n")
    with pytest.raises(ValueError, match="markers failed"):
        report.validate_log(path, ("NPU_P6_PASS",))
