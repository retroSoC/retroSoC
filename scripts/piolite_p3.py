#!/usr/bin/env python3
"""Independent source-bound PIOLITE-P3 Tiny acceptance checks."""
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
from scripts.flow_control import digest_json, source_state  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

FORBIDDEN = ("FAILED", "FATAL", "assertion failed", "%Error", "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT")
SOURCE_PROGRAM = "app/apps/ci_smoke/tiny_piolite_p3.c"
OBSERVER = "rtl/tiny/dv/tiny_piolite_observers.svh"
MIN_ACCEPTANCE_CYCLES = 20_000_000


def records(log: str, prefix: str) -> list[dict[str, str]]:
    result = []
    for line in log.splitlines():
        if not line.startswith(prefix + " "):
            continue
        fields = line[len(prefix) + 1:].split()
        names = [field.partition("=")[0] for field in fields]
        if (not fields or any("=" not in field for field in fields) or
                len(names) != len(set(names))):
            raise ValueError(f"malformed or duplicate fields in {prefix}")
        result.append(dict(field.split("=", 1) for field in fields))
    return result


def number(row: dict[str, str], name: str) -> int:
    return int(row[name], 0)


EXPECTED_CHECKS = [
    {"id": "1", "pass": "1", "clock": "24000000", "mask": "0003ffff"},
    {"id": "2", "pass": "1", "pins": "32"},
    {"id": "3", "pass": "1", "shared": "1"},
    {"id": "4", "pass": "1", "output": "1"},
    {"id": "5", "pass": "1", "tx_bytes": "4", "rx_bytes": "4"},
    {"id": "6", "pass": "1", "tcds": "2", "tx_bytes": "4"},
    {"id": "7", "pass": "1", "rcu": "1"},
    {"id": "8", "pass": "1", "reset": "1"},
]


def _check_log(log: str, observer_log: str) -> list[str]:
    problems = [f"forbidden marker: {marker}" for marker in FORBIDDEN
                if marker in log or marker in observer_log]
    terminal = re.findall(r"^SIM_TEST_PASS Tiny.*$", log, re.MULTILINE)
    if (len(terminal) != 1 or
            re.fullmatch(r"SIM_TEST_PASS Tiny cycles=[1-9][0-9]*", terminal[0]) is None):
        problems.append("missing, malformed, or duplicate Tiny terminal verdict")
    if re.search(r"^SIM_TEST_(?:PASS|FAIL|TIMEOUT)", observer_log, re.MULTILINE):
        problems.append("terminal verdict appears in the observer log")
    if records(log, "PIOLITE_P3_CHECK") != EXPECTED_CHECKS:
        problems.append("P3 case records are incomplete, malformed, duplicated, or reordered")
    if records(log, "PIOLITE_P3_RESULT") != [{"code": "0"}]:
        problems.append("P3 result is missing, malformed, duplicated, or failed")
    expected_observation = [{"mask": "ffffffff", "reset_seen": "1", "output_oe": "00000000"}]
    if records(observer_log, "PIOLITE_P3_OBSERVATION") != expected_observation:
        problems.append("GPIO observation is missing, malformed, duplicated, or incomplete")
    if records(observer_log, "PIOLITE_P3_RESET") != [{"seen": "1"}]:
        problems.append("GPIO reset marker is missing, malformed, or duplicated")
    if records(observer_log, "PIOLITE_P3_OUTPUT") != [{"pin": "4", "value": "1", "oe": "1"}]:
        problems.append("GPIO output/ownership observation is missing, malformed, or duplicated")
    for prefix in ("PIOLITE_P3_OBSERVATION", "PIOLITE_P3_RESET", "PIOLITE_P3_OUTPUT"):
        if records(log, prefix):
            problems.append(f"observer record appears in the firmware log: {prefix}")
    for prefix in ("PIOLITE_P3_CHECK", "PIOLITE_P3_RESULT"):
        if records(observer_log, prefix):
            problems.append(f"firmware record appears in the observer log: {prefix}")
    return problems


