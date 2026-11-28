"""PIOLITE-P4 application qualification and source-bound acceptance checks."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from piolite_asm import assemble, emit_c  # noqa: E402
from piolite_isa import InstructionAllocator  # noqa: E402

SCENARIOS = (
    "LOGIC_CAPTURE",
    "PULSE",
    "UART",
    "SPI",
    "IR",
    "LED",
    "GAMEPAD",
    "CONTENTION",
)


def test_p4_uses_isolated_bringup_scenario_variants() -> None:
    makefile = (ROOT / "Makefile").read_text()
    bringup = (ROOT / "app/apps/bringup/tiny.mk").read_text()
    assert "TINY_PIOLITE_P4_ACCEPTANCE ?= NO" in makefile
    assert "TINY_PIOLITE_P4_SCENARIO   ?= LOGIC_CAPTURE" in makefile
    assert "APP                        := bringup" in makefile
    assert "CONFIG_KEY_VARS += TINY_PIOLITE_P4_ACCEPTANCE TINY_PIOLITE_P4_SCENARIO" in makefile
    assert "TINY/bringup/YES" in makefile
    assert "generated/piolite" in bringup
    assert "RS_PIOLITE_P4_SCENARIO_$(TINY_PIOLITE_P4_SCENARIO)" in bringup
    for scenario in SCENARIOS:
        assert scenario in makefile


def test_all_application_objects_are_deterministic_and_fit_imem() -> None:
    sources = sorted((ROOT / "app/asm/piolite").glob("*.piolite"))
    assert {source.stem for source in sources} >= {
        "logic_capture",
        "pulse_generate",
        "pulse_capture",
        "uart_tx",
        "uart_rx",
        "spi_master",
        "ir_tx",
        "ir_rx",
        "led_scan",
        "gamepad",
    }
    for source in sources:
        text = source.read_text(encoding="utf-8")
        program = assemble(text)
        assert len(program.instructions) <= 32, source.name
        assert emit_c(program) == emit_c(assemble(text)), source.name


@pytest.mark.parametrize(
    ("first", "second"),
    (("pulse_generate", "pulse_capture"), ("uart_tx", "uart_rx"), ("ir_tx", "ir_rx")),
)
def test_p4_required_dual_sm_images_fit(first: str, second: str) -> None:
    allocator = InstructionAllocator()
    for name in (first, second):
        source = ROOT / "app/asm/piolite" / f"{name}.piolite"
        allocator.load(assemble(source.read_text(encoding="utf-8")))
    assert allocator.valid_bitmap.bit_count() <= 32


@pytest.mark.parametrize("mode", range(4))
def test_spi_program_supports_all_frame_widths_at_twelve_ticks(mode: int) -> None:
    name = "spi_master" if mode == 0 else f"spi_master_mode{mode}"
    source = ROOT / "app/asm/piolite" / f"{name}.piolite"
    program = assemble(source.read_text(encoding="utf-8"))
    assert len(program.instructions) == 15
    assert program.instructions[14].opcode.name == "CTRL"
    assert program.flag_mask == 0
    assert program.tx.bits == 32 and program.tx.mode == "manual"
    assert program.rx.bits == 8 and program.rx.mode == "auto"
    assert program.packing.tx_items == 0 and program.packing.rx_items == 0
    assert program.timing.clock_ticks == 12
    loop = program.instructions[8:13]
    assert sum(1 + instruction.delay for instruction in loop) == 12
    move = program.instructions[7]
    assert move.opcode.name == "MOVE" and move.operand == 0x98
    assert program.instructions[12].opcode.name == "BRANCH"


def logic_observations() -> str:
    lines = []
    for pattern in range(3):
        lines.append(
            f"PIOLITE_P4_LOGIC pattern={pattern} samples=32768 words=8192 "
            "first=31 last=ac fnv=1234abcd stalls=0"
        )
    for pattern in range(3):
        lines.append(
            f"PIOLITE_P4_BFM_LOGIC pattern={pattern} samples=32768 "
            "first=31 last=ac fnv=1234abcd min_period=24 max_period=24"
        )
    lines.extend(("PIOLITE_P4_RESULT scenario=LOGIC_CAPTURE code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    return "\n".join(lines) + "\n"


def test_p4_logic_checker_requires_matching_independent_observations() -> None:
    from piolite_p4 import check_log

    golden = logic_observations()
    assert check_log(golden, "LOGIC_CAPTURE") == []
    corrupted = (
        "",
        golden + "SIM_TEST_TIMEOUT Tiny cycles=123456\n",
        golden + "SIM_TEST_PASS Tiny cycles=123456\n",
        golden.replace("words=8192", "words=8191", 1),
        golden.replace("min_period=24", "min_period=23", 1),
        golden.replace("fnv=1234abcd", "fnv=deadbeef", 1),
        golden.replace("PIOLITE_P4_LOGIC pattern=1", "PIOLITE_P4_LOGIC pattern=0", 1),
        golden.replace("code=0", "code=1"),
        golden.replace("first=31", "first=30", 1),
    )
    for log in corrupted:
        assert check_log(log, "LOGIC_CAPTURE")


def test_p4_program_evidence_rebinds_every_generated_object(tmp_path: Path) -> None:
    from piolite_p4 import PROGRAM_NAMES, program_evidence

    generated = tmp_path / "generated/piolite"
    generated.mkdir(parents=True)
    for name in PROGRAM_NAMES:
        source = ROOT / "app/asm/piolite" / f"{name}.piolite"
        generated.joinpath(f"{name}.c").write_text(
            emit_c(assemble(source.read_text(encoding="utf-8"))), encoding="utf-8"
        )
    records, problems = program_evidence(tmp_path)
    assert problems == []
    assert len(records) == len(PROGRAM_NAMES)
    assert all(record["word_count"] <= 32 for record in records)
    generated.joinpath("uart_tx.c").write_text("corrupted\n", encoding="utf-8")
    _, problems = program_evidence(tmp_path)
    assert "generated object is not source-bound: uart_tx" in problems


def test_p4_pulse_checker_binds_capture_to_wire_widths() -> None:
    from piolite_p4 import check_log

    durations = ((3, 5), (8, 2), (1, 1), (0, 1), (1, 0), (65535, 1))
    lines = []
    for index, (high, low) in enumerate(durations):
        lines.append(
            f"PIOLITE_P4_PULSE case={index} high={high} low={low} "
            f"capture={2 * max(1, (high + 1) // 2)} done=1"
        )
    lines.append("PIOLITE_P4_PULSE_ABORT complete=1")
    for index, (high, low) in enumerate(durations):
        lines.append(f"PIOLITE_P4_BFM_PULSE case={index} high={max(2, high)} low={max(2, low)}")
    lines.extend((
        "PIOLITE_P4_BFM_PULSE_ABORT complete=1",
        "PIOLITE_P4_RESULT scenario=PULSE code=0",
        "SIM_TEST_PASS Tiny cycles=123456",
    ))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "PULSE") == []
    assert check_log(golden.replace("PIOLITE_P4_BFM_PULSE case=0 high=3 low=5",
                                    "PIOLITE_P4_BFM_PULSE case=0 high=3 low=6"), "PULSE")
    assert check_log(golden.replace("capture=4", "capture=9", 1), "PULSE")
    assert check_log(golden.replace("done=1", "done=0", 1), "PULSE")
    assert check_log(golden.replace("PIOLITE_P4_BFM_PULSE_ABORT complete=1\n", ""), "PULSE")


def test_p4_spi_checker_covers_modes_widths_and_waveforms() -> None:
    from piolite_p4 import check_log

    lines = ["PIOLITE_P4_SPI_STARVATION safe=1", "PIOLITE_P4_BFM_SPI_STARVATION safe=1"]
    for mode in range(4):
        for width in (8, 16, 32):
            mask = 0xFFFFFFFF if width == 32 else (1 << width) - 1
            tx = (0xA5C33C96 ^ (mode * 0x00102040) ^ (width << 1)) & mask
            rx = (0x5A3CC35A ^ (mode * 0x01020408) ^ width) & mask
            lines.append(
                f"PIOLITE_P4_SPI mode={mode} width={width} tx={tx:08x} rx={rx:08x} rate=1000000"
            )
            lines.append(
                f"PIOLITE_P4_BFM_SPI mode={mode} width={width} tx={tx:08x} rx={rx:08x} "
                "rate=1000000 setup=3 hold=2"
            )
    lines.extend(("PIOLITE_P4_RESULT scenario=SPI code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "SPI") == []
    assert check_log(golden.replace("setup=3", "setup=0", 1), "SPI")
    assert check_log(golden.replace("rate=1000000", "rate=999999", 1), "SPI")
    assert check_log(golden.replace("PIOLITE_P4_BFM_SPI_STARVATION safe=1\n", ""), "SPI")
    assert check_log(golden.replace("PIOLITE_P4_BFM_SPI mode=0 width=8", "PIOLITE_P4_BFM_SPI mode=1 width=8"), "SPI")


def test_p4_uart_checker_binds_baud_data_and_phase() -> None:
    from piolite_p4 import check_log

    lines = []
    for case, phase in enumerate((0, 3, 7, 13)):
        hash_value = 2166136261
        for index in range(16):
            if index < 4:
                value = (0x00, 0xFF, 0xA5, 0x5A)[index] ^ phase
            else:
                value = ((index * 73) + (phase * 29) + ((index >> 2) * 11)) & 0xFF
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
        lines.append(
            f"PIOLITE_P4_UART case={case} phase={phase} bytes=16 baud=115384 "
            f"error_ppm=1603 fnv={hash_value:08x}"
        )
        lines.append(
            f"PIOLITE_P4_BFM_UART case={case} phase={phase} bytes=16 baud=115384 "
            f"error_ppm=1603 fnv={hash_value:08x}"
        )
    recovery_fnv = 2166136261
    for index in range(16):
        if index < 4:
            value = (0x00, 0xFF, 0xA5, 0x5A)[index]
        else:
            value = ((index * 73) + ((index >> 2) * 11)) & 0xFF
        recovery_fnv = ((recovery_fnv ^ value) * 16777619) & 0xFFFFFFFF
    for name in ("RX_STARVATION", "BREAK", "FRAMING", "TX_STARVATION"):
        lines.append(f"PIOLITE_P4_UART_{name} detected=1")
        lines.append(f"PIOLITE_P4_BFM_UART_{name} detected=1")
    lines.append(f"PIOLITE_P4_UART_RECOVERY phase=0 bytes=16 baud=115384 error_ppm=1603 fnv={recovery_fnv:08x}")
    lines.append(f"PIOLITE_P4_BFM_UART_RECOVERY phase=0 bytes=16 baud=115384 error_ppm=1603 fnv={recovery_fnv:08x}")
    lines.extend(("PIOLITE_P4_RESULT scenario=UART code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "UART") == []
    assert check_log(golden.replace("baud=115384", "baud=115200", 1), "UART")
    assert check_log(golden.replace("fnv=", "fnv=0", 1), "UART")
    assert check_log(golden.replace("phase=7", "phase=8"), "UART")
    assert check_log(golden.replace("PIOLITE_P4_BFM_UART_BREAK detected=1\n", ""), "UART")
    assert check_log(golden.replace("PIOLITE_P4_UART_RECOVERY", "PIOLITE_P4_UART_MISSING", 1), "UART")


def test_p4_firmware_has_real_generated_program_prerequisites() -> None:
    bringup = (ROOT / "app/apps/bringup/tiny.mk").read_text()
    assert "$(SW_BUILD_DIR)/firmware: $(PIOLITE_P4_GENERATED_C)" in bringup
    assert "$(FIRMWARE_ELF): $(PIOLITE_P4_GENERATED_C)" not in bringup


def test_p4_ir_checker_binds_carrier_and_pulse_quantization() -> None:
    from piolite_p4 import check_log

    expected = (((3, 4), (5, 7)), ((10, 2), (13, 9)), ((1, 1), (1, 11)))
    lines = []
    for case, (tx, rx) in enumerate(expected):
        lines.append(
            f"PIOLITE_P4_IR case={case} mark={tx[0]} space={tx[1]} high={rx[0]} low={rx[1]} "
            "rate=37915 error_ppm=2245"
        )
        measured_rate = 0 if case == 2 else 37915
        lines.append(
            f"PIOLITE_P4_BFM_IR case={case} mark={tx[0]} space={tx[1]} high={rx[0]} low={rx[1]} "
            f"rate={measured_rate} error_ppm=2245"
        )
    for name in ("TIMEOUT", "OVERFLOW"):
        lines.append(f"PIOLITE_P4_IR_{name} detected=1")
        lines.append(f"PIOLITE_P4_BFM_IR_{name} detected=1")
    lines.append("PIOLITE_P4_IR_RECOVERY mark=3 space=4 high=5 low=7 rate=37915 error_ppm=2245")
    lines.append("PIOLITE_P4_BFM_IR_RECOVERY mark=3 space=4 high=5 low=7 rate=37915 error_ppm=2245")
    lines.extend(("PIOLITE_P4_RESULT scenario=IR code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "IR") == []
    assert check_log(golden.replace("high=5", "high=9"), "IR")
    assert check_log(golden.replace("error_ppm=2245", "error_ppm=2253", 1), "IR")
    assert check_log(golden.replace("PIOLITE_P4_BFM_IR case=0 mark=3", "PIOLITE_P4_BFM_IR case=0 mark=4"), "IR")
    assert check_log(golden.replace("PIOLITE_P4_BFM_IR_OVERFLOW detected=1\n", ""), "IR")


def test_p4_led_checker_requires_frame_rate_blanking_and_rows() -> None:
    from piolite_p4 import check_log

    hash_value = 2166136261
    for index in range(16):
        row = index & 7
        columns = 0x81 ^ (row * 0x11) ^ (index >> 3)
        word = (columns << 8) | (1 << row)
        for value in (word & 0xFF, (word >> 8) & 0xFF):
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
    lines = [
        f"PIOLITE_P4_LED frames=2 rows=16 fps=389 blank=1 fnv={hash_value:08x}",
        "PIOLITE_P4_LED_ABORT blank=1",
        f"PIOLITE_P4_BFM_LED frames=2 rows=16 fps=389 blank=1 fnv={hash_value:08x}",
        "PIOLITE_P4_BFM_LED_ABORT blank=1",
        "PIOLITE_P4_RESULT scenario=LED code=0",
        "SIM_TEST_PASS Tiny cycles=123456",
    ]
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "LED") == []
    assert check_log(golden.replace("fps=389", "fps=199"), "LED")
    assert check_log(golden.replace("blank=1", "blank=0", 1), "LED")
    assert check_log(golden.replace("fnv=", "fnv=0", 1), "LED")
    assert check_log(golden.replace("PIOLITE_P4_BFM_LED_ABORT blank=1\n", ""), "LED")


def test_p4_gamepad_checker_covers_changing_disconnect_and_rearm() -> None:
    from piolite_p4 import check_log

    patterns = ([0xA5] * 4, [0x00, 0xFF, 0x5A, 0xC3], [0x00, 0xFF], [0x69] * 4)
    lines = []
    for session, values in enumerate(patterns):
        hash_value = 2166136261
        for value in values:
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
        disconnected = int(session == 2)
        lines.append(
            f"PIOLITE_P4_GAMEPAD session={session} scans={len(values)} "
            f"fnv={hash_value:08x} disconnected={disconnected}"
        )
        lines.append(
            f"PIOLITE_P4_BFM_GAMEPAD session={session} scans={len(values)} "
            f"fnv={hash_value:08x} disconnected={disconnected}"
        )
    lines.extend(("PIOLITE_P4_RESULT scenario=GAMEPAD code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "GAMEPAD") == []
    assert check_log(golden.replace("scans=2", "scans=4"), "GAMEPAD")
    assert check_log(golden.replace("disconnected=1", "disconnected=0"), "GAMEPAD")
    assert check_log(golden.replace("fnv=", "fnv=0", 1), "GAMEPAD")


def test_p4_contention_requires_background_cpu_and_service_gap() -> None:
    from piolite_p4 import check_log

    lines = []
    for pattern in range(3):
        lines.append(
            f"PIOLITE_P4_LOGIC pattern={pattern} samples=32768 words=8192 "
            "first=31 last=ac fnv=1234abcd stalls=0"
        )
        lines.append(f"PIOLITE_P4_CONTEND pattern={pattern} bg_done=1 heartbeat=123 iterations=2")
        lines.append(
            f"PIOLITE_P4_BFM_LOGIC pattern={pattern} samples=32768 "
            "first=31 last=ac fnv=1234abcd min_period=24 max_period=24"
        )
        lines.append(f"PIOLITE_P4_BFM_CONTEND pattern={pattern} longest_gap=17 overlap=23 late_overlap=11")
    lines.extend(("PIOLITE_P4_RESULT scenario=CONTENTION code=0", "SIM_TEST_PASS Tiny cycles=123456"))
    golden = "\n".join(lines) + "\n"
    assert check_log(golden, "CONTENTION") == []
    assert check_log(golden.replace("heartbeat=123", "heartbeat=0", 1), "CONTENTION")
    assert check_log(golden.replace("longest_gap=17", "longest_gap=0", 1), "CONTENTION")
    assert check_log(golden.replace("bg_done=1", "bg_done=0", 1), "CONTENTION")
    assert check_log(golden.replace("iterations=2", "iterations=1", 1), "CONTENTION")
    assert check_log(golden.replace("overlap=23", "overlap=0", 1), "CONTENTION")
    assert check_log(golden.replace("late_overlap=11", "late_overlap=0", 1), "CONTENTION")


def test_contention_uses_equal_dma_priorities() -> None:
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    capture = scenarios.split("rs_dma_config_t config = {", 1)[1].split("};", 1)[0]
    background = scenarios.split("rs_dma_config_t background_config = {", 1)[1].split("};", 1)[0]
    assert ".priority = 1U" in capture
    assert ".priority = 1U" in background
    assert ".burst_beats = 16U" in capture
    assert ".burst_beats = 16U" in background


def test_contention_bfm_measures_write_scheduler_wait() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    contention = testbench.split("logic s_p4_contend_active", 1)[1]
    assert "u_dut.u_soc.u_dma.u_dma_core.s_write_candidate[2]" in contention
    assert "u_dut.u_soc.u_dma.u_dma_core.s_axi_write_start_valid" in contention
    assert "u_dut.u_soc.u_dma.u_dma_core.s_axi_write_start_ready" in contention
    assert "(u_dut.u_soc.u_dma.u_dma_core.s_write_rr_selected == 2)" in contention


def test_p4_terminal_status_precedes_all_diagnostic_output() -> None:
    import re

    main = (ROOT / "app/apps/bringup/tiny_piolite_p4.c").read_text()
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    assert main.index("rs_sysctrl_write_test_status") < main.index("rs_p4_report_flush()")
    assert main.index("rs_p4_report_flush()") < main.index("for (;;)")
    assert re.search(r"(?<![A-Za-z0-9_])printf\(", main) is None
    assert re.search(r"(?<![A-Za-z0-9_])printf\(", scenarios) is None
    assert "RS_PIOLITE_P4_REPORT_BYTES  8192U" in scenarios
    assert "rs_p4_report_truncated = true" in scenarios


def test_p4_source_bound_checker_writes_record_and_rejects_tampering() -> None:
    import json
    import subprocess
    import tempfile

    from piolite_p4 import PROGRAM_NAMES, evaluate
    from scripts.flow_control import file_digest, source_state

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
                "APP": "bringup",
                "TINY_PIOLITE_P4_ACCEPTANCE": "YES",
                "TINY_PIOLITE_P4_SCENARIO": "LOGIC_CAPTURE",
            },
            "repository": {"commit": identity["source_revision"], "dirty": identity["source_dirty"]},
            "dependency_lock": {"sha256": identity["tool_lock_sha256"]},
            "profile": "ihp130-tiny",
        }
        (variant / "meta/manifest.json").write_text(json.dumps(manifest))
        generated = variant / "generated/piolite"
        generated.mkdir(parents=True)
        for name in PROGRAM_NAMES:
            source = ROOT / "app/asm/piolite" / f"{name}.piolite"
            generated.joinpath(f"{name}.c").write_text(
                emit_c(assemble(source.read_text(encoding="utf-8"))), encoding="utf-8"
            )
        firmware = variant / "sw/retrosoc_fw.hex"
        firmware.write_text("firmware\n")
        emulator = variant / "sim/verilator/emu"
        emulator.write_text("simulator\n")
        log = variant / "sim/verilator/sim.log"
        log.write_text(logic_observations())
        (variant / "sim/verilator/result-sim-check.json").write_text(
            json.dumps({"status": "passed", "log": str(log)})
        )
        flow = {
            "status": "passed",
            "exit_code": 0,
            "log": str(log),
            "command": [
                str(emulator),
                f"+firmware={firmware}",
                "+piolite_p4_loopback",
                "+piolite_p4_scenario_LOGIC_CAPTURE",
            ],
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
            str(ROOT / "scripts/piolite_p4.py"),
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
        record = json.loads((variant / "meta/piolite-p4/check/record.json").read_text())
        assert record["status"] == "passed" and record["problems"] == []
        assert record["phase_accepted"] is False
        assert len(record["programs"]) == len(PROGRAM_NAMES)

        mutations = {
            "missing source hash": {"source_state_sha256": None},
            "revision mismatch": {"source_revision": "0" * 40},
            "source mutation": {"source_state_sha256": "1" * 64},
            "missing input hashes": {"input_sha256": {}},
            "tool lock mismatch": {"tool_lock_sha256": "0" * 64},
            "alternate flow log": {"log": str(log) + ".alternate"},
            "missing scenario": {"command": [str(emulator), f"+firmware={firmware}"]},
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
        verdict_path.write_text(json.dumps({"status": "passed", "log": str(log)}))
        generated.joinpath("spi_master.c").write_text("corrupted\n")
        rejected = evaluate(variant, "IHP130", "verilator", log)
        assert rejected["status"] == "failed"
        assert "generated object is not source-bound: spi_master" in rejected["problems"]


def test_p4_report_drain_has_bounded_post_verdict_window() -> None:
    main = (ROOT / "app/apps/bringup/tiny_piolite_p4.c").read_text()
    testbench = (ROOT / "rtl/tiny/dv/retrosoc_tiny_tb.sv").read_text()
    assert "rs_uart_init(RS_PCLK_CLOCK_HZ, UINT32_C(1000000))" in main
    assert main.index("rs_uart_init") < main.index("rs_sysctrl_write_test_status")
    assert 'if ($test$plusargs("piolite_p4_loopback")) s_done_limit = 2000000;' in testbench


def test_finite_application_programs_do_not_depend_on_late_flag() -> None:
    names = (
        "spi_master",
        "spi_master_mode1",
        "spi_master_mode2",
        "spi_master_mode3",
        "uart_tx",
        "uart_rx",
        "ir_tx",
        "ir_rx",
        "pulse_capture",
    )
    for name in names:
        source = (ROOT / "app/asm/piolite" / f"{name}.piolite").read_text(encoding="utf-8")
        assert "TEST_FLAG_SET" not in source
        assert "CTRL HALT" in source


@pytest.mark.parametrize("high", (1, 3, 8, 65535))
def test_pulse_capture_complement_decode_and_finite_halt(high: int) -> None:
    from test_piolite_model import SMState, application_machine

    dut = application_machine("pulse_capture")
    dut.start(1)
    for edge in range(high + 14):
        dut.pin_inputs = (1 << 3) if edge < 2 or 4 <= edge < high + 4 else 0
        dut.step()
        if dut.sms[0].state == SMState.HALTED:
            break
    raw = dut.read_rx(0)
    assert raw == 65536 - ((high + 1) // 2)
    assert 2 * (65536 - raw) - high in (0, 1)
    assert dut.sms[0].state == SMState.HALTED


@pytest.mark.parametrize(("high", "low"), ((1, 7), (5, 9), (13, 11)))
def test_ir_capture_complement_decode_and_finite_halt(high: int, low: int) -> None:
    from test_piolite_model import SMState, application_machine

    dut = application_machine("ir_rx")
    dut.start(1)
    for edge in range(high + low + 8):
        dut.pin_inputs = (1 << 13) if edge < high or edge >= high + low else 0
        dut.step()
        if dut.sms[0].state == SMState.HALTED:
            break
    values = [dut.read_rx(0), dut.read_rx(0)]
    assert values == [65536 - ((high + 1) // 2), 65536 - ((low - 3) // 2)]
    decoded = [1 + 2 * (65535 - values[0]), 5 + 2 * (65535 - values[1])]
    assert decoded[0] - high in (-1, 0)
    assert decoded[1] == low
    assert dut.sms[0].state == SMState.HALTED


@pytest.mark.parametrize("mode", range(4))
def test_spi_wrap_reaches_halt_after_exact_frame(mode: int) -> None:
    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    name = "spi_master" if mode == 0 else f"spi_master_mode{mode}"
    allocation = InstructionAllocator().load(application_program(name))
    initial_value = 0x30 if mode & 1 else 0x20
    sm_config = SMConfig.from_allocation(
        allocation, initial_value=initial_value, initial_oe=initial_value, initial_y=7
    )
    dut = machine([allocation.words], [sm_config, config(1)])
    dut.write_tx(0, 0xA5)
    dut.start(1)
    for _ in range(1000):
        dut.step(rx_reads=[0])
        if dut.sms[0].state == SMState.HALTED:
            break
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].pc == sm_config.wrap_top
    assert not dut.sms[0].tx.items
    assert not dut.sms[0].rx.items


def test_ir_tx_wrap_reaches_halt_after_exact_mark_space_pair() -> None:
    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    allocation = InstructionAllocator().load(application_program("ir_tx"))
    sm_config = SMConfig.from_allocation(allocation)
    dut = machine([allocation.words], [sm_config, config(1)])
    dut.write_tx(0, 3)
    dut.write_tx(0, 4)
    dut.start(1)
    rising = []
    previous = 0
    for _ in range(100):
        dut.step()
        level = (dut.sms[0].output_value >> 12) & 1
        if level and not previous:
            rising.append(dut.pclk_edges)
        previous = level
        if dut.sms[0].state == SMState.HALTED:
            break
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].pc == sm_config.wrap_top
    assert len(rising) == 3
    assert [later - earlier for earlier, later in zip(rising, rising[1:], strict=False)] == [3, 3]
    assert not dut.sms[0].tx.items


def test_uart_malformed_stop_waits_at_pc10() -> None:
    from test_piolite_model import SMState, StallKind, application_machine

    dut = application_machine("uart_rx")
    dut.start(1)
    for _ in range(77):
        dut.pin_inputs = 0
        dut.step()
    assert dut.sms[0].state == SMState.RUNNING
    assert dut.sms[0].pc == 10
    assert dut.sms[0].stall == StallKind.PIN


def test_ir_ninth_push_blocks_with_fifo_full_and_stall_count() -> None:
    from test_piolite_model import Machine, SMConfig, SMState, application_program, config

    allocation = InstructionAllocator().load(application_program("ir_rx"))
    sm_config = SMConfig.from_allocation(allocation, initial_y=0xFFFF)
    dut = Machine((sm_config, config(1)))
    dut.publish(allocation)
    dut.start(1)
    stalled_pc = None
    for _ in range(5):
        for tick in range(17):
            dut.pin_inputs = (1 << 13) if tick < 5 else 0
            before_pc = dut.sms[0].pc
            before_stalls = dut.sms[0].rx_stall_count
            dut.step()
            if stalled_pc is None and dut.sms[0].rx_stall_count != before_stalls:
                stalled_pc = before_pc
    for _ in range(20):
        dut.step()
    assert dut.sms[0].state == SMState.RUNNING
    assert len(dut.sms[0].rx.items) == 8
    assert stalled_pc == 6
    assert dut.sms[0].rx_stall_count != 0
    assert dut.sms[0].events & (1 << 4)


def test_ir_bfm_covers_six_sessions_overflow_and_every_carrier_period() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    assert "s_p4_ir_tx_sessions != 6" in testbench
    assert "s_p4_ir_tx_cases != 6" in testbench
    assert "if (period != 633)" in testbench
    assert "(24000000 + 316) / 633" in testbench
    assert "pair < 6" in testbench
    assert "snapshot.rx_stall_count != 0U" in scenarios
    assert "s_p4_ir_last_period" not in testbench
    assert "runtime[0].pc == 11" not in testbench


def test_ir_adverse_session_finishes_tx_before_overflow() -> None:
    from test_piolite_model import Machine, SMConfig, SMState, application_program

    allocator = InstructionAllocator()
    tx_allocation = allocator.load(application_program("ir_tx"))
    rx_allocation = allocator.load(application_program("ir_rx"))
    dut = Machine((
        SMConfig.from_allocation(tx_allocation, divider=211),
        SMConfig.from_allocation(rx_allocation, divider=211, initial_y=0xFFFF),
    ))
    dut.publish(tx_allocation)
    dut.publish(rx_allocation)
    dut.write_tx(0, 3)
    dut.write_tx(0, 4)
    dut.start(3)
    durations = ((5, 7), (13, 9), (1, 11))
    tx_halt_edge = None
    rx_stall_edge = None
    for edge in range(20000):
        interval = (edge // 211) % 3
        pair = ((edge // 211) // 3) % 3
        if interval == 0:
            high = edge % 211 < durations[pair][0]
        elif interval == 1:
            high = False
        else:
            high = True
        dut.pin_inputs = (1 << 13) if high else 0
        dut.step()
        if tx_halt_edge is None and dut.sms[0].state == SMState.HALTED:
            tx_halt_edge = edge
        if dut.sms[1].rx_stall_count != 0:
            rx_stall_edge = edge
            break
    assert tx_halt_edge is not None
    assert rx_stall_edge is not None
    assert tx_halt_edge < rx_stall_edge


@pytest.mark.parametrize("mode", range(4))
@pytest.mark.parametrize("width", (8, 16, 32))
def test_spi_program_matches_independent_protocol_playback(mode: int, width: int) -> None:
    from dataclasses import replace

    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    name = "spi_master" if mode == 0 else f"spi_master_mode{mode}"
    allocation = InstructionAllocator().load(application_program(name))
    initial_value = 0x30 if mode & 1 else 0x20
    sm_config = replace(
        SMConfig.from_allocation(
            allocation,
            initial_value=initial_value,
            initial_oe=0x70,
            initial_y=width - 1,
        ),
        tx_bits=width,
    )
    dut = machine([allocation.words], [sm_config, config(1)])
    mask = 0xFFFFFFFF if width == 32 else (1 << width) - 1
    tx = (0xA5C33C96 ^ (mode * 0x00102040) ^ (width << 1)) & mask
    expected_rx = (0x5A3CC35A ^ (mode * 0x01020408) ^ width) & mask
    dut.write_tx(0, tx)
    dut.start(1)
    cpol = int(mode >= 2)
    cpha = mode & 1
    sck = (initial_value >> 4) & 1
    cs = (initial_value >> 5) & 1
    miso = 0
    mosi = 0
    bit_index = 0
    received = []
    for _ in range((width * 12) + 40):
        dut.pin_inputs = miso << 7
        result = dut.step(rx_reads=[0])
        if result.rx_read_values[0] is not None:
            received.append(result.rx_read_values[0])
        output = dut.sms[0].output_value
        next_sck = (output >> 4) & 1
        next_cs = (output >> 5) & 1
        if cs and not next_cs:
            bit_index = 0
            mosi = 0
            if cpha == 0:
                miso = expected_rx & 1
        elif not next_cs and next_sck != sck:
            leading = next_sck != cpol
            if leading:
                if cpha == 0:
                    mosi |= ((output >> 6) & 1) << bit_index
                else:
                    miso = (expected_rx >> bit_index) & 1
            else:
                if cpha != 0:
                    mosi |= ((output >> 6) & 1) << bit_index
                bit_index += 1
                if cpha == 0 and bit_index < width:
                    miso = (expected_rx >> bit_index) & 1
        sck = next_sck
        cs = next_cs
        if dut.sms[0].state == SMState.HALTED:
            break
    assert dut.sms[0].state == SMState.HALTED
    assert mosi == tx
    assert received == [(expected_rx >> (8 * index)) & 0xFF for index in range(width // 8)]
    assert bit_index == width
    assert dut.sms[0].osr_count == 0
    assert dut.sms[0].isr_count == 0


def test_uart_tx_program_emits_exact_sixteen_8n1_frames() -> None:
    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    allocation = InstructionAllocator().load(application_program("uart_tx"))
    sm_config = SMConfig.from_allocation(
        allocation, initial_value=1, initial_oe=1, initial_y=16
    )
    dut = machine([allocation.words], [sm_config, config(1)])
    expected = [
        (0x00, 0xFF, 0xA5, 0x5A)[index] if index < 4 else (index * 73) + ((index >> 2) * 11)
        for index in range(16)
    ]
    next_tx = 0
    dut.start(1)
    levels = []
    for _ in range((16 * 80) + 16):
        while next_tx < len(expected) and len(dut.sms[0].tx.items) < 8:
            dut.write_tx(0, expected[next_tx])
            next_tx += 1
        dut.step()
        levels.append(dut.sms[0].output_value & 1)
        if dut.sms[0].state == SMState.HALTED:
            break
    decoded = []
    for frame in range(16):
        start = 8 + (80 * frame)
        assert levels[start] == 0, (frame, start, levels[start - 2:start + 3])
        value = sum(levels[start + 8 + (8 * bit)] << bit for bit in range(8))
        assert levels[start + 72] == 1
        decoded.append(value)
    assert decoded == [value & 0xFF for value in expected]
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].osr_count == 0


def test_uart_pc2_marks_start_bit_for_both_data0_values() -> None:
    from test_piolite_model import SMConfig, application_program, config, machine

    allocation = InstructionAllocator().load(application_program("uart_tx"))
    sm_config = SMConfig.from_allocation(
        allocation, initial_value=1, initial_oe=1, initial_y=2
    )
    dut = machine([allocation.words], [sm_config, config(1)])
    expected = (1, 0)
    next_tx = 0
    previous_pc = 0
    transitions = {2: [], 3: [], 11: []}
    dut.start(1)
    for _ in range(176):
        while next_tx < len(expected) and len(dut.sms[0].tx.items) < 8:
            dut.write_tx(0, expected[next_tx])
            next_tx += 1
        dut.step()
        sm = dut.sms[0]
        if sm.pc != previous_pc and sm.pc in transitions:
            transitions[sm.pc].append((sm.tick_count, sm.output_value & 1))
        previous_pc = sm.pc
        if len(transitions[3]) == 2:
            break
    assert [pin for _, pin in transitions[2]] == [0, 0]
    assert [pin for _, pin in transitions[3]][:2] == [1, 0]
    assert transitions[2][1][0] - transitions[2][0][0] == 80
    assert transitions[11][0][1] == 1
    assert transitions[11][0][0] - transitions[2][0][0] == 72


def test_led_program_latches_exact_sixteen_rows() -> None:
    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    allocation = InstructionAllocator().load(application_program("led_scan"))
    sm_config = SMConfig.from_allocation(allocation, initial_y=16)
    dut = machine([allocation.words], [sm_config, config(1)])
    dut.start(1)
    next_tx = 0
    latches = 0
    previous_latch = 0
    for _ in range(1400):
        while next_tx < 16 and len(dut.sms[0].tx.items) < 8:
            row = next_tx & 7
            columns = 0x81 ^ (row * 0x11) ^ (next_tx >> 3)
            dut.write_tx(0, (columns << 8) | (1 << row))
            next_tx += 1
        dut.step()
        latch = (dut.sms[0].output_value >> 17) & 1
        if latch and not previous_latch:
            latches += 1
        previous_latch = latch
        if dut.sms[0].state == SMState.HALTED:
            break
    assert latches == 16
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].osr_count == 0


def test_gamepad_program_reads_exact_four_bytes() -> None:
    from test_piolite_model import SMConfig, SMState, application_program, config, machine

    allocation = InstructionAllocator().load(application_program("gamepad"))
    sm_config = SMConfig.from_allocation(allocation, initial_y=4)
    dut = machine([allocation.words], [sm_config, config(1)])
    dut.start(1)
    pattern = 0xA5
    sample_index = 0
    received = []
    for _ in range(200):
        dut.pin_inputs = ((pattern >> (sample_index & 7)) & 1) << 22
        before_pc = dut.sms[0].pc
        instruction = dut.imem[before_pc]
        result = dut.step(rx_reads=[0])
        if result.committed[0] and instruction >> 12 == 4:
            sample_index += 1
        if result.rx_read_values[0] is not None:
            received.append(result.rx_read_values[0])
        if dut.sms[0].state == SMState.HALTED:
            break
    assert received == [pattern] * 4
    assert sample_index == 32
    assert dut.sms[0].state == SMState.HALTED


def test_p4_timeout_override_is_rejected() -> None:
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    assert "#ifndef RS_PIOLITE_P4_TIMEOUT" not in scenarios
    assert '#error "RS_PIOLITE_P4_TIMEOUT is fixed by PIOLITE-P4 acceptance"' in scenarios
    assert "#define RS_PIOLITE_P4_TIMEOUT       UINT32_C(4000000)" in scenarios


def test_full_duplex_binds_both_directions_before_either_start() -> None:
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    for function in ("rs_p4_spi_transfer", "rs_p4_uart_duplex"):
        body = scenarios.split(f"static rs_status_t {function}", 1)[1].split("\n}\n", 1)[0]
        rx_bind = body.index("rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_RX")
        tx_bind = body.index("rs_piolite_dma_bind(&rs_p4_session.session, RS_PIOLITE_TX")
        rx_start = body.index("rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_RX")
        tx_start = body.index("rs_piolite_dma_start(&rs_p4_session.session, RS_PIOLITE_TX")
        sm_start = body.index("rs_piolite_start(&rs_p4_session.session")
        assert rx_bind < tx_bind < rx_start < tx_start < sm_start


def test_p4_isolates_legacy_uart_packet_observer() -> None:
    devices = (ROOT / "rtl/tiny/dv/tiny_p6_devices.svh").read_text()
    assert "if (!s_piolite_loopback)\n    forever begin" in devices
    assert "assign s_gpio_9 = s_piolite_loopback ? 1'bz : s_p6_uart_rx;" in devices


def test_pulse_abort_waits_actual_high_wait_pc() -> None:
    source = (ROOT / "app/asm/piolite/pulse_generate.piolite").read_text()
    instructions = [
        line for line in source.splitlines()
        if line.strip() and not line.startswith((".", ";"))
    ]
    high_wait_pc = next(index for index, line in enumerate(instructions) if line.startswith("high_wait:"))
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    assert high_wait_pc == 9
    abort_body = scenarios.split("static rs_status_t rs_p4_pulse_abort", 1)[1].split("\n}\n", 1)[0]
    assert f"(snapshot.pc & 0x1FU) == {high_wait_pc}U" in abort_body


def test_uart_and_ir_stimuli_wait_for_receiver_entry() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    expected = (
        "u_dut.u_soc.u_piolite.u_ctrl.runtime[1].pc == "
        "u_dut.u_soc.u_piolite.u_ctrl.cfg[1].entry"
    )
    assert testbench.count(expected) == 1
    assert "((phase_index >= 4) && (phase_index <= 6)) ? 0 : 1" in testbench
    assert "u_dut.u_soc.u_piolite.u_ctrl.runtime[rx_sm].state" in testbench
    assert "u_dut.u_soc.u_piolite.u_ctrl.cfg[rx_sm].entry" in testbench
    assert "repeat (208) @(negedge s_clk);" in testbench
    assert "repeat (211) @(negedge s_clk);" in testbench


def test_pulse_bfm_counts_only_actual_generator_phase_edges() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    assert "s_p4_pulse_pc_q == 5'd8" in testbench
    assert "s_p4_pulse_pc_q == 5'd12" in testbench
    assert "!s_gpio_2 && s_p4_pulse_level_q && s_p4_pulse_high_valid" in testbench


def test_uart_bfm_preserves_normal_timing_and_skips_starved_stop() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    scenarios = (ROOT / "app/apps/bringup/piolite_p4_scenarios.c").read_text()
    assert "(kind != 1U) ? rs_p4_uart_single(&piolite_p1_uart_rx, 0U)" in scenarios
    assert "if (!s_p4_uart_tx_frame && !s_gpio_0 &&" in testbench
    assert "(u_dut.u_soc.u_piolite.u_ctrl.runtime[0].pc == 2)" in testbench
    assert "s_p4_uart_tx_bit    = -1;" in testbench
    assert "s_p4_uart_tx_frame && (s_p4_uart_tx_sessions != 4)" in testbench
    for session in (5, 6, 7):
        assert f"s_p4_uart_rx_sessions == {session}" in testbench


def test_ir_bfm_frame_end_covers_one_capture_sample_period() -> None:
    testbench = (ROOT / "rtl/tiny/dv/tiny_piolite_p4.svh").read_text()
    assert testbench.count("s_p4_ir_drive_level(1'b1, 2);") == 3
    assert "s_p4_ir_drive_level(1'b1, 1);" not in testbench
    assert "s_p4_ir_rx_sessions == 4" in testbench
    assert "s_p4_ir_rx_sessions == 5" in testbench
    assert "u_dut.u_soc.u_piolite.u_ctrl.cfg[1].entry" in testbench
