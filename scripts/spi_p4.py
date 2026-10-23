#!/usr/bin/env python3
"""Source-bound focused SPI-P4 Tiny display checks and panel-oracle validation."""
from __future__ import annotations

import argparse
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


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def focused(output: Path, stage: str) -> int:
    output.mkdir(parents=True, exist_ok=False)
    command = [sys.executable, "-m", "pytest", "-q", "tests/test_spi_p4.py",
               "tests/test_spi_p3.py", "tests/test_spi_register_parity.py"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    atomic_write(output / "pytest.log", result.stdout + result.stderr)
    return result.returncode


def check_log(log: str, quick: bool = False) -> list[str]:
    problems = []
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
    checksum_stage = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 8: 7}
    if len(windows) != len(expected):
        problems.append(f"expected {len(expected)} windows, saw {len(windows)}")
        return problems
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
        if seq == 7:
            if aborted != 1 or not (0 < pixels < want_pixels):
                problems.append(f"window 7: abort semantics wrong pixels={pixels} aborted={aborted}")
            continue
        if aborted != 0:
            problems.append(f"window {seq}: unexpected abort")
        if pixels != want_pixels:
            problems.append(f"window {seq}: pixels {pixels} != {want_pixels}")
            continue
        golden = fnv1a(window_stream(checksum_stage[seq], *geometry))
        if int(fields["fnv1a"], 16) != golden:
            problems.append(f"window {seq}: pixel checksum mismatch")
    if panel is None:
        problems.append("missing SPI_P4_PANEL summary")
    else:
        if int(panel["violations"], 16) != 0:
            problems.append("panel summary reports violations")
        if int(panel["pixels"], 16) != sum(int(w["pixels"], 16) for w in windows):
            problems.append("panel pixel total mismatch")
    if commands < 10:
        problems.append(f"too few commands observed: {commands}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "report", "check"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--quick", action="store_true")
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
        problems = check_log(args.log.read_text(errors="replace"), quick=args.quick)
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
