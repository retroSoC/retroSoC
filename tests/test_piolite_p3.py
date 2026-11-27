"""PIOLITE-P3 topology, DMA lifecycle, and Mini default-off integration checks."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from test_tiny_r2_p7 import COMMON, ROOT, run_rtl

TINY = ROOT / "rtl/tiny"


def test_tiny_piolite_topology_and_rcu() -> None:
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    memory = json.loads((TINY / "address_map/memory_map.json").read_text())
    regions = {row["symbol"]: row for row in memory["regions"]}
    assert regions["APB4_PIOLITE"]["base"] == "0x1001C000"
    assert topology["fabric"]["target_count"] == 31
    assert topology["fabric"]["decode_error_target"] == 29
    assert topology["fabric"]["protocol_error_target"] == 30
    assert topology["dma_request_mask"] == "0x3f9ff"
    assert any(row["name"] == "piolite" and row["regions"] == ["APB4_PIOLITE"]
               for row in topology["apb_targets"])
    assert {row["core_bit"] for row in topology["interrupts"] if row["name"] == "piolite"} == {24}
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert ".TargetMask (18'h3ffff)" in top
    assert "s_piolite_lifecycle_idle" in top
    assert "u_piolite_tx_axis_if" in top and "u_piolite_rx_axis_if" in top


def test_mini_piolite_is_default_off() -> None:
    top = (ROOT / "rtl/mini/top/apb4_periph.sv").read_text()
    assert "piolite_tx_admit_i ('0)" in top
    assert "piolite_rx_admit_i ('0)" in top
    assert "piolite_tx_proc = 1'b0" in top
    assert "piolite_rx_proc = 1'b0" in top
    assert "EnablePiolite" not in top
    software = (ROOT / "rtl/mk/software.mk").read_text()
    common_sources, tiny_sources = software.split("ifeq ($(SOC),TINY)", 1)
    assert "crt/src/hal/piolite.c" not in common_sources
    assert "CRT_SRCS       += $(ROOT_PATH)/crt/src/hal/piolite.c" in tiny_sources


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_piolite_p3_dma_lifecycle(tmp_path: Path, simulator: str) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(tmp_path / "map"),
            "--have-sram-if",
            "NO",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    log = run_rtl(
        tmp_path,
        simulator,
        "piolite_p3_dma_tb",
        [
            COMMON / "utils/fifo.sv",
            COMMON / "stream/round_robin_arbiter.sv",
            COMMON / "interface/axi4_stream_if.sv",
            ROOT / "rtl/ip/peripheral/dma_req_if.sv",
            ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
            ROOT / "rtl/ip/peripheral/dma_core.sv",
        ],
        defines=[
            f"-I{ROOT / 'rtl/ip/peripheral'}",
            f"-I{ROOT / 'rtl/mini/top'}",
            f"-I{COMMON / 'utils'}",
            f"-I{tmp_path / 'map/rtl'}",
        ],
        packages=[ROOT / "rtl/ip/peripheral/dma_pkg.sv"],
    )
    assert "PIOLITE_P3_DMA direct=1 tcd=1 abort=1 residual=1" in log



@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_mini_piolite_dma_is_disabled(tmp_path: Path, simulator: str) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(tmp_path / "map"),
            "--have-sram-if",
            "NO",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    log = run_rtl(
        tmp_path,
        simulator,
        "piolite_p3_dma_tb",
        [
            COMMON / "utils/fifo.sv",
            COMMON / "stream/round_robin_arbiter.sv",
            COMMON / "interface/axi4_stream_if.sv",
            ROOT / "rtl/ip/peripheral/dma_req_if.sv",
            ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
            ROOT / "rtl/ip/peripheral/dma_core.sv",
        ],
        defines=[
            "-DPIOLITE_MINI_DEFAULT",
            f"-I{ROOT / 'rtl/ip/peripheral'}",
            f"-I{ROOT / 'rtl/mini/top'}",
            f"-I{COMMON / 'utils'}",
            f"-I{tmp_path / 'map/rtl'}",
        ],
        packages=[ROOT / "rtl/ip/peripheral/dma_pkg.sv"],
    )
    assert "PIOLITE_MINI_DEFAULT_OFF" in log


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_piolite_p3_gpio_and_binding_lifecycle(tmp_path: Path, simulator: str) -> None:
    peripheral = ROOT / "rtl/ip/peripheral"
    piolite = ROOT / "rtl/ip/piolite"
    log = run_rtl(
        tmp_path,
        simulator,
        "piolite_p3_gpio_tb",
        [
            peripheral / "gpio_if.sv",
            peripheral / "user_gpio_if.sv",
            peripheral / "gpio_core.sv",
            peripheral / "gpio_reg.sv",
            peripheral / "apb4_gpio.sv",
            COMMON / "clkrst/counter.sv",
            COMMON / "utils/edge_det.sv",
            ROOT / "rtl/ip/util/soc_common_fifo.sv",
            piolite / "piolite_if.sv",
            piolite / "piolite_imem.sv",
            piolite / "piolite_fifo.sv",
            piolite / "piolite_sm.sv",
            piolite / "piolite_core.sv",
            piolite / "piolite_gpio_guard.sv",
            piolite / "piolite_dma_adapter.sv",
            piolite / "piolite_reg.sv",
            piolite / "apb4_piolite.sv",
        ],
        defines=[
            f"-I{peripheral}",
            f"-I{piolite}",
            f"-I{COMMON}",
            f"-I{COMMON / 'utils'}",
        ],
        packages=[piolite / "piolite_pkg.sv"],
    )
    assert "PIOLITE_P3_GPIO all32=1 gpio31=1 guards=1 reset_rearm=1 bind_race=1" in log


def test_piolite_formal_cover_uses_sby_xml_identity(tmp_path: Path) -> None:
    from scripts.piolite_p2 import EXPECTED_COVERS, validate_cover

    converted = tmp_path / "top_cover.v"
    converted.write_text("".join(f"  cover ({goal});\n" for goal in EXPECTED_COVERS))
    model = tmp_path / "design_smt2.smt2"
    model.write_text("".join(
        f"; yosys-smt2-cover {index} cover{index}\n" for index in range(len(EXPECTED_COVERS))
    ))
    engine = tmp_path / "engine_0"
    engine.mkdir()
    trace_indices = (0, 3, 3, 1, 2, 4)
    for index in set(trace_indices):
        (engine / f"trace{index}.yw").write_text(
            '{"format":"Yosys Witness Trace","steps":[{}]}\n'
        )
    (tmp_path / "top_cover.xml").write_text(
        '<testsuite>\n' + "".join(
            f'<testcase type="COVER" id="cover{index}" '
            f'tracefile="engine_0/trace{trace}.yw"/>\n'
            for index, trace in enumerate(trace_indices)
        ) + '</testsuite>\n'
    )
    sites = validate_cover(tmp_path, "", converted, model)
    assert [site["witness"] for site in sites] == [
        f"engine_0/trace{index}.yw" for index in trace_indices
    ]
    (engine / "trace4.yw").unlink()
    with pytest.raises(ValueError, match="nonzero OE|no witness"):
        validate_cover(tmp_path, "", converted, model)


def test_piolite_p3_source_bound_checker_rejects_bad_verdicts() -> None:
    from scripts.piolite_p3 import check_log

    golden = "SIM_TEST_PASS Tiny cycles=123456\n"
    assert check_log(golden) == []
    corrupted = (
        "",
        golden + "SIM_TEST_TIMEOUT Tiny cycles=123456\n",
        golden.replace("cycles=123456", "cycles=0"),
        golden + "SIM_TEST_PASS Tiny cycles=123456\n",
        golden + "%Error: injected\n",
    )
    for log in corrupted:
        assert check_log(log)


def test_piolite_p3_source_bound_checker_writes_record() -> None:
    import tempfile

    from scripts.flow_control import file_digest, source_state
    from scripts.piolite_p3 import configuration_digest, evaluate

    identity = source_state(ROOT)
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
        variant = Path(directory).resolve()
        (variant / "meta").mkdir()
        (variant / "sw").mkdir()
        (variant / "sim/verilator").mkdir(parents=True)
        manifest = {
            "configuration": {
                "SOC": "TINY",
                "PDK": "IHP130",
                "SIMU": "VERILATOR",
                "TINY_PIOLITE_P3_ACCEPTANCE": "YES",
            },
            "repository": {"commit": identity["source_revision"], "dirty": identity["source_dirty"]},
            "dependency_lock": {"sha256": identity["tool_lock_sha256"]},
            "profile": "ihp130-tiny",
        }
        (variant / "meta/manifest.json").write_text(json.dumps(manifest))
        firmware = variant / "sw/retrosoc_fw.hex"
        firmware.write_text("firmware\n")
        emulator = variant / "sim/verilator/emu"
        emulator.write_text("simulator\n")
        log = variant / "sim/verilator/sim.log"
        log.write_text("SIM_TEST_PASS Tiny cycles=123456\n")
        (variant / "sim/verilator/result-sim-check.json").write_text(
            json.dumps({"status": "passed", "log": str(log)})
        )
        flow = {
            "status": "passed",
            "exit_code": 0,
            "log": str(log),
            "command": [str(emulator), f"+firmware={firmware}", "+piolite_p3_loopback"],
            "source_revision": identity["source_revision"],
            "source_dirty": identity["source_dirty"],
            "source_state_sha256": identity["source_state_sha256"],
            "tool_lock_sha256": identity["tool_lock_sha256"],
            "configuration": {"pdk": "IHP130", "soc": "TINY", "profile": "ihp130-tiny"},
            "input_sha256": {
                str(firmware): file_digest(firmware),
                str(emulator): file_digest(emulator),
            },
        }
        flow_path = variant / "sim/verilator/result-sim.json"
        flow_path.write_text(json.dumps(flow))
        result = subprocess.run([
            sys.executable,
            str(ROOT / "scripts/piolite_p3.py"),
            "check",
            "--variant-root",
            str(variant),
            "--pdk",
            "IHP130",
            "--simulator",
            "verilator",
            "--log",
            str(log),
        ], cwd=ROOT, capture_output=True, text=True, check=False)
        assert result.returncode == 0, result.stdout + result.stderr
        record = json.loads((variant / "meta/piolite-p3/check/record.json").read_text())
        assert record["status"] == "passed" and record["problems"] == []
        assert record["phase_accepted"] is False
        assert record["configuration_digest"] == configuration_digest(manifest)
        for key in ("manifest_sha256", "firmware_sha256", "simulator_sha256", "log_sha256"):
            assert len(record[key]) == 64

        mutations = {
            "missing source hash": {"source_state_sha256": None},
            "revision mismatch": {"source_revision": "0" * 40},
            "source mutation": {"source_state_sha256": "1" * 64},
            "missing input hashes": {"input_sha256": {}},
            "tool lock mismatch": {"tool_lock_sha256": "0" * 64},
            "alternate flow log": {"log": str(log) + ".alternate"},
            "missing flow log": {"log": None},
        }
        for name, changes in mutations.items():
            flow_path.write_text(json.dumps(flow | changes))
            rejected = evaluate(variant, "IHP130", "verilator", log)
            assert rejected["status"] == "failed" and rejected["problems"], name
        flow_path.write_text(json.dumps(flow))
        verdict_path = variant / "sim/verilator/result-sim-check.json"
        verdict_path.write_text(json.dumps({"status": "passed", "log": str(log) + ".alternate"}))
        rejected = evaluate(variant, "IHP130", "verilator", log)
        assert rejected["status"] == "failed"
        assert any("verdict log identity" in problem for problem in rejected["problems"])
        verdict_path.write_text(json.dumps({"status": "passed", "log": str(log)}))
        emulator.write_text("replacement\n")
        rejected = evaluate(variant, "IHP130", "verilator", log)
        assert rejected["status"] == "failed"
        assert any("input hashes" in problem for problem in rejected["problems"])
