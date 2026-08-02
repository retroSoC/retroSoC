"""Tests for the machine-readable benchmark log parser."""

from __future__ import annotations

from scripts.parse_performance_log import parse_log


def test_parse_log_requires_terminal_marker_and_complete_samples() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 mgmt_wait=10 "
        "native_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "passed"
    assert report["failure_marker"] is False
    assert report["pass_marker"] is True
    assert report["samples"] == [
        {
            "checksum": 0x1234,
            "dma_wait": 0,
            "flash_wait": 0,
            "mgmt_wait": 10,
            "native_wait": 9,
            "operation": "read",
            "psram_wait": 0,
            "region": "sdram",
            "sdram_wait": 8,
            "words": 1024,
        }
    ]


def test_parse_log_rejects_missing_benchmark_marker() -> None:
    report = parse_log(
        "PERF region=flash op=read words=1024 checksum=0 mgmt_wait=1 native_wait=1 "
        "sdram_wait=0 psram_wait=0 flash_wait=1 dma_wait=0\n"
    )

    assert report["status"] == "failed"


def test_parse_log_rejects_report_with_performance_failure() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 mgmt_wait=10 "
        "native_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0\n"
        "PERF_FAIL region=sdram op=read reason=data expected=1234 actual=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "failed"
    assert report["failure_marker"] is True
