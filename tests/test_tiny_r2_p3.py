"""P3 rejects incompatible builds, incorrect measurements and unsafe placements."""

from pathlib import Path
import subprocess

import pytest

from scripts import tiny_r2_p3 as p3

ROOT = Path(__file__).resolve().parents[1]


def test_make_success_does_not_hide_normal_firmware_warnings(tmp_path, monkeypatch):
    warning = f"{ROOT}/app/apps/ci_smoke/tiny.c:257:8: warning: snapshot may be used uninitialized\n"
    monkeypatch.setattr(p3.subprocess, "run", lambda *args, **kwargs:
                        subprocess.CompletedProcess(args[0], 0, stdout="", stderr=warning))
    with pytest.raises(ValueError, match="self-owned compiler warnings"):
        p3.execute_make(ROOT, tmp_path, "normal-image", ["make", "firmware"])
    result = p3.read_json(tmp_path / "normal-image.json")
    assert result["exit_code"] == 0
    assert result["status"] == "failed"
    assert len(result["self_owned_warnings"]) == 1


def sample_log() -> str:
    lines = ["P3_HEADER version=3 cpu_hz=24000000 words=1024 jobs=4 iterations=4096 seed=0x12345678"]
    for i, name in enumerate(p3.CASES):
        row = dict.fromkeys(p3.baseline.CASE_FIELDS, 0)
        row.update(id=i, name=name, cycles=100, instructions=50,
                   checksum=0 if i == 0 else 0xf6e37410 if i == 1 else 0xc4a58dc5,
                   payload_bytes=16384 if i >= 2 else 0,
                   kernel_calls=1 if i == 1 else 4 if i in (5, 6, 7) else 0)
        lines.append("P3_CASE " + " ".join(f"{k}={v}" for k, v in row.items()))
        for owner in range(2):
            axi = dict.fromkeys(p3.baseline.AXI_FIELDS, 0)
            axi.update(window=i+1, owner=owner)
            if owner == 1 and i >= 3:
                axi.update(read_bytes=16384, write_bytes=16384, reads=1, writes=1,
                           read_done=1, write_done=1, descriptor_bytes=1024 if i == 6 else 0)
            lines.append("R2_AXI " + " ".join(f"{k}={v}" for k, v in axi.items()))
            ahb = dict.fromkeys(p3.baseline.AHB_FIELDS, 0)
            ahb.update(window=i+1, kind=owner)
            lines.append("R2_AHB " + " ".join(f"{k}={v}" for k, v in ahb.items()))
    return "\n".join([*lines, "P3_STACK reserved=4096 observed=256", "P3_ISA PASS",
                      "P3_COMPLETE version=3 cases=8", "SIM_TEST_PASS Tiny code=0"])


def test_complete_log_and_independent_payload_oracle():
    value = 2166136261
    for _ in range(4):
        for index in range(1024):
            value = ((value ^ (0xa519c300 ^ index)) * 16777619) & 0xffffffff
    result = p3.parse_log(sample_log(), {"status": "passed", "exit_code": 0})
    assert result["cases"][2]["checksum"] == value
    assert result["axi"][13]["descriptor_bytes"] == 1024


@pytest.mark.parametrize("marker", ["FAILED", "FATAL", "assertion failed", "%Error",
                                    "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT", "P3_ERROR"])
def test_later_pass_does_not_hide_error(marker):
    with pytest.raises(ValueError):
        p3.parse_log(marker + "\n" + sample_log(), {"status": "passed", "exit_code": 0})


@pytest.mark.parametrize("old,new", [
    ("SIM_TEST_PASS Tiny code=0", "Hello retroSoC!"),
    ("P3_ISA PASS", ""), ("jobs=4", "jobs=16"),
    ("descriptor_bytes=1024", "descriptor_bytes=0"),
    ("write_bytes=16384", "write_bytes=16380"),
    ("pending_writes=0", "pending_writes=1"),
    ("observed=256", "observed=4096"),
    ("P3_COMPLETE version=3 cases=8", "P3_COMPLETE version=3 cases=7"),
])
def test_incomplete_or_wrong_measurement_fails(old, new):
    with pytest.raises(ValueError):
        p3.parse_log(sample_log().replace(old, new), {"status": "passed", "exit_code": 0})


def test_failed_command_and_duplicate_records_fail():
    with pytest.raises(ValueError):
        p3.parse_log(sample_log(), {"status": "passed", "exit_code": 124})
    line = next(line for line in sample_log().splitlines() if line.startswith("P3_CASE"))
    with pytest.raises(ValueError):
        p3.parse_log(sample_log() + "\n" + line, {"status": "passed", "exit_code": 0})


def layout_symbols() -> str:
    return "\n".join([
        "30018000 00001080 b rs_p3_source", "30019080 00004200 b rs_p3_destinations",
        "3001d280 00000400 b rs_p3_tcds", "3001d680 00000004 d rs_p3_dma_cookie",
        "30018000 A _stack_point", "30010200 B _ebss",
        "30000000 00000100 T main", "30000200 00000100 T system_trap_entry",
        "30000400 00000100 T rs_p3_isa_check", "30000600 00000008 T rs_p3_patch_target",
        "00000100 D _copy_table_start", "00000124 D _copy_table_end",
        "00000124 D _zero_table_start", "00000134 D _zero_table_end",
    ])


def test_valid_banked_placement():
    assert p3.check_layout(layout_symbols(), True)["descriptor_range"] == [0x3001d280, 0x3001d680]


@pytest.mark.parametrize("old,new", [("3001d280", "3001d284"), ("30018000 00001080", "30017000 00001080"),
                                    ("30010200", "30017800"), ("30000000 00000100", "30010000 00000100"),
                                    ("00000400 b", "00001000 b"), ("00000124 D _copy_table_end", "00000100 D _copy_table_end")])
def test_unsafe_placement_fails(old, new):
    with pytest.raises(ValueError):
        p3.check_layout(layout_symbols().replace(old, new), True)


@pytest.mark.parametrize("override", ["SW_ISA_PROFILE=RV32IMA", "SW_OPT=O0", "SW_LTO=maybe",
                                      "LINK_TYPE=ld2_psram", "WS2812_P3_ACCEPTANCE=YES"])
def test_tiny_rejects_invalid_experiment(override):
    result = subprocess.run(["make", "-s", "CONFIG=configs/ci/ics55-tiny.mk", override, "config"],
                            cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0


def test_performance_isa_is_not_enabled_for_mini():
    result = subprocess.run(["make", "-n", "CONFIG=configs/ci/ics55.mk", "SIMU=VERILATOR",
                             "SW_ISA_PROFILE=TINY_PERF", "firmware"], cwd=ROOT,
                            capture_output=True, text=True)
    assert result.returncode != 0


def test_eight_experiments_separate_isa_optimization_and_placement():
    assert len(p3.MATRIX) == 8
    assert {row[2:4] for row in p3.MATRIX if row[1] == "TINY_PERF"} == {
        (opt, lto) for opt in ("O2", "O3", "Os") for lto in ("NO", "YES")}


def test_trap_probe_must_not_compress_under_performance_flags():
    normal = "30001000 <rs_mcu_unmapped_probe>:\n30001000: 00052503 lw a0,0(a0)\n30001004: 8082 ret\n"
    p3.check_exception_probe(normal)
    with pytest.raises(ValueError, match="32-bit"):
        p3.check_exception_probe(normal.replace("00052503", "4108"))
