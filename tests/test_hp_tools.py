"""RV64 artifact admission and workload-specific simulation verdicts."""

from __future__ import annotations

import json
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

import pytest

from scripts.hp_tools import require_rv64_elf
from scripts.run_hp_sim import MARKERS

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("elf_class,machine,accepted", [(2, 243, True), (1, 243, False), (2, 62, False)])
def test_hp_executable_class(elf_class, machine, accepted, tmp_path):
    header = bytearray(64)
    header[:6] = b"\x7fELF" + bytes((elf_class, 1))
    struct.pack_into("<H", header, 18, machine)
    path = tmp_path / "payload.elf"
    path.write_bytes(header)
    if accepted:
        require_rv64_elf(path)
    else:
        with pytest.raises(ValueError, match="RV64 ELF"):
            require_rv64_elf(path)


@pytest.mark.parametrize("fault", ["none", "missing", "failure", "exit"])
def test_hp_runner_requires_all_markers_and_zero_exit(tmp_path, fault):
    emulator = tmp_path / "emu"
    markers = ["VERILATOR_FAST_FLASH=enabled", "SIM_TEST_PASS code=0", *MARKERS["rtthread"]]
    if fault == "missing":
        markers.remove("RTTHREAD_MAILBOX_IRQ_PASS")
    if fault == "failure":
        markers.append("SIM_TEST_FAIL code=1")
    emulator.write_text(f"#!{sys.executable}\nprint({chr(10).join(markers)!r})\n"
                        f"raise SystemExit({int(fault == 'exit')})\n")
    emulator.chmod(0o755)
    output = tmp_path / "result"
    output.mkdir()
    verdict = output / "result-sim-check.json"
    verdict.write_text('{"status":"passed"}')
    result = subprocess.run([sys.executable, str(ROOT / "scripts/run_hp_sim.py"),
                             "--emulator", str(emulator), "--image", str(tmp_path / "boot.bin"),
                             "--output", str(output), "--workload", "rtthread", "--timeout", "1"],
                            capture_output=True, text=True, check=False)
    assert (result.returncode == 0) == (fault == "none")
    assert json.loads(verdict.read_text())["status"] == ("passed" if fault == "none" else "failed")


def test_running_and_interrupted_flow_replace_previous_pass(tmp_path):
    verdict = tmp_path / "result.json"
    verdict.write_text('{"status":"passed"}')
    ready = tmp_path / "ready"
    child = f"from pathlib import Path; import time; Path({str(ready)!r}).touch(); time.sleep(30)"
    process = subprocess.Popen([sys.executable, str(ROOT / "scripts/run_flow.py"), "--tool", "test",
                                "--log", str(tmp_path / "sim.log"), "--result", str(verdict),
                                "--", sys.executable, "-c", child], stdout=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 10
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert ready.exists()
        assert json.loads(verdict.read_text())["status"] == "running"
        process.send_signal(signal.SIGINT)
        assert process.wait(timeout=10) == 130
        assert json.loads(verdict.read_text())["status"] == "interrupted"
    finally:
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            process.wait(timeout=10)
