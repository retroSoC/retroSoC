"""Tests for the machine-readable benchmark log parser."""

from __future__ import annotations

from scripts.parse_coremark_log import parse_log as parse_coremark_log
from scripts.parse_performance_log import parse_log


def test_parse_log_requires_terminal_marker_and_complete_samples() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 cycles=123 mgmt_wait=10 "
        "apb4_periph_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "passed"
    assert report["failure_marker"] is False
    assert report["pass_marker"] is True
    assert report["samples"] == [
        {
            "checksum": 0x1234,
            "cycles": 123,
            "dma_wait": 0,
            "flash_wait": 0,
            "mgmt_wait": 10,
            "apb4_periph_wait": 9,
            "operation": "read",
            "psram_wait": 0,
            "region": "sdram",
            "sdram_wait": 8,
            "words": 1024,
        }
    ]


def test_parse_log_rejects_missing_benchmark_marker() -> None:
    report = parse_log(
        "PERF region=flash op=read words=1024 checksum=0 cycles=10 mgmt_wait=1 apb4_periph_wait=1 "
        "sdram_wait=0 psram_wait=0 flash_wait=1 dma_wait=0\n"
    )

    assert report["status"] == "failed"


def test_parse_log_rejects_report_with_performance_failure() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 cycles=123 mgmt_wait=10 "
        "apb4_periph_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0\n"
        "PERF_FAIL region=sdram op=read reason=data expected=1234 actual=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "failed"
    assert report["failure_marker"] is True


def test_parse_coremark_quick_report() -> None:
    report = parse_coremark_log(
        "COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=4 cycles=2000 "
        "cpu_hz=72000000\nCOREMARK_PASS\n"
    )

    assert report["status"] == "passed"
    assert report["results"] == [
        {
            "coremark_per_mhz": "2000.000",
            "cpu_hz": 72000000,
            "cycles": 2000,
            "iterations": 4,
            "memory": "sram",
            "mode": "quick",
            "qualified": False,
        }
    ]


def test_parse_coremark_rejects_failure_or_non_sram_result() -> None:
    report = parse_coremark_log(
        "COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=36 cycles=1800 "
        "cpu_hz=72000000\nCOREMARK_FAIL result=1\n"
    )
    assert report["status"] == "failed"
    assert report["failure_marker"] is True

    try:
        parse_coremark_log(
            "COREMARK_RESULT mode=quick qualified=0 memory=psram iterations=36 cycles=1800 "
            "cpu_hz=72000000\nCOREMARK_PASS\n"
        )
    except ValueError as error:
        assert "SRAM" in str(error)
    else:
        raise AssertionError("non-SRAM CoreMark result was accepted")
