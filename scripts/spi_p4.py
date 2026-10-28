#!/usr/bin/env python3
"""Source-bound focused SPI-P4 Tiny display checks and panel-oracle validation."""
from __future__ import annotations

import argparse
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402

STAGE_GEOMETRY = {
    1: (0, 0, 319, 239),
    2: (0, 0, 319, 239),
    3: (13, 17, 45, 29),
    4: (319, 0, 319, 239),
    5: (200, 239, 260, 239),
    6: (5, 7, 45, 29),
    7: (100, 100, 116, 108),
}
BARS = [0xFFFF, 0xFFE0, 0x07FF, 0x07E0, 0xF81F, 0xF800, 0x001F, 0x0000]


def golden_pixel(stage: int, row: int, col: int) -> int:
    if stage == 1:
        return BARS[min(col // 40, 7)]
    if stage in (2, 8):
        red5 = min(col >> 3, 31)
        green6 = min(row >> 2, 63)
        blue5 = min((row + col) >> 4, 31)
        return (red5 << 11) | (green6 << 5) | blue5
    if stage == 3:
        return 0xFFFF if (row + col) & 1 else 0x0000
    if stage == 4:
        return 0x07E0
    if stage == 5:
        return 0xFFE0
    if stage == 6:
        return ((col & 31) << 11) | ((row & 63) << 5) | ((row ^ col) & 31)
    if stage == 7:
        return 0xFFFF
    raise ValueError(f"unknown stage {stage}")


def fnv1a(data: bytes) -> int:
    value = 2166136261
    for byte in data:
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def window_stream(stage: int, x0: int, y0: int, x1: int, y1: int) -> bytes:
    out = bytearray()
    for row in range(y0, y1 + 1):
        for col in range(x0, x1 + 1):
            pixel = golden_pixel(stage, row, col)
            out.append((pixel >> 8) & 0xFF)
            out.append(pixel & 0xFF)
    return bytes(out)


def camera_pixel(row: int, col: int) -> int:
    first = (2 * col + 3 * row) & 0xFF
    return (first << 8) | ((first + 1) & 0xFF)


@lru_cache(maxsize=1)
def camera_stream() -> bytes:
    out = bytearray()
    for row in range(240):
        for col in range(320):
            pixel = camera_pixel(row, col)
            out.append((pixel >> 8) & 0xFF)
            out.append(pixel & 0xFF)
    return bytes(out)


def fnv1a_continue(value: int, data: bytes) -> int:
    for byte in data:
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


P9_TB_PROGRESS_RE = re.compile(
    r"P9_TB_PROGRESS cycle=[0-9]+ cpu_boot=[01] core_rst=[01] boot_release=[01] "
    r"fabric=[01] dma_ready=[01] apb_ready=[01] i_trans=[01] i_ready=[01] "
    r"d_trans=[01] d_ready=[01] slow_req=[0-9]+ slow_state=[0-9]+ "
    r"slow_htrans=[01]+ slow_hready=[01] xpi_ar=[01]/[01] xpi_r=[01]/[01](?:\n|$)"
)


def reassemble_progress(log: str, problems: list[str]) -> str:
    matches = list(P9_TB_PROGRESS_RE.finditer(log))
    if log.count("P9_TB_PROGRESS") != len(matches):
        problems.append("malformed P9_TB_PROGRESS record")
    return P9_TB_PROGRESS_RE.sub("", log)


def records(log: str, prefix: str, problems: list[str] | None = None) -> list[dict[str, str]]:
    result = []
    marker = prefix + " "
    for line in log.splitlines():
        if line.startswith(marker):
            try:
                result.append(dict(field.split("=", 1) for field in line[len(marker):].split()))
            except ValueError:
                if problems is None:
                    raise
                problems.append(f"malformed {prefix} record")
    return result


def record_int(fields: dict[str, str], name: str) -> int:
    return int(fields[name], 0)


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def focused(output: Path, stage: str) -> int:
    output.mkdir(parents=True, exist_ok=False)
    command = [sys.executable, "-m", "pytest", "-q", "tests/test_spi_dma_admit.py",
               "tests/test_spi_p4.py", "tests/test_spi_p3.py",
               "tests/test_spi_register_parity.py"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    atomic_write(output / "pytest.log", result.stdout + result.stderr)
    return result.returncode


def check_b_records(log: str, problems: list[str]) -> None:
    capture = records(log, "SPI_P4_CAPTURE", problems)
    saved = records(log, "SPI_P4_SD", problems)
    measurements = records(log, "SPI_P4_V22", problems)
    stalls = records(log, "SPI_P4_V22_STALL", problems)
    bus = records(log, "P10_BUS", problems)
    concurrency = records(log, "P10_CONCURRENCY", problems)
    p9 = records(log, "P9_OBSERVATION", problems)
    result = records(log, "SPI_P4_RESULT", problems)
    expected_counts = (len(capture) == 1 and len(saved) == 1 and len(measurements) == 2 and
                       len(stalls) == 2 and len(bus) == 6 and len(concurrency) == 2 and
                       len(p9) == 1 and len(result) == 1)
    if not expected_counts:
        problems.append("missing or duplicate B capture/SD/measurement/observer/result records")
        return
    try:
        golden_fnv = fnv1a(camera_stream())
        c = capture[0]
        expected_capture = {"pixels": 76800, "bytes": 153600, "words": 38400,
                            "dma_bytes": 153600, "fnv1a": golden_fnv, "guards": 1,
                            "camera_active": 0, "dma2_busy": 0}
        for name, expected in expected_capture.items():
            if record_int(c, name) != expected:
                problems.append(f"capture {name} mismatch")
        s = saved[0]
        expected_sd = {"first_lba": 16, "last_lba": 315, "blocks": 300, "chunks": 150,
                       "bytes": 153600, "readback": 1, "fnv1a": golden_fnv}
        for name, expected in expected_sd.items():
            if record_int(s, name) != expected:
                problems.append(f"SD {name} mismatch")
        if record_int(result[0], "code") != 0:
            problems.append("firmware result is nonzero")
        observation = p9[0]
        for name, expected in {"version": 1, "accepted_words": 38400,
                               "delivered_words": 38400, "pixel_half_ns": 500}.items():
            if record_int(observation, name) != expected:
                problems.append(f"DVP observation {name} mismatch")
        for index, source in enumerate(("psram", "sram")):
            m = measurements[index]
            stall = stalls[index]
            if m["source"] != source or stall["source"] != source:
                problems.append(f"measurement {index + 1}: source/order mismatch")
                continue
            cycles = record_int(m, "frame_cycles")
            divider = record_int(m, "divider")
            if cycles == 0:
                problems.append(f"measurement {source}: zero frame cycles")
                continue
            expected = {"bus_window": index + 1, "pclk_hz": 24000000, "sck_hz": 12000000,
                        "pixels": 76800, "payload_bytes": 153600, "transport_words": 38400,
                        "chunks": 1 if index == 0 else 150, "cpu_cycles": cycles,
                        "frame_time_ns": cycles * 1000000000 // 24000000,
                        "utilization_ppm": 153600 * 16 * divider * 1000000 // cycles}
            for name, value in expected.items():
                if record_int(m, name) != value:
                    problems.append(f"measurement {source}: {name} mismatch")
            if divider != 1 or cycles == 0 or not (0 < record_int(m, "instructions") <= cycles):
                problems.append(f"measurement {source}: invalid divider/cycle/instruction accounting")
            if record_int(m, "utilization_ppm") > 1000000:
                problems.append(f"measurement {source}: utilization exceeds wire payload")
            if (record_int(stall, "rx_stall") != 0 or
                    record_int(stall, "longest_rx_wait") != 0 or
                    record_int(stall, "fifo_final") != 0 or
                    record_int(stall, "fifo_min") > record_int(stall, "fifo_max") or
                    record_int(stall, "fifo_max") > 8 or
                    record_int(stall, "longest_tx_wait") > record_int(stall, "tx_stall")):
                problems.append(f"measurement {source}: invalid stall/FIFO accounting")
        order = [(record_int(row, "window"), record_int(row, "owner")) for row in bus]
        if order != [(window, owner) for window in (1, 2) for owner in range(3)]:
            problems.append("DMA bus observations are missing or reordered")
        for row in bus:
            for direction in ("read", "write"):
                initial = record_int(row, direction + "_initial")
                pending = record_int(row, direction + "_pending")
                if (record_int(row, direction + "s") + initial !=
                        record_int(row, direction + "_done") + pending):
                    problems.append("DMA bus transaction conservation mismatch")
            if record_int(row, "errors") != 0:
                problems.append("DMA bus error inside display window")
            if record_int(row, "owner") == 1:
                for name in ("read_bytes", "write_bytes", "reads", "read_done", "writes",
                             "write_done"):
                    expected = 153600 if name.endswith("bytes") else 38400
                    if record_int(row, name) != expected:
                        problems.append(f"DMA bus {name} is not exact single-beat payload")
                if (record_int(row, "read_pending") != 0 or record_int(row, "write_pending") != 0 or
                        record_int(row, "read_latency_max") == 0):
                    problems.append("DMA display traffic is pending or lacks latency evidence")
        if [record_int(row, "window") for row in concurrency] != [1, 2]:
            problems.append("missing display concurrency observations")
        if any(record_int(row, "active_targets_max") > 29 for row in concurrency):
            problems.append("display concurrency exceeds Tiny topology")
    except (KeyError, ValueError) as error:
        problems.append(f"malformed B record: {error}")


def check_log(log: str, quick: bool = False, version: str = "auto") -> list[str]:
    if version not in ("auto", "a", "b"):
        raise ValueError("version must be auto, a, or b")
    problems = []
    log = reassemble_progress(log, problems)
    if problems:
        return problems
    if version == "auto":
        version = "b" if "SPI_P4_V22 " in log or "SPI_P4_CAPTURE " in log else "a"
    windows = []
    violations = 0
    panel = None
    commands = 0
    saw_slpout = False
    saw_dispon = False
    for line in log.splitlines():
        if "SPI_P4_VIOLATION" in line:
            violations += 1
        elif "SPI_P4_CMD " in line:
            commands += 1
            fields = dict(re.findall(r"(\w+)=([0-9a-f]+)", line))
            code = int(fields["code"], 16)
            if code == 0x11:
                saw_slpout = True
            if code == 0x29:
                saw_dispon = True
        elif "SPI_P4_WINDOW " in line:
            fields = dict(re.findall(r"(\w+)=([0-9a-f]+)", line))
            windows.append(fields)
        elif "SPI_P4_PANEL " in line:
            panel = dict(re.findall(r"(\w+)=([0-9a-f]+)", line))
    if violations != 0:
        problems.append(f"{violations} panel violations recorded")
    if not saw_slpout or not saw_dispon:
        problems.append("init ordering missing SLPOUT or DISPON")
    full_geometry = (319, 239) if not quick else (39, 23)
    expected = [((0, 0) + full_geometry), ((0, 0) + full_geometry), (13, 17, 45, 29),
                (319, 0, 319, 239), (200, 239, 260, 239), (5, 7, 45, 29),
                ((0, 0) + full_geometry), (100, 100, 116, 108)]
    if version == "b":
        expected += [(0, 0, 319, 239)] * 3
    checksum_stage = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 8: 7}
    if len(windows) != len(expected):
        problems.append(f"expected {len(expected)} windows, saw {len(windows)}")
        return problems
    panel_fnv = 2166136261
    for index, (fields, geometry) in enumerate(zip(windows, expected)):
        seq = index + 1
        if int(fields["seq"], 16) != seq:
            problems.append(f"window {seq}: seq mismatch {fields['seq']}")
        got = tuple(int(fields[name], 16) for name in ("x0", "y0", "x1", "y1"))
        if got != geometry:
            problems.append(f"window {seq}: geometry {got} != {geometry}")
            continue
        pixels = int(fields["pixels"], 16)
        aborted = int(fields["aborted"], 16)
        want_pixels = (geometry[2] - geometry[0] + 1) * (geometry[3] - geometry[1] + 1)
        if seq in (7, 11):
            expected_abort = 544 if seq == 7 else 143
            if aborted != 1:
                problems.append(f"window {seq}: expected abort")
            if pixels != expected_abort:
                problems.append(f"window {seq}: abort pixels {pixels} != {expected_abort}")
        else:
            if aborted != 0:
                problems.append(f"window {seq}: unexpected abort")
            if pixels != want_pixels:
                problems.append(f"window {seq}: pixels {pixels} != {want_pixels}")
                continue
        if pixels > want_pixels:
            problems.append(f"window {seq}: excess pixels")
            continue
        if seq >= 9:
            stream = camera_stream()
        else:
            stage = 4 if seq == 7 else checksum_stage[seq]
            stream = window_stream(stage, *geometry)
        stream = stream[:pixels * 2]
        if int(fields["fnv1a"], 16) != fnv1a(stream):
            problems.append(f"window {seq}: pixel checksum mismatch")
        panel_fnv = fnv1a_continue(panel_fnv, stream)
    if panel is None:
        problems.append("missing SPI_P4_PANEL summary")
    else:
        if int(panel["violations"], 16) != 0:
            problems.append("panel summary reports violations")
        if int(panel["pixels"], 16) != sum(int(w["pixels"], 16) for w in windows):
            problems.append("panel pixel total mismatch")
        if int(panel["windows"], 16) != len(windows):
            problems.append("panel window total mismatch")
        if int(panel["fnv1a"], 16) != panel_fnv:
            problems.append("panel aggregate checksum mismatch")
    if commands < 10:
        problems.append(f"too few commands observed: {commands}")
    if version == "b":
        check_b_records(log, problems)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "report", "check"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--version", choices=("auto", "a", "b"), default="auto")
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["configuration"]["SOC"] != "TINY" or manifest["configuration"]["PDK"] != args.pdk:
        raise ValueError("profile/PDK mismatch")
    output = variant / "meta/spi-p4" / args.stage
    if args.stage == "check":
        if args.log is None or not args.log.is_file():
            raise ValueError("check requires an existing --log sim.log path")
        problems = check_log(args.log.read_text(errors="replace"), quick=args.quick,
                             version=args.version)
        status = "passed" if not problems else "failed"
    else:
        problems = []
        status = "passed" if focused(output, args.stage) == 0 else "failed"
    output.mkdir(parents=True, exist_ok=True)
    record = {"phase": "SPI-P4", "stage": args.stage, "status": status,
              "problems": problems, "configuration_digest": configuration_digest(manifest),
              "phase_accepted": False}
    atomic_write(output / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    for problem in problems:
        print(problem, file=sys.stderr)
    return int(bool(problems)) if args.stage == "check" else (0 if status == "passed" else 1)


if __name__ == "__main__":
    raise SystemExit(main())
