#!/usr/bin/env python3
"""Run and validate one HP workload without reusing another workload's verdict."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


MARKERS = {
    "smoke": ("HP_LINUX_READY", "HP_GA2D_PASS", "HP_GA2D_CACHE_CLEAN"),
    "linux": ("HP_LINUX_INIT_PASS", "retroSoC HP Linux ready", "HP_LINUX_READY"),
    "rtthread": ("RTTHREAD_RV64_PASS", "RTTHREAD_TIMEOUT_PASS", "RTTHREAD_PREEMPT_PASS",
                 "RTTHREAD_CONTEXT_PASS", "RTTHREAD_IPC_PASS", "RTTHREAD_MAILBOX_IRQ_PASS",
                 "RTTHREAD_TEST_PASS", "HP_RTTHREAD_PASS"),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workload", choices=MARKERS, required=True)
    parser.add_argument("--timeout", type=int, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = output / "result-sim-check.json"
    result.write_text(json.dumps({"status": "running", "workload": args.workload}) + "\n",
                      encoding="utf-8")
    scripts = Path(__file__).resolve().parent
    try:
        process = subprocess.run([
            sys.executable, str(scripts / "run_flow.py"), "--tool", "verilator-sim",
            "--stream-bytes", "--log", str(output / "sim.log"), "--result",
            str(output / "result-sim.json"), "--cwd", str(output), "--",
            str(args.emulator.resolve()), "-i", str(args.image.resolve()),
            "--fast-flash", "-t", str(args.timeout),
        ], check=False)
        if process.returncode:
            result.write_text(json.dumps({"status": "failed", "exit_code": process.returncode})
                              + "\n", encoding="utf-8")
            return process.returncode
        command = [sys.executable, str(scripts / "check_simulation.py"), "--log",
                   str(output / "sim.log"), "--result", str(result)]
        for marker in ("VERILATOR_FAST_FLASH=enabled", "SIM_TEST_PASS code=0",
                       *MARKERS[args.workload]):
            command.extend(("--require", marker))
        return subprocess.run(command, check=False).returncode
    except KeyboardInterrupt:
        result.write_text('{"status": "interrupted"}\n', encoding="utf-8")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
