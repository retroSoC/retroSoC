"""Cross-IP publication tables must match routed hardware and executable SDK math."""
from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from publications import programming_reference as pr

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
IDS = {row["id"] for row in REFERENCE["support"]}


@pytest.fixture
def spec():
    return copy.deepcopy(REFERENCE["programming"])


def check(spec):
    pr.validate_programming(spec, IDS, ROOT, REFERENCE["source_revision"])


def test_complete_dma_routes_and_native_credit_boundary(spec):
    result = pr.collect_programming(ROOT, spec, IDS, REFERENCE["source_revision"])
    assert [r["number"] for r in result["dma_routes"]] == list(range(14))
    assert [r["number"] for r in result["channels"]] == list(range(8))
    assert result["read_credits"] == [4, 4, 4, 2, 2, 1, 0, 4]
    assert result["write_credits"] == [0, 2, 2, 1, 1, 1, 0, 2]


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "unknown_ip", "connection"])
def test_route_inventory_rejects_ambiguous_or_unwired_entries(spec, mutation):
    if mutation == "missing":
        spec["dma_routes"].pop()
    elif mutation == "duplicate":
        spec["dma_routes"].append(copy.deepcopy(spec["dma_routes"][0]))
    elif mutation == "unknown_ip":
        spec["dma_routes"][0]["ips"] = ["nonexistent"]
    else:
        spec["dma_routes"][1]["bindings"][0]["text"] = ".missing_port(missing_signal)"
    with pytest.raises(ValueError, match="coverage|duplicate|unknown programming IP|binding changed"):
        check(spec)


def test_sdk_request_number_drift_is_rejected(spec, monkeypatch):
    original = pr.constants

    def drift(text, prefix, rtl=False):
        result = original(text, prefix, rtl)
        if prefix == "RS_DMA_REQUEST_":
            result["RS_DMA_REQUEST_DVP_RX"] = 14
        return result

    monkeypatch.setattr(pr, "constants", drift)
    with pytest.raises(ValueError, match="RTL/SDK DMA request mismatch"):
        check(spec)


def test_device_board_claim_needs_a_matching_report(spec):
    spec["devices"][0]["board"] = "Reported pass"
    with pytest.raises(ValueError, match="requires matching evidence"):
        check(spec)


def test_channel_coverage_cannot_drop_the_boot_channel(spec):
    spec["channels"] = [r for r in spec["channels"] if r["id"] != "hp"]
    with pytest.raises(ValueError, match="channel allocation coverage"):
        pr.collect_programming(ROOT, spec, IDS, REFERENCE["source_revision"])


def test_credit_parser_fails_closed_on_unreviewed_shape():
    with pytest.raises(ValueError, match="unsupported credit function"):
        pr.credit_values("function automatic int limits(input int master); return compute(master); endfunction", "limits", 8)


def test_memory_payload_packing_and_alignment_are_distinct():
    frame = pr.buffer_budget("frame", width=640, height=480, count=2)
    assert frame["storage_bytes"] == 614400 and frame["total_bytes"] == 1228800
    odd = pr.buffer_budget("frame", width=641, height=480)
    assert odd["payload_bytes"] == 615360 and odd["storage_bytes"] == 616320
    assert odd["dma_supported"] is False
    audio16 = pr.buffer_budget("audio", rate=48000, bits=16, milliseconds=10, count=2)
    audio24 = pr.buffer_budget("audio", rate=48000, bits=24, milliseconds=10, count=2)
    assert audio16["total_bytes"] == 3840
    assert audio24["payload_bytes"] == 2880 and audio24["total_bytes"] == 7680
    assert pr.buffer_budget("descriptors", descriptors=8)["total_bytes"] == 512


@pytest.mark.parametrize("args", [
    {"kind": "frame", "width": 0, "height": 480},
    {"kind": "frame", "width": 65536, "height": 65536},
    {"kind": "audio", "rate": 44100, "bits": 16, "milliseconds": 1},
    {"kind": "audio", "rate": 48000, "bits": 32, "milliseconds": 10},
    {"kind": "descriptors", "descriptors": 1, "alignment": 3},
    {"kind": "descriptors", "descriptors": 1, "count": 1 << 31},
])
def test_budget_rejects_invalid_sizes_alignment_and_overflow(args):
    with pytest.raises(ValueError):
        pr.buffer_budget(**args)


