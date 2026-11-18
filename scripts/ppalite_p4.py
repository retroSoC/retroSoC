#!/usr/bin/env python3
"""Independent PPALITE-P4 capture, SD, display, and source-bound log checks."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ppalite_model import Config, layout, render  # noqa: E402

FORBIDDEN = ("FAILED", "FATAL", "assertion failed", "%Error", "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT",
             "SPI_P4_VIOLATION", "PPALITE_P4_PIXEL_MISMATCH")
CASES = {
    1: (5, 3, 2, 1, 2, 2, 0, 0, True, False, 3, 2, 3, 4, 6, 8),
    3: (5, 3, 2, 1, 2, 2, 0, 0, True, False, 3, 2, 3, 4, 6, 8),
    4: (320, 240, 0, 0, 2, 2, 0, 0, True, False, 160, 120, 160, 160, 19200, 19200),
    5: (320, 240, 0, 0, 2, 2, 0, 0, False, False, 160, 120, 320, 320, 38400, 38400),
    6: (319, 239, 1, 0, 2, 2, 1, 0, False, True, 159, 120, 318, 320, 38160, 38400),
    10: (320, 240, 0, 0, 1, 1, 0, 0, True, False, 320, 240, 320, 320, 76800, 76800),
    11: (319, 239, 1, 0, 2, 2, 1, 0, True, False, 159, 120, 159, 160, 19080, 19200),
}
MEASURE_BYTES = {1: 8, 2: 0, 3: 8, 4: 19200, 5: 38400, 6: 38400, 7: 19200, 8: 38400,
                 9: 38160, 10: 76800, 11: 19200, 12: 19080, 13: 153600}
DMA_WINDOWS = {
    1: {"write": 8},
    3: {"write": 8},
    4: {"write": 19200},
    6: {"write": 38400},
    7: {"read": 38400, "write": 38400},
    8: {"write": 38400},
    9: {"read": 38400, "write": 38400},
    10: {"write": 76800},
    11: {"write": 19200},
    13: {"write": 153600},
}
DMA_IDLE_WINDOWS = (5, 12)
DMA_SINGLE_BEAT_WINDOWS = (7, 9)


def records(log: str, prefix: str) -> list[dict[str, str]]:
    result = []
    marker = prefix + " "
    for line in log.splitlines():
        if line.startswith(marker):
            result.append(dict(field.split("=", 1) for field in line[len(marker):].split()))
    return result


def number(fields: dict[str, str], name: str) -> int:
    return int(fields[name], 0)


def model(case_id: int) -> tuple[Config, bytes, dict[str, int]]:
    width, height, crop_x, crop_y, step_x, step_y, phase_x, phase_y, gray8, swapped, _, _, _, _, _, _ = CASES[case_id]
    sensor = bytearray()
    for y in range(height):
        source_y = crop_y + y
        for x in range(width):
            source_x = crop_x + x
            index = 2 * source_x
            sensor.extend(((index + 3 * source_y) & 0xFF, (index + 1 + 3 * source_y) & 0xFF))
    config = Config(width, height, input_format=2, gray8=gray8, output_byte_swap=swapped,
                    step_x=step_x, step_y=step_y, phase_x=phase_x, phase_y=phase_y)
    rendered, _ = render(config, bytes(sensor))
    shape = layout(config)
    return config, rendered, shape


def wire_pixels(case_id: int) -> bytes:
    _, rendered, shape = model(case_id)
    swapped = CASES[case_id][9]
    output = bytearray()
    for row_start in range(0, len(rendered), shape["stride_bytes"]):
        row = rendered[row_start:row_start + shape["row_bytes"]]
        for column in range(0, len(row), 2):
            if swapped:
                output.extend(row[column:column + 2])
            else:
                output.extend(row[column:column + 2][::-1])
    return bytes(output)


def fnv1a(data: bytes, value: int = 2166136261) -> int:
    for byte in data:
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def check_capture(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_CAPTURE")
    if [number(row, "id") for row in rows] != [1, 3, 4, 5, 6, 10, 11]:
        problems.append("capture IDs are missing, duplicated, or reordered")
        return
    previous_job = 0
    previous_source = 0
    for row in rows:
        case_id = number(row, "id")
        *_, width, height, row_bytes, stride, valid, transport = CASES[case_id]
        expected = {"pass": 1, "width": width, "height": height, "row": row_bytes,
                    "stride": stride, "valid": valid, "transport": transport}
        for name, value in expected.items():
            if number(row, name) != value:
                problems.append(f"capture {case_id}: {name} mismatch")
        job = number(row, "job")
        source = number(row, "source")
        if job <= previous_job or source <= previous_source:
            problems.append(f"capture {case_id}: stale job/source sequence")
        previous_job = job
        previous_source = source


def check_recovery(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_RECOVERY")
    if len(rows) != 1:
        problems.append("missing or duplicate recovery record")
        return
    expected = {"pass": 1, "wait": -4, "abort": 0, "stopped": -4, "resumed": 0, "owned": 1,
                "valid": 0}
    for name, value in expected.items():
        if number(rows[0], name) != value:
            problems.append(f"recovery {name} mismatch")


def check_sd(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_SD")
    if [number(row, "id") for row in rows] != [7, 12]:
        problems.append("SD records are missing, duplicated, or reordered")
        return
    expected = {
        7: {"pass": 1, "first_lba": 16, "last_lba": 53, "blocks": 38, "bytes": 19200, "row": 160,
            "stride": 160, "stripped": 0, "readback": 1},
        12: {"pass": 1, "first_lba": 16, "last_lba": 53, "blocks": 38, "bytes": 19080, "row": 159,
             "stride": 160, "stripped": 1, "readback": 1},
    }
    for row in rows:
        case_id = number(row, "id")
        for name, value in expected[case_id].items():
            if number(row, name) != value:
                problems.append(f"SD {case_id}: {name} mismatch")


def check_display(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_DISPLAY")
    if [number(row, "id") for row in rows] != [8, 9]:
        problems.append("display records are missing, duplicated, or reordered")
        return
    expected = {
        8: {"pass": 1, "pixels": 19200, "payload": 38400, "transport": 9600, "chunks": 120,
            "frame16": 1},
        9: {"pass": 1, "pixels": 19080, "payload": 38160, "transport": 9600, "chunks": 120,
            "frame16": 0},
    }
    for row in rows:
        case_id = number(row, "id")
        for name, value in expected[case_id].items():
            if number(row, name) != value:
                problems.append(f"display {case_id}: {name} mismatch")


def check_measurements(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_MEASURE")
    if [number(row, "id") for row in rows] != [1, 2, 3, 4, 7, 5, 8, 6, 9, 10, 11, 12, 13]:
        problems.append("measurement IDs are missing, duplicated, or reordered")
        return
    for row in rows:
        case_id = number(row, "id")
        if number(row, "bytes") != MEASURE_BYTES[case_id]:
            problems.append(f"measurement {case_id}: byte count mismatch")
        cycles = number(row, "cycles")
        instructions = number(row, "instructions")
        if cycles <= 0 or instructions <= 0 or instructions > cycles:
            problems.append(f"measurement {case_id}: invalid cycle/instruction accounting")


def check_core(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_CORE")
    if [number(row, "id") for row in rows] != [1, 3, 4, 5, 6, 10, 11]:
        problems.append("core measurement IDs are missing, duplicated, or reordered")
        return
    for row in rows:
        case_id = number(row, "id")
        width, height, _, _, _, _, _, _, _, _, _, output_lines, _, _, _, transport = CASES[case_id]
        expected = {
            "input_words": ((width + 1) // 2) * height,
            "input_pixels": width * height,
            "input_lines": height,
            "output_words": transport // 4,
            "output_lines": output_lines,
        }
        for name, value in expected.items():
            if number(row, name) != value:
                problems.append(f"core {case_id}: {name} mismatch")
        if number(row, "high_water") < 0 or number(row, "high_water") > 8:
            problems.append(f"core {case_id}: impossible FIFO high-water")
        if number(row, "input_stall") < 0 or number(row, "output_stall") < 0:
            problems.append(f"core {case_id}: invalid stall counter")


def check_timing(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_TIMING")
    if [number(row, "id") for row in rows] != [1, 3, 4, 5, 6, 10, 11]:
        problems.append("capture timing IDs are missing, duplicated, or reordered")
        return
    totals = {number(row, "id"): number(row, "cycles") for row in records(log, "PPALITE_P4_MEASURE")}
    for row in rows:
        case_id = number(row, "id")
        if number(row, "rows") != CASES[case_id][11]:
            problems.append(f"capture timing {case_id}: row count mismatch")
        for name in ("arm", "start", "wait"):
            if number(row, name) <= 0:
                problems.append(f"capture timing {case_id}: missing {name} overhead")
        if case_id not in totals:
            problems.append(f"capture timing {case_id}: missing total measurement")
        elif number(row, "arm") + number(row, "start") + number(row, "wait") > totals[case_id]:
            problems.append(f"capture timing {case_id}: phases exceed total cycles")


def check_raw(log: str, problems: list[str]) -> None:
    rows = records(log, "PPALITE_P4_RAW")
    if len(rows) != 1:
        problems.append("missing or duplicate RAW reference")
        return
    expected = {"pass": 1, "pixels": 76800, "bytes": 153600, "words": 38400,
                "dma_bytes": 153600}
    for name, value in expected.items():
        if number(rows[0], name) != value:
            problems.append(f"RAW reference {name} mismatch")


def check_panel(log: str, problems: list[str]) -> None:
    windows = []
    summary = None
    for line in log.splitlines():
        if line.startswith("SPI_P4_WINDOW "):
            windows.append(dict(re.findall(r"(\w+)=([0-9a-f]+)", line)))
        elif line.startswith("SPI_P4_PANEL "):
            summary = dict(re.findall(r"(\w+)=([0-9a-f]+)", line))
    if len(windows) != 2:
        problems.append("expected two completed panel windows")
        return
    aggregate = 2166136261
    total_pixels = 0
    for index, (case_id, geometry) in enumerate(((5, (0, 0, 159, 119)), (6, (0, 0, 158, 119)))):
        fields = windows[index]
        if int(fields["seq"], 16) != index + 1:
            problems.append(f"panel window {index + 1}: sequence mismatch")
        got = tuple(int(fields[name], 16) for name in ("x0", "y0", "x1", "y1"))
        if got != geometry:
            problems.append(f"panel window {index + 1}: geometry mismatch")
        pixels = wire_pixels(case_id)
        if int(fields["pixels"], 16) != len(pixels) // 2 or int(fields["aborted"], 16) != 0:
            problems.append(f"panel window {index + 1}: pixel count/abort mismatch")
        if int(fields["fnv1a"], 16) != fnv1a(pixels):
            problems.append(f"panel window {index + 1}: pixel checksum mismatch")
        aggregate = fnv1a(pixels, aggregate)
        total_pixels += len(pixels) // 2
    if summary is None:
        problems.append("missing panel summary")
        return
    if int(summary["windows"], 16) != 2 or int(summary["pixels"], 16) != total_pixels:
        problems.append("panel summary window/pixel count mismatch")
    if int(summary["fnv1a"], 16) != aggregate or int(summary["violations"], 16) != 0:
        problems.append("panel summary checksum/violation mismatch")


def check_observers(log: str, problems: list[str]) -> None:
    p9 = records(log, "P9_OBSERVATION")
    if len(p9) != 1:
        problems.append("missing or duplicate raw-camera observation")
        return
    try:
        accepted = number(p9[0], "accepted_words")
        delivered = number(p9[0], "delivered_words")
        expected_words = sum(((case[0] + 1) // 2) * case[1] for case in CASES.values()) + 38400
        if accepted != expected_words or delivered != expected_words:
            problems.append("raw-camera accepted/delivered word conservation mismatch")
        if number(p9[0], "version") != 1 or number(p9[0], "pixel_half_ns") != 500:
            problems.append("raw-camera observation identity mismatch")
        high_water = number(p9[0], "fifo_high_water")
        backpressure = number(p9[0], "backpressure")
        if high_water <= 0 or high_water > 124 or backpressure < 0:
            problems.append("invalid raw-camera FIFO/stall observation")
        else:
            no_service_budget_us = 496 - (4 * high_water)
            if backpressure / 24 >= no_service_budget_us:
                problems.append("raw-camera backpressure exceeds the no-service FIFO budget")
    except (KeyError, ValueError) as error:
        problems.append(f"malformed raw-camera observation: {error}")
    bus = records(log, "P10_BUS")
    if not bus:
        problems.append("missing AXI measurement observations")
        return
    expected = DMA_WINDOWS
    matched = set()
    observed = []
    try:
        for row in bus:
            if number(row, "errors") != 0:
                problems.append("AXI measurement contains a response error")
            for direction in ("read", "write"):
                initial = number(row, direction + "_initial")
                pending = number(row, direction + "_pending")
                if number(row, direction + "s") + initial != number(row, direction + "_done") + pending:
                    problems.append("AXI measurement transaction conservation mismatch")
            window = number(row, "window")
            owner = number(row, "owner")
            if owner == 1:
                observed.append(window)
            if owner == 1 and window in DMA_IDLE_WINDOWS:
                for direction in ("read", "write"):
                    if any(number(row, direction + suffix) != 0
                           for suffix in ("s", "_done", "_initial", "_pending", "_bytes")):
                        problems.append(f"SD window {window}: unexpected central DMA {direction} traffic")
            if owner == 1 and window in expected:
                if window in matched:
                    problems.append(f"duplicate DMA measurement for window {window}")
                matched.add(window)
                for direction in ("read", "write"):
                    if number(row, direction + "_initial") != 0 or number(row, direction + "_pending") != 0:
                        problems.append(f"DMA window {window}: outstanding {direction} work")
                    accepted = number(row, direction + "s")
                    completed = number(row, direction + "_done")
                    if accepted != completed:
                        problems.append(f"DMA window {window}: owner is not drained")
                    expected_bytes = expected[window].get(direction, 0)
                    if expected_bytes == 0:
                        if accepted != 0 or number(row, direction + "_bytes") != 0:
                            problems.append(f"DMA window {window}: unexpected {direction} traffic")
                        continue
                    if window in DMA_SINGLE_BEAT_WINDOWS:
                        minimum = expected_bytes // 4
                        maximum = minimum
                    else:
                        minimum = (expected_bytes + 63) // 64
                        maximum = expected_bytes // 4
                    if accepted < minimum or accepted > maximum:
                        problems.append(f"DMA window {window}: impossible {direction} transaction count")
                    if number(row, direction + "_bytes") != expected_bytes:
                        problems.append(f"DMA window {window}: {direction} byte count mismatch")
                    if number(row, direction + "_latency_max") <= 0:
                        problems.append(f"DMA window {window}: missing {direction} latency evidence")
        if observed != list(range(1, 14)):
            problems.append("central DMA window sequence is incomplete, duplicated, or reordered")
        if matched != set(expected):
            problems.append("missing DMA window byte/latency evidence")
    except (KeyError, ValueError) as error:
        problems.append(f"malformed AXI observation: {error}")


def check_log(log: str) -> list[str]:
    problems = []
    for marker in FORBIDDEN:
        if marker in log:
            problems.append(f"forbidden marker: {marker}")
    terminal = re.findall(r"^SIM_TEST_PASS Tiny.*$", log, re.MULTILINE)
    if (len(terminal) != 1 or
            re.fullmatch(r"SIM_TEST_PASS Tiny cycles=[1-9][0-9]*", terminal[0]) is None):
        problems.append("missing, malformed, or duplicate Tiny terminal verdict")
    for check in (check_capture, check_recovery, check_sd, check_display, check_measurements,
                  check_core, check_timing, check_raw, check_panel, check_observers):
        try:
            check(log, problems)
        except (KeyError, ValueError) as error:
            problems.append(f"malformed record: {error}")
    result = records(log, "PPALITE_P4_RESULT")
    if len(result) != 1:
        problems.append("missing or duplicate P4 result")
    else:
        for name, expected in (("code", 0), ("frames", 7), ("recovered", 1)):
            try:
                if number(result[0], name) != expected:
                    problems.append(f"P4 result {name} mismatch")
            except (KeyError, ValueError) as error:
                problems.append(f"malformed P4 result: {error}")
    return problems


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("check",))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--simulator", choices=("verilator", "iverilog"), required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    log_path = args.log.resolve()
    log_path.relative_to(variant)
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    configuration = manifest["configuration"]
    if (configuration["SOC"] != "TINY" or configuration["PDK"] != args.pdk or
            configuration.get("TINY_PPALITE_P4_ACCEPTANCE") != "YES"):
        raise ValueError("not a matching Tiny PPALITE-P4 build variant")
    verdict = json.loads((log_path.parent / "result-sim-check.json").read_text())
    problems = check_log(log_path.read_text(errors="replace"))
    if verdict.get("status") != "passed":
        problems.append("structured simulation verdict did not pass")
    firmware = variant / "sw/retrosoc_fw.hex"
    simulator = variant / "sim" / args.simulator / ("emu" if args.simulator == "verilator" else "simv")
    record = {
        "phase": "PPALITE-P4",
        "stage": args.stage,
        "status": "passed" if not problems else "failed",
        "problems": problems,
        "simulator": args.simulator,
        "configuration_digest": configuration_digest(manifest),
        "firmware_sha256": file_sha256(firmware),
        "simulator_sha256": file_sha256(simulator),
        "log_sha256": file_sha256(log_path),
        "phase_accepted": False,
    }
    output = variant / "meta/ppalite-p4" / args.stage
    output.mkdir(parents=True, exist_ok=True)
    (output / "record.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    for problem in problems:
        print(problem, file=sys.stderr)
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