def check_log(log: str, observer_log: str) -> list[str]:
    try:
        return _check_log(log, observer_log)
    except (KeyError, ValueError) as error:
        return [f"malformed P3 record: {error}"]


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact_name(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def base_record(manifest: dict, variant: Path, stage: str, pdk: str, command: list[str],
                observed_gaps: list[str]) -> dict:
    firmware = variant / "sw/retrosoc_fw.hex"
    repository = manifest["repository"]
    dependency_lock = manifest["dependency_lock"]
    return {
        "phase": "PIOLITE-P3",
        "stage": stage,
        "source_revision": repository["commit"],
        "source_dirty": repository["dirty"],
        "dependency_lock": dependency_lock,
        "dependency_lock_sha256": dependency_lock["sha256"],
        "profile": manifest["profile"],
        "pdk": pdk,
        "variant": artifact_name(variant),
        "configuration": manifest["configuration"],
        "configuration_digest": configuration_digest(manifest),
        "tool_versions": manifest["tools"],
        "source_programs": [{
            "source": SOURCE_PROGRAM,
            "source_sha256": file_sha256(ROOT / SOURCE_PROGRAM),
            "observer": OBSERVER,
            "observer_sha256": file_sha256(ROOT / OBSERVER),
            "assembled_image": artifact_name(firmware),
            "assembled_image_sha256": file_sha256(firmware),
            "assembled_binary": artifact_name(variant / "sw/retrosoc_fw.bin"),
            "assembled_binary_sha256": file_sha256(variant / "sw/retrosoc_fw.bin"),
            "disassembly": artifact_name(variant / "sw/retrosoc_fw.txt"),
            "disassembly_sha256": file_sha256(variant / "sw/retrosoc_fw.txt"),
        }],
        "clock_rates_hz": {
            "external": int(manifest["configuration"]["EXT_CLK_HZ"]),
            "safe24_pclk": 24_000_000,
            "pll192_rediscovery_target_pclk": 48_000_000,
        },
        "pin_assignment_electrical_model": {
            "input_pins": "GPIO0..31; driven value is pin[0]",
            "output_pin": 4,
            "reset_pin": 31,
            "model": "three-state pin drive; observed USER output/OE and one-cycle GPIO reset with release",
        },
        "dma_bindings": {
            "direct": {"tx_request": 14, "rx_request": 15, "tx_channel": 3, "rx_channel": 2,
                       "tx_bytes": 4, "rx_bytes": 4},
            "mixed_tcd": {"tx_channel": 3, "descriptors": 2, "tx_bytes": 4,
                          "chain": "MM_TO_MM->MM_TO_STREAM"},
        },
        "command": command,
        "command_sha256": digest_json(command),
        "firmware_sha256": file_sha256(firmware),
        "observed_gaps": observed_gaps,
        "phase_accepted": False,
    }


def identity_problems(manifest: dict, verdict: dict, variant: Path, pdk: str, simulator: str,
                      log_path: Path, observer_log: Path) -> list[str]:
    problems = []
    current = source_state(ROOT)
    repository = manifest.get("repository", {})
    revision = repository.get("commit")
    if re.fullmatch(r"[0-9a-f]{40}", str(revision)) is None or revision != verdict.get("source_revision"):
        problems.append("source revision is missing or differs between manifest and simulation")
    if repository.get("dirty") != verdict.get("source_dirty") or not isinstance(repository.get("dirty"), bool):
        problems.append("source dirty state differs between manifest and simulation")
    if current.get("source_state_sha256") != verdict.get("source_state_sha256"):
        problems.append("source tree changed after simulation")
    dependency = manifest.get("dependency_lock", {})
    lock_digest = file_sha256(ROOT / "dependencies/dependencies.lock.json")
    if (dependency.get("sha256") != lock_digest or verdict.get("tool_lock_sha256") != lock_digest or
            current.get("tool_lock_sha256") != lock_digest):
        problems.append("dependency lock differs between source, manifest and simulation")
    for relative, expected in manifest.get("filelists", {}).items():
        path = (variant / relative).resolve()
        try:
            path.relative_to(variant)
            actual = file_sha256(path)
        except (ValueError, OSError):
            actual = None
        if actual != expected:
            problems.append(f"filelist digest mismatch: {relative}")
    if manifest.get("profile") != f"{pdk.lower()}-tiny":
        problems.append("manifest profile does not match the selected Tiny PDK")
    if verdict.get("tool") != f"{simulator}-sim" or verdict.get("exit_code") != 0:
        problems.append("simulator identity or exit status is invalid")
    if Path(verdict.get("log", "")).resolve() != log_path:
        problems.append("simulation log path differs from its structured verdict")
    try:
        observer_log.relative_to(variant)
    except ValueError:
        problems.append("observer log is outside the selected build variant")
    if observer_log == log_path:
        problems.append("observer log must be distinct from the firmware log")
    command = verdict.get("command")
    if not isinstance(command, list) or not all(isinstance(item, str) for item in command):
        problems.append("simulation command is missing or malformed")
        command = []
    if digest_json(command) != verdict.get("command_sha256"):
        problems.append("simulation command digest mismatch")
    executable = variant / "sim" / simulator / ("emu" if simulator == "verilator" else "simv")
    if str(executable) not in command:
        problems.append("simulation command does not name the selected build executable")
    if f"+firmware={variant / 'sw/retrosoc_fw.hex'}" not in command or "+tiny_piolite_p3" not in command:
        problems.append("simulation command does not select the isolated P3 image and observer")
    observer_args = [item for item in command if item.startswith("+tiny_piolite_observer_log=")]
    if observer_args != [f"+tiny_piolite_observer_log={observer_log}"]:
        problems.append("simulation command does not bind the selected observer log exactly once")
    try:
        cycles = next(int(item.split("=", 1)[1]) for item in command if item.startswith("+max_cycles="))
    except (StopIteration, ValueError):
        cycles = 0
    if cycles < MIN_ACCEPTANCE_CYCLES:
        problems.append("simulation cycle budget is below the full P3 acceptance")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "report", "check"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--simulator", type=str.lower, choices=("verilator", "iverilog"))
    parser.add_argument("--log", type=Path)
    parser.add_argument("--observer-log", type=Path)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    configuration = manifest["configuration"]
    if (configuration["SOC"] != "TINY" or configuration["PDK"] != args.pdk or
            configuration.get("APP") != "ci_smoke" or
            configuration.get("TINY_PIOLITE_P3_ACCEPTANCE") != "YES" or
            manifest.get("profile") != f"{args.pdk.lower()}-tiny"):
        raise ValueError("not a matching isolated Tiny PIOLITE-P3 build variant")
    output = variant / "meta/piolite-p3" / args.stage
    output.mkdir(parents=True, exist_ok=False)
    problems = []
    if args.stage in {"lint", "rtl"}:
        command = [sys.executable, "-m", "pytest", "-q", "tests/test_piolite_p3.py",
                   "tests/test_piolite_register_parity.py"]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
        log_path = output / "pytest.log"
        atomic_write(log_path, result.stdout + result.stderr)
        if result.returncode != 0:
            problems.append("focused PIOLITE-P3 tests failed")
            print(result.stdout + result.stderr, file=sys.stderr)
        gaps = [*problems, "Focused host/RTL tests only; no TEST_STATUS or terminal simulator verdict is implied"]
        record = base_record(manifest, variant, args.stage, args.pdk, command, gaps)
        record.update(status="passed" if result.returncode == 0 else "failed", problems=problems,
                      source_state_sha256=source_state(ROOT)["source_state_sha256"],
                      structured_verdict={"kind": "pytest", "exit_code": result.returncode},
                      log=artifact_name(log_path), log_sha256=file_sha256(log_path))
    else:
        if args.simulator is None or args.log is None or args.observer_log is None:
            raise ValueError("a real simulator and separate firmware/observer logs are required")
        if configuration.get("SIMU", "").lower() != args.simulator:
            raise ValueError("not an isolated PIOLITE-P3 build for the selected simulator")
        log_path = args.log.resolve()
        log_path.relative_to(variant)
        observer_log = args.observer_log.resolve()
        verdict_path = log_path.parent / "result-sim.json"
        check_path = log_path.parent / "result-sim-check.json"
        verdict = json.loads(verdict_path.read_text())
        check_verdict = json.loads(check_path.read_text())
        problems.extend(identity_problems(manifest, verdict, variant, args.pdk, args.simulator, log_path,
                                          observer_log))
        if verdict.get("status") != "passed" or check_verdict.get("status") != "passed":
            problems.append("structured simulation verdict did not pass")
        log_text = log_path.read_text(errors="replace")
        observer_text = observer_log.read_text(errors="replace")
        problems.extend(check_log(log_text, observer_text))
        command = verdict.get("command", [])
        if (isinstance(command, list) and "+tiny_piolite_progress" in command and
                "PIOLITE_P3_PROGRESS cycles=" not in observer_text):
            problems.append("requested PIOLITE progress observations are missing")
        gaps = [*problems,
                "Only this source/profile/simulator is covered; other gates and physical qualification remain separate"]
        record = base_record(manifest, variant, args.stage, args.pdk, command, gaps)
        record.update(status="passed" if not problems else "failed", problems=problems, simulator=args.simulator,
                      source_state_sha256=verdict.get("source_state_sha256"),
                      simulator_sha256=file_sha256(variant / "sim" / args.simulator /
                                                   ("emu" if args.simulator == "verilator" else "simv")),
                      log=artifact_name(log_path), log_sha256=file_sha256(log_path),
                      observer_log=artifact_name(observer_log), observer_log_sha256=file_sha256(observer_log),
                      structured_verdict={"run": artifact_name(verdict_path), "check": artifact_name(check_path)},
                      run_result_sha256=file_sha256(verdict_path), check_result_sha256=file_sha256(check_path))
    atomic_write(output / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    for problem in record["problems"]:
        print(problem, file=sys.stderr)
    return int(bool(record["problems"]))


if __name__ == "__main__":
    raise SystemExit(main())