@pytest.fixture(scope="module")
def sdk_math(tmp_path_factory):
    if os.name == "nt":
        pytest.skip("SDK C math comparison runs in the Linux host test environment")
    cc = shutil.which("cc") or shutil.which("gcc")
    if cc is None:
        pytest.skip("host C compiler unavailable")
    folder = tmp_path_factory.mktemp("publication-math")
    include = folder / "retrosoc/generated"
    include.mkdir(parents=True)
    # The pure calculations do not use MMIO. This only permits unrelated address
    # accessor functions in i2s_math.c to compile; none are called by this driver.
    (include / "memory_map.h").write_text("#define RS_SOC_APB4_I2S_BASE 0U\n")
    driver = folder / "compare.c"
    driver.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/i2s.h>
int main(int argc, char **argv) {
    if (argc < 4) return 2;
    uint32_t clock = (uint32_t)strtoul(argv[2], NULL, 10);
    uint32_t value = (uint32_t)strtoul(argv[3], NULL, 10);
    if (!strcmp(argv[1], "uart")) {
        rs_uart_timing_t t = {0};
        int s = rs_uart_timing_calculate(clock, value, &t);
        printf("%d %u %u\n", s, t.baud_integer, t.baud_fraction);
    } else if (!strcmp(argv[1], "i2c")) {
        rs_i2c_timing_t t = {0};
        int s = rs_i2c_timing_calculate(clock, value, &t);
        printf("%d %u %u %u %u %u %u %u\n", s, t.scl_low_cycles, t.scl_high_cycles,
            t.start_hold_cycles, t.start_setup_cycles, t.data_setup_cycles, t.stop_setup_cycles, t.bus_free_cycles);
    } else if (!strcmp(argv[1], "timer")) {
        rs_timer_period_t t = {0};
        int s = rs_timer_period_from_ms(clock, value, &t);
        printf("%d %u %u\n", s, t.prescale, t.load);
    } else if (!strcmp(argv[1], "i2s") && argc == 5) {
        uint8_t a = 0, b = 0;
        int s = rs_i2s_div_from_hz(clock, value, (uint32_t)strtoul(argv[4], NULL, 10), &a, &b);
        printf("%d %u %u\n", s, (unsigned)a, (unsigned)b);
    } else return 2;
    return 0;
}
''', encoding="utf-8")
    exe = folder / "compare"
    files = [ROOT / f"crt/src/hal/{name}_math.c" for name in ("uart", "i2c", "timer", "i2s")]
    subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(folder),
                    "-I", str(ROOT / "crt/include"), str(driver), *map(str, files), "-o", str(exe)], check=True)
    return exe


@pytest.mark.parametrize("kind,clock,value,bits", [
    ("uart", 24000000, 115200, 0), ("uart", 72000000, 115200, 0),
    ("uart", 16000000, 1000000, 0), ("uart", 16000000, 1000001, 0), ("uart", 0, 115200, 0),
    ("i2c", 24000000, 100000, 0), ("i2c", 24000000, 400000, 0),
    ("i2c", 24000000, 1000000, 0), ("i2c", 24000000, 1000001, 0), ("i2c", 24000000, 1, 0),
    ("timer", 24000000, 1, 0), ("timer", 24000000, 1000, 0),
    ("timer", 4294967295, 1001, 0), ("timer", 1, 1, 0), ("timer", 24000000, 0, 0),
    ("i2s", 18432000, 48000, 16), ("i2s", 18432000, 96000, 16),
    ("i2s", 18432000, 48000, 24), ("i2s", 18432000, 96000, 24),
    ("i2s", 18432000, 44100, 16), ("i2s", 18432000, 48000, 32),
])
def test_published_integer_math_matches_sdk_c(sdk_math, kind, clock, value, bits):
    output = subprocess.check_output([str(sdk_math), kind, str(clock), str(value), *([str(bits)] if kind == "i2s" else [])], text=True)
    status, *actual = map(int, output.split())
    try:
        expected = getattr(pr, kind + "_timing")(clock, value, *([bits] if kind == "i2s" else []))
    except ValueError:
        expected = None
    assert (status == 0) == (expected is not None)
    if expected is not None:
        fields = {"uart": ("integer", "fraction"), "timer": ("prescale", "load"), "i2s": ("sclk_div", "lrck_div")}
        wanted = expected["cycles"] if kind == "i2c" else [expected[key] for key in fields[kind]]
        assert actual == wanted
