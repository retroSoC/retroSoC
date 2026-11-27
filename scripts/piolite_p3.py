#!/usr/bin/env python3
"""Independent source-bound PIOLITE-P3 Tiny acceptance-log checks."""
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
from scripts.setup_helpers import atomic_write  # noqa: E402

TERMINAL = re.compile(r"SIM_TEST_PASS Tiny cycles=[1-9][0-9]*")


def check_log(log: str) -> list[str]:
    problems = []
    failure = DEFAULT_FAILURE.search(log)
    if failure:
        problems.append(f"forbidden marker: {failure.group(0)}")
    terminal = re.findall(r"^SIM_TEST_PASS Tiny.*$", log, re.MULTILINE)
    if len(terminal) != 1 or TERMINAL.fullmatch(terminal[0]) is None:
        problems.append("missing, malformed, or duplicate Tiny terminal verdict")
    return problems


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def evaluate(variant: Path, pdk: str, simulator_name: str, log_path: Path) -> dict:
    manifest_path = variant / "meta/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    configuration = manifest["configuration"]
    if (configuration["SOC"] != "TINY" or configuration["PDK"] != pdk or
            configuration.get("TINY_PIOLITE_P3_ACCEPTANCE") != "YES" or
            configuration["SIMU"] != simulator_name.upper()):
        raise ValueError("not a matching Tiny PIOLITE-P3 build variant")
    problems = check_log(log_path.read_text(errors="replace"))
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
    if "+piolite_p3_loopback" not in command:
        problems.append("simulation did not isolate the external loopback drivers")

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

    return {
        "phase": "PIOLITE-P3",
        "stage": "check",
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
        "phase_accepted": False,
    }


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
    record = evaluate(variant, args.pdk, args.simulator, log_path)
    output = variant / "meta/piolite-p3" / args.stage
    output.mkdir(parents=True, exist_ok=True)
    atomic_write(output / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    for problem in record["problems"]:
        print(problem, file=sys.stderr)
    return int(record["status"] != "passed")


if __name__ == "__main__":
    raise SystemExit(main())
