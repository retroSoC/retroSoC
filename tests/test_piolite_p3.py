"""PIOLITE-P3 Tiny topology, USER GPIO and lifecycle integration checks."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

import pytest

from scripts.check_clock_reset_domains import validate as validate_clocks
from scripts.generate_tiny import generate_bindings, read_topology
from test_tiny_r2_p7 import COMMON, run_rtl

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def test_tiny_piolite_topology_and_capability(tmp_path: Path) -> None:
    topology = read_topology(TINY / "integration/soc_topology.json",
                             TINY / "address_map/memory_map.json")
    regions = {row["symbol"]: row for row in json.loads(
        (TINY / "address_map/memory_map.json").read_text())["regions"]}
    assert regions["APB4_PIOLITE"] == {
        "symbol": "APB4_PIOLITE", "base": "0x1001C000", "size": "0x00001000",
        "route": "apb4_periph", "kind": "active", "public": True, "user_access": "none",
    }
    assert topology["apb_targets"][-1] == {"name": "piolite", "regions": ["APB4_PIOLITE"]}
    assert topology["fabric"]["target_count"] == 31
    assert topology["fabric"]["decode_error_target"] == 29
    assert topology["fabric"]["protocol_error_target"] == 30
    assert {row["core_bit"] for row in topology["interrupts"] if row["name"] == "piolite"} == {24}

    generate_bindings(topology, tmp_path)
    constants = (tmp_path / "rtl/tiny_topology.svh").read_text()
    assert "`define RETROSOC_TINY__LEAF_COUNT 25" in constants
    assert "`define RETROSOC_TINY__TARGET_PIOLITE 28" in constants
    interfaces = (tmp_path / "rtl/tiny_apb_interfaces.svh").read_text()
    assert "tiny_peripheral_leaf u_piolite_lifecycle" in interfaces
    assert ".gate_i(s_gate_request[15])" in interfaces
    assert ".reset_i(s_local_reset[15])" in interfaces
    assert ".rst_n_i(s_leaf_rst_n[24])" in interfaces
    irq = (tmp_path / "include/retrosoc/generated/irq_metadata.h").read_text()
    assert "RS_SOC_IRQ_PIOLITE UINT32_C(24)" in irq
    assert "RS_SOC_EXT_IRQ_PIOLITE UINT32_C(22)" in irq
    features = (tmp_path / "include/retrosoc/generated/soc_features.h").read_text()
    assert "RS_SOC_HAS_PIOLITE 1U" in features
    assert "RS_SOC_PIOLITE_DMA_TX 14U" in features
    assert "RS_SOC_PIOLITE_DMA_RX 15U" in features
    assert "RS_SOC_DMA_REQUEST_MASK 0x3f9ffU" in features


def test_piolite_clock_reset_inventory() -> None:
    inventory = json.loads((TINY / "integration/clock_reset_domains.json").read_text())
    assert inventory["reset_distribution"]["leaf_names"][-1] == "piolite"
    assert len(inventory["reset_distribution"]["leaf_names"]) == 25
    assert inventory["generated_apb_crossings"]["destinations"]["peripheral"][-1] == "piolite"
    validate_clocks(TINY / "integration/clock_reset_domains.json", ROOT)


def test_piolite_product_wiring_and_filelists() -> None:
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert "apb4_piolite u_piolite" in top
    assert ".filter_enable_i       (u_user_gpio_if.filter_enable_i)" in top
    assert ".gpio_value_o          (u_user_gpio_if.do_o)" in top
    assert ".gpio_oe_o             (u_user_gpio_if.oe_o)" in top
    assert "s_periph_idle[15] = s_piolite_lifecycle_idle && !(|s_gpio_user_select)" in top
    assert "assign u_user_gpio_if.do_o" not in top
    assert "assign u_user_gpio_if.oe_o" not in top
    user_gpio = (ROOT / "rtl/ip/peripheral/user_gpio_if.sv").read_text()
    gpio_core = (ROOT / "rtl/ip/peripheral/gpio_core.sv").read_text()
    assert "input di_i, input filter_enable_i" in user_gpio
    assert "assign user_gpio.filter_enable_i = filter_enable_i" in gpio_core

    sources = (TINY / "filelist/ip.fl").read_text().splitlines()
    expected = [
        "piolite_pkg", "piolite_if", "piolite_imem", "piolite_fifo", "piolite_sm",
        "piolite_core", "piolite_gpio_guard", "piolite_dma_adapter", "piolite_reg", "apb4_piolite",
    ]
    positions = [sources.index(f"/ip/piolite/{name}.sv") for name in expected]
    assert positions == sorted(positions)
    assert "+incdir+/ip/piolite" in (TINY / "filelist/inc.fl").read_text().splitlines()


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_piolite_dma_admission_and_recovery(tmp_path: Path, simulator: str) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/generate_memory_map.py"),
            "--map", str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir", str(tmp_path / "map"), "--have-sram-if", "NO",
        ],
        check=True, capture_output=True, text=True,
    )
    log = run_rtl(
        tmp_path,
        simulator,
        "spi_dma_admit_tb",
        [
            COMMON / "utils/fifo.sv",
            COMMON / "stream/round_robin_arbiter.sv",
            COMMON / "interface/axi4_stream_if.sv",
            ROOT / "rtl/tiny/top/tiny_axi42apb4.sv",
            ROOT / "rtl/ip/peripheral/dma_req_if.sv",
            ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
            ROOT / "rtl/ip/peripheral/dma_reg.sv",
            ROOT / "rtl/ip/peripheral/dma_core.sv",
            ROOT / "rtl/ip/peripheral/apb4_dma.sv",
            ROOT / "rtl/ip/serial/spi_ctrl_if.sv",
            ROOT / "rtl/ip/serial/spi_reg.sv",
            ROOT / "rtl/ip/serial/spi_phase_ctrl.sv",
            ROOT / "rtl/ip/serial/spi_word_packer.sv",
            ROOT / "rtl/ip/serial/spi_gpio_guard.sv",
            ROOT / "rtl/ip/serial/spi_dma_pacing.sv",
            ROOT / "rtl/ip/serial/spi_master_core.sv",
            ROOT / "rtl/ip/serial/apb4_spi.sv",
        ],
        defines=[
            "-DPIOLITE_P3",
            f"-I{ROOT / 'rtl/ip/peripheral'}",
            f"-I{ROOT / 'rtl/ip/serial'}",
            f"-I{tmp_path / 'map/rtl'}",
        ],
        packages=[
            ROOT / "rtl/ip/peripheral/dma_pkg.sv",
            ROOT / "rtl/ip/serial/spi_pkg.sv",
        ],
    )
    assert "SIM_TEST_PASS PIOLITE_DMA_ADMIT_PASS" in log
    assert "SIM_TEST_FAIL" not in log and "SIM_TEST_TIMEOUT" not in log


def test_piolite_acceptance_image_is_explicit_and_isolated() -> None:
    base = ["make", "--no-print-directory", "CONFIG=configs/ci/ics55-tiny.mk", "APP=ci_smoke",
            "TINY_PIOLITE_P3_ACCEPTANCE=YES", "BUILD_TIMESTAMP=2026-11-18-06-00"]
    build = subprocess.run([*base, "-n", "firmware"], cwd=ROOT, text=True, capture_output=True,
                           check=False)
    assert build.returncode == 0, build.stdout + build.stderr
    assert "tiny_piolite_p3.c" in build.stdout
    assert "crt/src/hal/piolite.c" in build.stdout
    assert "tiny_r2_p6.c" not in build.stdout
    for override in ("TINY_P7_ACCEPTANCE=YES", "TINY_P8_ACCEPTANCE=YES",
                     "TINY_P9_ACCEPTANCE=YES", "TINY_P10_ACCEPTANCE=YES",
                     "TINY_SPI_P3_ACCEPTANCE=YES", "TINY_SPI_P4_ACCEPTANCE=YES",
                     "TINY_PPALITE_P3_ACCEPTANCE=YES", "TINY_PPALITE_P4_ACCEPTANCE=YES",
                     "APP=bringup", "SOC=MINI"):
        result = subprocess.run([*base, override, "config"], cwd=ROOT, text=True,
                                capture_output=True, check=False)
        assert result.returncode != 0, override


def test_piolite_observer_is_source_bound() -> None:
    observer = (TINY / "dv/tiny_piolite_observers.svh").read_text()
    testbench = (TINY / "dv/retrosoc_tiny_tb.sv").read_text()
    assert "tiny_piolite_observers.svh" in testbench
    assert "assign s_gpio = piolite_drive_value" in observer
    assert "force u_dut.u_soc.s_gpio_rst_n" in observer
    assert "PIOLITE_P3_OBSERVATION" in observer


GOOD_LOG = """PIOLITE_P3_CHECK id=1 pass=1 clock=24000000 mask=0003ffff
PIOLITE_P3_CHECK id=2 pass=1 pins=32
PIOLITE_P3_CHECK id=3 pass=1 shared=1
PIOLITE_P3_OUTPUT pin=4 value=1 oe=1
PIOLITE_P3_CHECK id=4 pass=1 output=1
PIOLITE_P3_CHECK id=5 pass=1 tx_bytes=4 rx_bytes=4
PIOLITE_P3_CHECK id=6 pass=1 tcds=2 tx_bytes=4
PIOLITE_P3_CHECK id=7 pass=1 rcu=1
PIOLITE_P3_RESET seen=1
PIOLITE_P3_CHECK id=8 pass=1 reset=1
PIOLITE_P3_OBSERVATION mask=ffffffff reset_seen=1 output_oe=00000000
PIOLITE_P3_RESULT code=0
SIM_TEST_PASS Tiny cycles=12345
"""


def test_piolite_checker_accepts_only_complete_records() -> None:
    from scripts.piolite_p3 import check_log
    assert check_log(GOOD_LOG) == []


@pytest.mark.parametrize("old,new", [
    ("mask=ffffffff", "mask=0000ffff"),
    ("reset_seen=1", "reset_seen=0"),
    ("PIOLITE_P3_CHECK id=3 pass=1 shared=1\n", ""),
    ("PIOLITE_P3_OUTPUT pin=4 value=1 oe=1", "PIOLITE_P3_OUTPUT pin=4 value=0 oe=0"),
    ("PIOLITE_P3_RESULT code=0", "PIOLITE_P3_RESULT code=0\nPIOLITE_P3_RESULT code=0"),
    ("PIOLITE_P3_CHECK id=1 pass=1", "PIOLITE_P3_CHECK id=1 id=1 pass=1"),
    ("PIOLITE_P3_RESET seen=1", "PIOLITE_P3_RESET seen=1\nPIOLITE_P3_RESET seen=1"),
    ("SIM_TEST_PASS Tiny cycles=12345", "SIM_TEST_TIMEOUT Tiny cycles=12345"),
])
def test_piolite_checker_rejects_incomplete_or_invalid_records(old: str, new: str) -> None:
    from scripts.piolite_p3 import check_log
    assert check_log(GOOD_LOG.replace(old, new)) != []


def test_piolite_observer_uses_dedicated_reset_and_real_output() -> None:
    observer = (TINY / "dv/tiny_piolite_observers.svh").read_text()
    firmware = (ROOT / "app/apps/ci_smoke/tiny_piolite_p3.c").read_text()
    output_case = firmware.split("static rs_status_t rs_pio_output(void)", 1)[1].split(
        "static rs_status_t rs_pio_direct_dma(void)", 1)[0]
    assert "UINT16_C(0x1001)" in output_case
    assert "UINT16_C(0x2001)" in output_case
    assert "u_ctrl.runtime" not in observer
    assert "u_ctrl.cfg" not in observer
    assert "piolite_pkg::" not in observer
    assert "imem_write_data == 16'h9000" in observer
    assert "cmd_start[0]" in observer
    assert "oe_o[4] && s_gpio[4]" in observer
    release = observer.split("if (piolite_reset_countdown == 5)", 1)[1]
    assert "release u_dut.u_soc.s_gpio_rst_n" in release
    assert "piolite_reset_countdown = 0" in release


def evidence_identity(tmp_path: Path) -> tuple[dict, dict, dict, Path]:
    from scripts.flow_control import digest_json
    from scripts.piolite_p3 import file_sha256

    variant = tmp_path / "build/ihp130-tiny-test"
    log = variant / "sim/verilator/sim.log"
    command = [
        "timeout", "--foreground", "43200s", str(variant / "sim/verilator/emu"),
        f"+firmware={variant / 'sw/retrosoc_fw.hex'}", "+max_cycles=20000000",
        "+tiny_piolite_p3",
    ]
    lock = file_sha256(ROOT / "dependencies/dependencies.lock.json")
    manifest = {
        "repository": {"commit": "a" * 40, "dirty": False},
        "dependency_lock": {"path": "dependencies/dependencies.lock.json", "sha256": lock},
        "profile": "ihp130-tiny",
        "configuration": {"SOC": "TINY", "PDK": "IHP130", "EXT_CLK_HZ": "24000000"},
        "tools": {"verilator": "test-version"},
        "filelists": {},
    }
    verdict = {
        "source_revision": "a" * 40,
        "source_dirty": False,
        "source_state_sha256": "b" * 64,
        "tool_lock_sha256": lock,
        "tool": "verilator-sim",
        "exit_code": 0,
        "log": str(log),
        "command": command,
        "command_sha256": digest_json(command),
    }
    state = {
        "source_revision": "a" * 40,
        "source_dirty": False,
        "source_state_sha256": "b" * 64,
        "tool_lock_sha256": lock,
    }
    return manifest, verdict, state, log


def test_piolite_evidence_identity_is_complete_and_fail_closed(tmp_path: Path,
                                                                monkeypatch: pytest.MonkeyPatch) -> None:
    from scripts.piolite_p3 import identity_problems

    manifest, verdict, state, log = evidence_identity(tmp_path)
    variant = tmp_path / "build/ihp130-tiny-test"
    monkeypatch.setattr("scripts.piolite_p3.source_state", lambda root: state)
    assert identity_problems(manifest, verdict, variant, "IHP130", "verilator", log) == []
    for field in ("source_revision", "source_state_sha256", "tool_lock_sha256"):
        broken = dict(verdict)
        broken[field] = "0" * (40 if field == "source_revision" else 64)
        assert identity_problems(manifest, broken, variant, "IHP130", "verilator", log)
    broken = dict(verdict)
    broken["command"] = [item.replace("20000000", "1000000") for item in verdict["command"]]
    assert identity_problems(manifest, broken, variant, "IHP130", "verilator", log)
    broken = dict(verdict)
    broken["log"] = str(tmp_path / "other.log")
    assert identity_problems(manifest, broken, variant, "IHP130", "verilator", log)
    broken_manifest = dict(manifest)
    broken_manifest["profile"] = "ihp130"
    assert identity_problems(broken_manifest, verdict, variant, "IHP130", "verilator", log)


def test_piolite_evidence_record_binds_program_and_execution(tmp_path: Path) -> None:
    from scripts.piolite_p3 import base_record, file_sha256

    manifest, _, _, _ = evidence_identity(tmp_path)
    variant = tmp_path / "build/ihp130-tiny-test"
    (variant / "sw").mkdir(parents=True)
    for name in ("retrosoc_fw.hex", "retrosoc_fw.bin", "retrosoc_fw.txt"):
        (variant / "sw" / name).write_text(name)
    record = base_record(manifest, variant, "check", "IHP130", ["make", "sim"], ["gap"])
    required = {
        "source_revision", "dependency_lock_sha256", "profile", "pdk", "variant",
        "tool_versions", "source_programs", "clock_rates_hz", "pin_assignment_electrical_model",
        "dma_bindings", "command", "firmware_sha256", "observed_gaps",
    }
    assert required <= record.keys()
    program = record["source_programs"][0]
    assert program["source"] == "app/apps/ci_smoke/tiny_piolite_p3.c"
    assert program["observer"] == "rtl/tiny/dv/tiny_piolite_observers.svh"
    assert program["assembled_image_sha256"] == file_sha256(variant / "sw/retrosoc_fw.hex")
    assert program["assembled_binary_sha256"] == file_sha256(variant / "sw/retrosoc_fw.bin")
    assert program["disassembly_sha256"] == file_sha256(variant / "sw/retrosoc_fw.txt")
    assert record["observed_gaps"] == ["gap"]
    assert record["phase_accepted"] is False


def test_piolite_check_entrypoint_writes_bound_verdicts() -> None:
    import tempfile

    from scripts.flow_control import digest_json, source_state
    from scripts.piolite_p3 import file_sha256

    revision = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    current = source_state(ROOT)
    lock = file_sha256(ROOT / "dependencies/dependencies.lock.json")
    for stale in (False, True):
        with tempfile.TemporaryDirectory(prefix="piolite-p3-test-", dir=ROOT / "build") as directory:
            variant = Path(directory)
            (variant / "meta").mkdir()
            (variant / "sw").mkdir()
            (variant / "sim/verilator").mkdir(parents=True)
            for name in ("retrosoc_fw.hex", "retrosoc_fw.bin", "retrosoc_fw.txt"):
                (variant / "sw" / name).write_text(name)
            (variant / "sim/verilator/emu").write_text("test executable")
            log = variant / "sim/verilator/sim.log"
            log.write_text(GOOD_LOG)
            command = [
                "timeout", "--foreground", "43200s", str(variant / "sim/verilator/emu"),
                f"+firmware={variant / 'sw/retrosoc_fw.hex'}", "+max_cycles=20000000",
                "+tiny_piolite_p3",
            ]
            manifest = {
                "repository": {"commit": "0" * 40 if stale else revision,
                               "dirty": current["source_dirty"]},
                "dependency_lock": {"path": "dependencies/dependencies.lock.json", "sha256": lock},
                "profile": "ihp130-tiny",
                "configuration": {
                    "SOC": "TINY", "PDK": "IHP130", "APP": "ci_smoke",
                    "TINY_PIOLITE_P3_ACCEPTANCE": "YES", "SIMU": "VERILATOR",
                    "EXT_CLK_HZ": "24000000",
                },
                "tools": {"verilator": "test-version"},
                "filelists": {},
            }
            verdict = {
                "status": "passed",
                "source_revision": revision,
                "source_dirty": current["source_dirty"],
                "source_state_sha256": current["source_state_sha256"],
                "tool_lock_sha256": lock,
                "tool": "verilator-sim",
                "exit_code": 0,
                "log": str(log),
                "command": command,
                "command_sha256": digest_json(command),
            }
            (variant / "meta/manifest.json").write_text(json.dumps(manifest))
            (variant / "sim/verilator/result-sim.json").write_text(json.dumps(verdict))
            (variant / "sim/verilator/result-sim-check.json").write_text('{"status": "passed"}')
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/piolite_p3.py"), "check",
                 "--variant-root", str(variant), "--pdk", "IHP130", "--simulator", "verilator",
                 "--log", str(log)], cwd=ROOT, text=True, capture_output=True, check=False)
            record = json.loads((variant / "meta/piolite-p3/check/record.json").read_text())
            if stale:
                assert result.returncode != 0
                assert record["status"] == "failed"
                assert "source revision is missing or differs between manifest and simulation" in record["problems"]
            else:
                assert result.returncode == 0, result.stdout + result.stderr
                assert record["status"] == "passed"
                assert record["problems"] == []
                assert record["source_revision"] == revision
                assert record["command"] == command
                assert record["observed_gaps"]
