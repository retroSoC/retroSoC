#!/usr/bin/env python3
"""Run the local Verilator, OpenOCD, and GDB Hazard3 debug acceptance flow."""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


SUCCESS_MARKER = "DEBUG_GDB_PASS"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", required=True, type=Path)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--elf", required=True, type=Path)
    parser.add_argument("--openocd", default="openocd")
    parser.add_argument("--gdb", default="riscv32-unknown-elf-gdb")
    parser.add_argument("--openocd-config", required=True, type=Path)
    parser.add_argument("--log-dir", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--sim-time", type=int, default=180)
    return parser.parse_args()


def reserve_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def wait_for_port(port: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError(f"timed out waiting for 127.0.0.1:{port}")


def stop(process: subprocess.Popen[object] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def gdb_commands(elf: Path, gdb_port: int) -> str:
    return "\n".join(
        (
            "set confirm off",
            "set pagination off",
            "set remotetimeout 30",
            "set architecture riscv:rv32",
            f"file {elf}",
            f"target extended-remote 127.0.0.1:{gdb_port}",
            "p/x $pc",
            "set {unsigned int}0x3001ff00 = 0x5a5aa5a5",
            "x/w 0x3001ff00",
            "load",
            "break *0x30000008",
            "continue",
            "p/x $pc",
            "stepi",
            "p/x $pc",
            f'printf "{SUCCESS_MARKER}\\n"',
            "detach",
            "quit",
            "",
        )
    )


def main() -> int:
    args = parse_args()
    start = time.monotonic()
    started_at = datetime.now(timezone.utc)
    log_dir = args.log_dir.resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    args.result.parent.mkdir(parents=True, exist_ok=True)
    emulator_log = log_dir / "emulator.log"
    openocd_log = log_dir / "openocd.log"
    gdb_log = log_dir / "gdb.log"
    gdb_script = log_dir / "debug.gdb"
    jtag_port = reserve_port()
    gdb_port = reserve_port()
    emulator: subprocess.Popen[object] | None = None
    openocd: subprocess.Popen[object] | None = None
    error: str | None = None
    status = "failed"

    try:
        gdb_script.write_text(gdb_commands(args.elf.resolve(), gdb_port), encoding="utf-8")
        with emulator_log.open("w", encoding="utf-8") as emulator_stream:
            emulator = subprocess.Popen(
                [
                    str(args.emulator.resolve()),
                    "--image",
                    str(args.image.resolve()),
                    "--sim-time",
                    str(args.sim_time),
                    "--jtag-port",
                    str(jtag_port),
                ],
                stdout=emulator_stream,
                stderr=subprocess.STDOUT,
                text=True,
            )
            wait_for_port(jtag_port, args.timeout)

            with openocd_log.open("w", encoding="utf-8") as openocd_stream:
                openocd = subprocess.Popen(
                    [
                        args.openocd,
                        "-c",
                        f"set jtag_port {jtag_port}",
                        "-f",
                        str(args.openocd_config.resolve()),
                        "-c",
                        f"gdb_port {gdb_port}",
                        "-c",
                        "tcl_port disabled",
                        "-c",
                        "telnet_port disabled",
                    ],
                    stdout=openocd_stream,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                wait_for_port(gdb_port, args.timeout)
                with gdb_log.open("w", encoding="utf-8") as gdb_stream:
                    result = subprocess.run(
                        [args.gdb, "--batch", "--nx", "--quiet", "--command", str(gdb_script)],
                        stdout=gdb_stream,
                        stderr=subprocess.STDOUT,
                        text=True,
                        timeout=args.timeout,
                        check=False,
                    )
                if result.returncode != 0:
                    raise RuntimeError(f"GDB exited with status {result.returncode}")
                if SUCCESS_MARKER not in gdb_log.read_text(encoding="utf-8"):
                    raise RuntimeError("GDB session did not print the success marker")
                status = "passed"
    except (OSError, RuntimeError, TimeoutError, subprocess.SubprocessError) as exception:
        error = str(exception)
    finally:
        stop(openocd)
        stop(emulator)

    report = {
        "schema_version": 1,
        "tool": "verilator-openocd-gdb",
        "started_at": started_at.isoformat(),
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "duration_seconds": round(time.monotonic() - start, 3),
        "status": status,
        "success_marker": SUCCESS_MARKER,
        "success_marker_seen": status == "passed",
        "logs": {
            "emulator": str(emulator_log),
            "openocd": str(openocd_log),
            "gdb": str(gdb_log),
            "gdb_script": str(gdb_script),
        },
    }
    if error is not None:
        report["error"] = error
    atomic_write(args.result, json.dumps(report, indent=2, sort_keys=True) + "\n")
    if error is not None:
        print(f"debug session failed: {error}")
        return 1
    print(SUCCESS_MARKER)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
