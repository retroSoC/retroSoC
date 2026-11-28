#!/usr/bin/env python3
"""Independent source-bound PIOLITE-P4 Tiny acceptance checks."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.flow_control import source_state  # noqa: E402
from scripts.piolite_asm import assemble, emit_c  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

TERMINAL = re.compile(r"SIM_TEST_PASS Tiny cycles=[1-9][0-9]*")
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
PROGRAM_NAMES = (
    "logic_capture",
    "pulse_generate",
    "pulse_capture",
    "uart_tx",
    "uart_rx",
    "spi_master",
    "spi_master_mode1",
    "spi_master_mode2",
    "spi_master_mode3",
    "ir_tx",
    "ir_rx",
    "led_scan",
    "gamepad",
)
LOGIC_FIRMWARE = re.compile(
    r"^PIOLITE_P4_LOGIC pattern=([0-9]+) samples=([0-9]+) words=([0-9]+) "
    r"first=([0-9a-fA-F]{2}) last=([0-9a-fA-F]{2}) fnv=([0-9a-fA-F]{8}) stalls=([0-9]+)$",
    re.MULTILINE,
)
LOGIC_BFM = re.compile(
    r"^PIOLITE_P4_BFM_LOGIC pattern=([0-9]+) samples=([0-9]+) "
    r"first=([0-9a-fA-F]{2}) last=([0-9a-fA-F]{2}) fnv=([0-9a-fA-F]{8}) "
    r"min_period=([0-9]+) max_period=([0-9]+)$",
    re.MULTILINE,
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def check_logic(log: str) -> list[str]:
    problems = []
    firmware = LOGIC_FIRMWARE.findall(log)
    bfm = LOGIC_BFM.findall(log)
    if sorted(int(row[0]) for row in firmware) != [0, 1, 2] or len(firmware) != 3:
        problems.append("missing, duplicate, or malformed firmware logic observations")
    if sorted(int(row[0]) for row in bfm) != [0, 1, 2] or len(bfm) != 3:
        problems.append("missing, duplicate, or malformed BFM logic observations")
    for row in firmware:
        pattern, samples, words, first, last, fnv, stalls = row
        if (int(samples), int(words), int(stalls)) != (32768, 8192, 0):
            problems.append(f"incorrect firmware logic counts for pattern {pattern}")
    for row in bfm:
        pattern, samples, first, last, fnv, minimum, maximum = row
        if (int(samples), int(minimum), int(maximum)) != (32768, 24, 24):
            problems.append(f"incorrect BFM logic counts or cadence for pattern {pattern}")
    firmware_by_pattern = {int(row[0]): row[3:6] for row in firmware}
    bfm_by_pattern = {int(row[0]): row[2:5] for row in bfm}
    for pattern in range(3):
        if firmware_by_pattern.get(pattern) != bfm_by_pattern.get(pattern):
            problems.append(f"firmware/BFM logic digest mismatch for pattern {pattern}")
    return problems


def check_contention(log: str) -> list[str]:
    problems = check_logic(log)
    firmware = re.findall(
        r"^PIOLITE_P4_CONTEND pattern=([0-9]+) bg_done=([0-9]+) heartbeat=([0-9]+) iterations=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_CONTEND pattern=([0-9]+) longest_gap=([0-9]+) "
        r"overlap=([0-9]+) late_overlap=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    if len(firmware) != 3 or sorted(int(row[0]) for row in firmware) != [0, 1, 2]:
        problems.append("missing, duplicate, or malformed firmware contention observations")
    if len(bfm) != 3 or sorted(int(row[0]) for row in bfm) != [0, 1, 2]:
        problems.append("missing, duplicate, or malformed BFM contention observations")
    for pattern, done, heartbeat, iterations in firmware:
        if int(done) != 1 or int(heartbeat) == 0 or int(iterations) < 2:
            problems.append(f"background/CPU progress missing for pattern {pattern}")
    for pattern, gap, overlap, late_overlap in bfm:
        if int(gap) <= 0 or int(overlap) <= 0 or int(late_overlap) <= 0:
            problems.append(f"no measured PIO service contention for pattern {pattern}")
    return problems


def check_pulse(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_PULSE case=([0-9]+) high=([0-9]+) low=([0-9]+) "
        r"capture=([0-9]+) done=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_PULSE case=([0-9]+) high=([0-9]+) low=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    if sorted(int(row[0]) for row in firmware) != list(range(6)) or len(firmware) != 6:
        problems.append("missing, duplicate, or malformed firmware pulse observations")
    if sorted(int(row[0]) for row in bfm) != list(range(6)) or len(bfm) != 6:
        problems.append("missing, duplicate, or malformed BFM pulse observations")
    if log.count("PIOLITE_P4_PULSE_ABORT complete=1") != 1:
        problems.append("missing or duplicate firmware pulse abort")
    if log.count("PIOLITE_P4_BFM_PULSE_ABORT complete=1") != 1:
        problems.append("missing or duplicate BFM pulse abort")
    bfm_by_case = {int(row[0]): (int(row[1]), int(row[2])) for row in bfm}
    for case, high, low, capture, done in firmware:
        index = int(case)
        programmed_high = max(2, int(high))
        programmed_low = max(2, int(low))
        if bfm_by_case.get(index) != (programmed_high, programmed_low):
            problems.append(f"pulse wire width mismatch for case {index}")
        if abs(int(capture) - programmed_high) > 2 or int(done) != 1:
            problems.append(f"pulse capture quantization/completion mismatch for case {index}")
    return problems


def check_spi(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_SPI mode=([0-9]+) width=([0-9]+) tx=([0-9a-fA-F]{8}) "
        r"rx=([0-9a-fA-F]{8}) rate=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_SPI mode=([0-9]+) width=([0-9]+) tx=([0-9a-fA-F]{8}) "
        r"rx=([0-9a-fA-F]{8}) rate=([0-9]+) setup=([0-9]+) hold=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    expected_cases = [(mode, width) for mode in range(4) for width in (8, 16, 32)]
    if [(int(row[0]), int(row[1])) for row in firmware] != expected_cases:
        problems.append("missing, duplicate, reordered, or malformed firmware SPI cases")
    if [(int(row[0]), int(row[1])) for row in bfm] != expected_cases:
        problems.append("missing, duplicate, reordered, or malformed BFM SPI cases")
    if log.count("PIOLITE_P4_SPI_STARVATION safe=1") != 1:
        problems.append("missing or duplicate firmware SPI starvation")
    if log.count("PIOLITE_P4_BFM_SPI_STARVATION safe=1") != 1:
        problems.append("missing or duplicate BFM SPI starvation")
    for index, (mode, width) in enumerate(expected_cases):
        mask = 0xFFFFFFFF if width == 32 else (1 << width) - 1
        expected_tx = (0xA5C33C96 ^ (mode * 0x00102040) ^ (width << 1)) & mask
        expected_rx = (0x5A3CC35A ^ (mode * 0x01020408) ^ width) & mask
        if index >= len(firmware) or index >= len(bfm):
            continue
        fw = firmware[index]
        wire = bfm[index]
        fw_values = (int(fw[2], 16), int(fw[3], 16), int(fw[4]))
        wire_values = (int(wire[2], 16), int(wire[3], 16), int(wire[4]))
        if fw_values != (expected_tx, expected_rx, 1000000):
            problems.append(f"firmware SPI data/rate mismatch for mode {mode} width {width}")
        if wire_values != fw_values:
            problems.append(f"BFM/firmware SPI mismatch for mode {mode} width {width}")
        if int(wire[5]) <= 0 or int(wire[6]) <= 0:
            problems.append(f"invalid SPI CS setup/hold for mode {mode} width {width}")
    return problems


def check_uart(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_UART case=([0-9]+) phase=([0-9]+) bytes=([0-9]+) "
        r"baud=([0-9]+) error_ppm=([0-9]+) fnv=([0-9a-fA-F]{8})$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_UART case=([0-9]+) phase=([0-9]+) bytes=([0-9]+) "
        r"baud=([0-9]+) error_ppm=([0-9]+) fnv=([0-9a-fA-F]{8})$",
        log,
        re.MULTILINE,
    )
    if len(firmware) != 4 or sorted(int(row[0]) for row in firmware) != [0, 1, 2, 3]:
        problems.append("missing, duplicate, or malformed firmware UART cases")
    if len(bfm) != 4 or sorted(int(row[0]) for row in bfm) != [0, 1, 2, 3]:
        problems.append("missing, duplicate, or malformed BFM UART cases")
    bfm_by_case = {int(row[0]): row for row in bfm}
    for case, phase, count, baud, error_ppm, fnv in firmware:
        index = int(case)
        phase_value = int(phase)
        if phase_value not in (0, 3, 7, 13):
            problems.append(f"unexpected UART phase for case {index}")
        if (int(count), int(baud), int(error_ppm)) != (16, 115384, 1603):
            problems.append(f"incorrect UART count/baud/error for case {index}")
        hash_value = 2166136261
        for byte_index in range(16):
            if byte_index < 4:
                value = (0x00, 0xFF, 0xA5, 0x5A)[byte_index] ^ phase_value
            else:
                value = ((byte_index * 73) + (phase_value * 29) + ((byte_index >> 2) * 11)) & 0xFF
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
        if int(fnv, 16) != hash_value:
            problems.append(f"incorrect firmware UART digest for case {index}")
        peer = bfm_by_case.get(index)
        if peer is None or peer[1:] != (phase, count, baud, error_ppm, fnv):
            problems.append(f"BFM/firmware UART mismatch for case {index}")
    for name in ("RX_STARVATION", "BREAK", "FRAMING", "TX_STARVATION"):
        if log.count(f"PIOLITE_P4_UART_{name} detected=1") != 1:
            problems.append(f"missing or duplicate firmware UART {name}")
        if log.count(f"PIOLITE_P4_BFM_UART_{name} detected=1") != 1:
            problems.append(f"missing or duplicate BFM UART {name}")
    recovery_pattern = (
        r"phase=0 bytes=16 baud=115384 error_ppm=1603 fnv=([0-9a-fA-F]{8})"
    )
    firmware_recovery = re.findall(r"^PIOLITE_P4_UART_RECOVERY " + recovery_pattern + "$", log,
                                   re.MULTILINE)
    bfm_recovery = re.findall(r"^PIOLITE_P4_BFM_UART_RECOVERY " + recovery_pattern + "$", log,
                              re.MULTILINE)
    expected_recovery = firmware[0][5] if firmware else None
    if len(firmware_recovery) != 1 or firmware_recovery[0] != expected_recovery:
        problems.append("missing or incorrect firmware UART recovery")
    if len(bfm_recovery) != 1 or bfm_recovery[0] != expected_recovery:
        problems.append("missing or incorrect BFM UART recovery")
    return problems


def check_ir(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_IR case=([0-9]+) mark=([0-9]+) space=([0-9]+) "
        r"high=([0-9]+) low=([0-9]+) rate=([0-9]+) error_ppm=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_IR case=([0-9]+) mark=([0-9]+) space=([0-9]+) "
        r"high=([0-9]+) low=([0-9]+) rate=([0-9]+) error_ppm=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    if len(firmware) != 3 or sorted(int(row[0]) for row in firmware) != [0, 1, 2]:
        problems.append("missing, duplicate, or malformed firmware IR cases")
    if len(bfm) != 3 or sorted(int(row[0]) for row in bfm) != [0, 1, 2]:
        problems.append("missing, duplicate, or malformed BFM IR cases")
    bfm_by_case = {int(row[0]): row for row in bfm}
    expected = (((3, 4), (5, 7)), ((10, 2), (13, 9)), ((1, 1), (1, 11)))
    for row in firmware:
        case, mark, space, high, low, rate, error_ppm = row
        index = int(case)
        tx_expected, rx_expected = expected[index]
        if (max(1, int(mark)), max(1, int(space))) != tx_expected:
            problems.append(f"unexpected firmware IR pattern for case {index}")
        if (int(rate), int(error_ppm)) != (37915, 2245):
            problems.append(f"incorrect firmware IR rate for case {index}")
        if abs(int(high) - rx_expected[0]) > 2 or abs(int(low) - rx_expected[1]) > 2:
            problems.append(f"IR capture quantization mismatch for case {index}")
        peer = bfm_by_case.get(index)
        if peer is None:
            problems.append(f"missing BFM IR peer for case {index}")
            continue
        if (max(1, int(peer[1])), max(1, int(peer[2]))) != tx_expected:
            problems.append(f"BFM IR mark/space mismatch for case {index}")
        if peer[3:5] != row[3:5] or peer[6] != row[6]:
            problems.append(f"BFM/firmware IR mismatch for case {index}")
        if int(peer[5]) != (0 if index == 2 else int(row[5])):
            problems.append(f"incorrect measured IR carrier rate for case {index}")
    for name in ("TIMEOUT", "OVERFLOW"):
        if log.count(f"PIOLITE_P4_IR_{name} detected=1") != 1:
            problems.append(f"missing or duplicate firmware IR {name}")
        if log.count(f"PIOLITE_P4_BFM_IR_{name} detected=1") != 1:
            problems.append(f"missing or duplicate BFM IR {name}")
    recovery = (
        r"mark=3 space=4 high=([0-9]+) low=([0-9]+) rate=37915 error_ppm=2245"
    )
    firmware_recovery = re.findall(r"^PIOLITE_P4_IR_RECOVERY " + recovery + "$", log,
                                   re.MULTILINE)
    bfm_recovery = re.findall(r"^PIOLITE_P4_BFM_IR_RECOVERY mark=3 space=4 high=5 low=7 "
                              r"rate=37915 error_ppm=2245$", log, re.MULTILINE)
    if len(firmware_recovery) != 1:
        problems.append("missing or duplicate firmware IR recovery")
    else:
        high, low = firmware_recovery[0]
        if abs(int(high) - 5) > 2 or abs(int(low) - 7) > 2:
            problems.append("incorrect firmware IR recovery pulse widths")
    if len(bfm_recovery) != 1:
        problems.append("missing or duplicate BFM IR recovery")
    return problems


def check_led(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_LED frames=([0-9]+) rows=([0-9]+) fps=([0-9]+) "
        r"blank=([0-9]+) fnv=([0-9a-fA-F]{8})$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_LED frames=([0-9]+) rows=([0-9]+) fps=([0-9]+) "
        r"blank=([0-9]+) fnv=([0-9a-fA-F]{8})$",
        log,
        re.MULTILINE,
    )
    hash_value = 2166136261
    for index in range(16):
        row = index & 7
        frame = index >> 3
        columns = 0x81 ^ (row * 0x11) ^ frame
        word = (columns << 8) | (1 << row)
        for value in (word & 0xFF, (word >> 8) & 0xFF):
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
    for name, rows in (("firmware", firmware), ("BFM", bfm)):
        if len(rows) != 1:
            problems.append(f"missing or duplicate {name} LED result")
            continue
        frames, row_count, fps, blank, fnv = rows[0]
        if (int(frames), int(row_count), int(fps), int(blank)) != (2, 16, 389, 1):
            problems.append(f"incorrect {name} LED frames/rate/blanking")
        if int(fnv, 16) != hash_value:
            problems.append(f"incorrect {name} LED row digest")
    if log.count("PIOLITE_P4_LED_ABORT blank=1") != 1:
        problems.append("missing or duplicate firmware LED abort")
    if log.count("PIOLITE_P4_BFM_LED_ABORT blank=1") != 1:
        problems.append("missing or duplicate BFM LED abort")
    return problems


def check_gamepad(log: str) -> list[str]:
    problems = []
    firmware = re.findall(
        r"^PIOLITE_P4_GAMEPAD session=([0-9]+) scans=([0-9]+) "
        r"fnv=([0-9a-fA-F]{8}) disconnected=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    bfm = re.findall(
        r"^PIOLITE_P4_BFM_GAMEPAD session=([0-9]+) scans=([0-9]+) "
        r"fnv=([0-9a-fA-F]{8}) disconnected=([0-9]+)$",
        log,
        re.MULTILINE,
    )
    if len(firmware) != 4 or [int(row[0]) for row in firmware] != [0, 1, 2, 3]:
        problems.append("missing, duplicate, reordered, or malformed firmware gamepad sessions")
    if len(bfm) != 4 or [int(row[0]) for row in bfm] != [0, 1, 2, 3]:
        problems.append("missing, duplicate, reordered, or malformed BFM gamepad sessions")
    patterns = (
        [0xA5] * 4,
        [0x00, 0xFF, 0x5A, 0xC3],
        [0x00, 0xFF],
        [0x69] * 4,
    )
    for index, values in enumerate(patterns):
        hash_value = 2166136261
        for value in values:
            hash_value = ((hash_value ^ value) * 16777619) & 0xFFFFFFFF
        expected = (len(values), hash_value, int(index == 2))
        if index >= len(firmware) or index >= len(bfm):
            continue
        for name, rows in (("firmware", firmware), ("BFM", bfm)):
            row = rows[index]
            actual = (int(row[1]), int(row[2], 16), int(row[3]))
            if actual != expected:
                problems.append(f"incorrect {name} gamepad session {index}")
    return problems


def check_log(log: str, scenario: str) -> list[str]:
    problems = []
    failure = DEFAULT_FAILURE.search(log)
    if failure:
        problems.append(f"forbidden marker: {failure.group(0)}")
    terminal = re.findall(r"^SIM_TEST_PASS Tiny.*$", log, re.MULTILINE)
    if len(terminal) != 1 or TERMINAL.fullmatch(terminal[0]) is None:
        problems.append("missing, malformed, or duplicate Tiny terminal verdict")
    result = re.findall(r"^PIOLITE_P4_RESULT scenario=([A-Z_]+) code=([0-9]+)$", log, re.MULTILINE)
    if result != [(scenario, "0")]:
        problems.append("missing, duplicate, or failing P4 scenario result")
    if scenario == "LOGIC_CAPTURE":
        problems.extend(check_logic(log))
    elif scenario == "CONTENTION":
        problems.extend(check_contention(log))
    elif scenario == "PULSE":
        problems.extend(check_pulse(log))
    elif scenario == "SPI":
        problems.extend(check_spi(log))
    elif scenario == "UART":
        problems.extend(check_uart(log))
    elif scenario == "IR":
        problems.extend(check_ir(log))
    elif scenario == "LED":
        problems.extend(check_led(log))
    elif scenario == "GAMEPAD":
        problems.extend(check_gamepad(log))
    elif scenario in SCENARIOS:
        problems.append(f"scenario {scenario} has no implemented observation checker")
    else:
        problems.append("unknown P4 scenario")
    return problems


def program_evidence(variant: Path) -> tuple[list[dict], list[str]]:
    records = []
    problems = []
    generated = variant / "generated/piolite"
    actual_names = sorted(path.stem for path in generated.glob("*.c")) if generated.is_dir() else []
    if actual_names != sorted(PROGRAM_NAMES):
        problems.append("generated PIO program inventory is incomplete or unexpected")
    for name in PROGRAM_NAMES:
        source = ROOT / "app/asm/piolite" / f"{name}.piolite"
        output = generated / f"{name}.c"
        try:
            source_text = source.read_text(encoding="utf-8")
            generated_text = output.read_text(encoding="utf-8")
        except OSError:
            problems.append(f"missing program source or object: {name}")
            continue
        program = assemble(source_text)
        if emit_c(program) != generated_text:
            problems.append(f"generated object is not source-bound: {name}")
        if len(program.instructions) > 32:
            problems.append(f"program exceeds IMEM capacity: {name}")
        records.append({
            "name": name,
            "source_sha256": file_sha256(source),
            "object_sha256": file_sha256(output),
            "word_count": len(program.instructions),
        })
    return records, problems


def evaluate(variant: Path, pdk: str, simulator_name: str, log_path: Path) -> dict:
    manifest_path = variant / "meta/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    configuration = manifest["configuration"]
    scenario = configuration.get("TINY_PIOLITE_P4_SCENARIO")
    if (configuration["SOC"] != "TINY" or configuration["PDK"] != pdk or
            configuration.get("APP") != "bringup" or
            configuration.get("TINY_PIOLITE_P4_ACCEPTANCE") != "YES" or
            configuration["SIMU"] != simulator_name.upper() or scenario not in SCENARIOS):
        raise ValueError("not a matching Tiny PIOLITE-P4 build variant")
    log_text = log_path.read_text(errors="replace")
    problems = check_log(log_text, scenario)
    verdict_path = log_path.parent / "result-sim-check.json"
    verdict = json.loads(verdict_path.read_text())
    if verdict.get("status") != "passed":
        problems.append("structured simulation verdict did not pass")
    if verdict.get("log") != str(log_path):
        problems.append("structured verdict log identity differs from the checked log")
    flow_path = log_path.parent / "result-sim.json"
    flow = json.loads(flow_path.read_text())
    if flow.get("status") != "passed" or flow.get("exit_code") != 0:
        problems.append("terminal run_flow result did not pass")
    if flow.get("log") != str(log_path):
        problems.append("run_flow log identity differs from the checked log")
    firmware = variant / "sw/retrosoc_fw.hex"
    simulator = variant / "sim" / simulator_name / ("emu" if simulator_name == "verilator" else "simv")
    command = flow.get("command", [])
    if str(simulator) not in command:
        problems.append("simulation did not execute the variant emulator")
    if f"+firmware={firmware}" not in command:
        problems.append("simulation did not use the variant firmware image")
    if "+piolite_p4_loopback" not in command:
        problems.append("simulation did not isolate native external drivers")
    if f"+piolite_p4_scenario_{scenario}" not in command:
        problems.append("simulation scenario does not match the build variant")

    repository = manifest.get("repository", {})
    current = source_state(ROOT)
    if (flow.get("source_revision") != repository.get("commit") or
            current["source_revision"] != repository.get("commit")):
        problems.append("flow, manifest, and current source revisions differ")
    if (flow.get("source_dirty") is not repository.get("dirty") or
            current["source_dirty"] is not repository.get("dirty")):
        problems.append("flow, manifest, and current dirty states differ")
    flow_source = flow.get("source_state_sha256")
    if not isinstance(flow_source, str) or re.fullmatch(r"[0-9a-f]{64}", flow_source) is None:
        problems.append("missing or malformed execution source-state hash")
    elif flow_source != current["source_state_sha256"]:
        problems.append("current source state differs from the executed image")
    lock_hash = manifest.get("dependency_lock", {}).get("sha256")
    if (flow.get("tool_lock_sha256") != lock_hash or current["tool_lock_sha256"] != lock_hash):
        problems.append("flow, manifest, and current dependency locks differ")
    if flow.get("configuration") != {"pdk": pdk, "soc": "TINY", "profile": manifest.get("profile")}:
        problems.append("simulation profile/PDK identity is missing or incorrect")
    inputs = flow.get("input_sha256")
    expected_inputs = {str(firmware): file_sha256(firmware), str(simulator): file_sha256(simulator)}
    if inputs != expected_inputs:
        problems.append("firmware/emulator execution input hashes are missing or changed")
    programs, program_problems = program_evidence(variant)
    problems.extend(program_problems)

    return {
        "phase": "PIOLITE-P4",
        "stage": "check",
        "scenario": scenario,
        "status": "passed" if not problems else "failed",
        "problems": problems,
        "simulator": simulator_name,
        "configuration_digest": configuration_digest(manifest),
        "manifest_sha256": file_sha256(manifest_path),
        "firmware_sha256": expected_inputs[str(firmware)],
        "simulator_sha256": expected_inputs[str(simulator)],
        "log_sha256": file_sha256(log_path),
        "flow_result_sha256": file_sha256(flow_path),
        "source_revision": repository.get("commit"),
        "source_dirty": repository.get("dirty"),
        "source_state_sha256": flow_source,
        "input_sha256": expected_inputs,
        "programs": programs,
        "phase_accepted": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("check",))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--simulator", choices=("verilator",), required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    log_path = args.log.resolve()
    log_path.relative_to(variant)
    try:
        record = evaluate(variant, args.pdk, args.simulator, log_path)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"PIOLITE-P4 check: {error}", file=sys.stderr)
        return 2
    output = variant / "meta/piolite-p4" / args.stage
    output.mkdir(parents=True, exist_ok=True)
    atomic_write(output / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    for problem in record["problems"]:
        print(problem, file=sys.stderr)
    return int(record["status"] != "passed")


if __name__ == "__main__":
    raise SystemExit(main())
