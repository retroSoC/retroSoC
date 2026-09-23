"""Tests for the machine-readable benchmark log parser."""

from __future__ import annotations

from decimal import Decimal

from scripts.check_lp_hp_performance import compare as compare_lp_hp
from scripts.parse_coremark_log import parse_log as parse_coremark_log
from scripts.parse_performance_log import parse_log


def test_parse_log_requires_terminal_marker_and_complete_samples() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 cycles=123 mgmt_wait=10 "
        "apb4_periph_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0 "
        "workload_bytes=4096 pixels=0 jobs=0 cpu_cycles=123 cpu_hz=24000000 "
        "pclk_hz=24000000 "
        "ga2d_features=0x7ff ga2d_limits=0x08202010 ga2d_formats=0x000f0f1f "
        "ga2d_cycles=0 ga2d_read_bytes=0 ga2d_write_bytes=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "passed"
    assert report["failure_marker"] is False
    assert report["pass_marker"] is True
    assert report["samples"] == [
        {
            "checksum": 0x1234,
            "configuration": {
                "cpu_hz": 24000000,
                "pclk_hz": 24000000,
                "ga2d_features": 0x7FF,
                "ga2d_formats": 0x000F0F1F,
                "ga2d_limits": 0x08202010,
            },
            "cpu_cycles": 123,
            "cycles": 123,
            "dma_wait": 0,
            "flash_wait": 0,
            "ga2d_cycles": 0,
            "ga2d_read_bytes": 0,
            "ga2d_write_bytes": 0,
            "jobs": 0,
            "mgmt_wait": 10,
            "apb4_periph_wait": 9,
            "operation": "read",
            "pixels": 0,
            "psram_wait": 0,
            "region": "sdram",
            "sdram_wait": 8,
            "workload_bytes": 4096,
            "words": 1024,
        }
    ]


def test_parse_log_rejects_missing_benchmark_marker() -> None:
    report = parse_log(
        "PERF region=flash op=read words=1024 checksum=0 cycles=10 mgmt_wait=1 apb4_periph_wait=1 "
        "sdram_wait=0 psram_wait=0 flash_wait=1 dma_wait=0 workload_bytes=4096 pixels=0 "
        "jobs=0 cpu_cycles=10 cpu_hz=24000000 pclk_hz=24000000 ga2d_features=0x7ff "
        "ga2d_limits=0x08202010 ga2d_formats=0x000f0f1f ga2d_cycles=0 "
        "ga2d_read_bytes=0 ga2d_write_bytes=0\n"
    )

    assert report["status"] == "failed"


def test_parse_log_rejects_report_with_performance_failure() -> None:
    report = parse_log(
        "PERF region=sdram op=read words=1024 checksum=0x1234 cycles=123 mgmt_wait=10 "
        "apb4_periph_wait=9 sdram_wait=8 psram_wait=0 flash_wait=0 dma_wait=0 "
        "workload_bytes=4096 pixels=0 jobs=0 cpu_cycles=123 cpu_hz=24000000 "
        "pclk_hz=24000000 "
        "ga2d_features=0x7ff ga2d_limits=0x08202010 ga2d_formats=0x000f0f1f "
        "ga2d_cycles=0 ga2d_read_bytes=0 ga2d_write_bytes=0\n"
        "PERF_FAIL region=sdram op=read reason=data expected=1234 actual=0\n"
        "PERF_BENCHMARK_PASS\n"
    )

    assert report["status"] == "failed"
    assert report["failure_marker"] is True


def test_parse_log_preserves_ga2d_workload_and_configuration_facts() -> None:
    report = parse_log(
        "PERF region=ga2d op=copy words=0 checksum=0x4567 cycles=99 mgmt_wait=3 "
        "apb4_periph_wait=2 sdram_wait=7 psram_wait=0 flash_wait=0 dma_wait=0 "
        "workload_bytes=192 pixels=32 jobs=1 cpu_cycles=99 cpu_hz=24000000 "
        "pclk_hz=24000000 "
        "ga2d_features=0x7ff ga2d_limits=0x08202010 ga2d_formats=0x000f0f1f "
        "ga2d_cycles=75 ga2d_read_bytes=96 ga2d_write_bytes=96 "
        "width=8 height=4 pitch=48\n"
        "PERF_BENCHMARK_PASS\n"
    )

    sample = report["samples"][0]
    assert sample["operation"] == "copy"
    assert sample["workload_bytes"] == 192
    assert sample["pixels"] == 32
    assert sample["jobs"] == 1
    assert sample["cpu_cycles"] == 99
    assert sample["ga2d_cycles"] == 75
    assert sample["ga2d_read_bytes"] == 96
    assert sample["ga2d_write_bytes"] == 96
    assert sample["width"] == 8
    assert sample["height"] == 4
    assert sample["pitch"] == 48
    assert sample["derived"] == {
        "ga2d_job_latency_us": "3.125",
        "ga2d_effective_mb_per_s": "61.440",
        "ga2d_pixels_per_s": "10240000.000",
        "lp_cpu_us": "4.125",
        "lp_cpu_cycles_per_pixel": "3.094",
    }
    assert sample["configuration"] == {
        "cpu_hz": 24000000,
        "pclk_hz": 24000000,
        "ga2d_features": 0x7FF,
        "ga2d_limits": 0x08202010,
        "ga2d_formats": 0x000F0F1F,
    }


def test_parse_coremark_quick_report() -> None:
    report = parse_coremark_log(
        "COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=4 cycles=2000 "
        "cpu_hz=24000000\nCOREMARK_PASS\n"
    )

    assert report["status"] == "passed"
    assert report["results"] == [
        {
            "coremark_per_mhz": "2000.000",
            "cpu_hz": 24000000,
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


def test_lp_hp_coremark_ratio_gate() -> None:
    lp = parse_coremark_log(
        "COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=4 cycles=2000 "
        "cpu_hz=72000000\nCOREMARK_PASS\n"
    )
    hp = parse_coremark_log(
        "COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=12 cycles=2000 "
        "cpu_hz=72000000\nCOREMARK_PASS\n"
    )
    report = compare_lp_hp(lp, hp, Decimal("2.5"))
    assert report["status"] == "passed"
    assert report["measured_ratio"] == "3.000"

    hp["results"][0]["coremark_per_mhz"] = "4000.000"
    report = compare_lp_hp(lp, hp, Decimal("2.5"))
    assert report["status"] == "failed"
