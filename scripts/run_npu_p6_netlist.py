#!/usr/bin/env python3
"""Run IHP130 NPU block synthesis/STA and KWS/VWW netlist workloads."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

from test_npu_rtl_p4 import _operator_cases  # noqa: E402


SRAM_MACRO = "RM_IHPSG13_1P_1024x32_c2_bm_bist"
DIRECTED_CASES = ("conv_kws_10x4", "dw33_s2_c7", "rej_stride3", "arith_acc_overflow")
REJECTED = re.compile(r"FAILED|FATAL|assertion failed|%Error|SIM_TEST_FAIL|SIM_TEST_TIMEOUT")
SPECIFY_BLOCK = re.compile(r"(?ms)^\s*specify\b.*?^\s*endspecify\s*$")
DELAYED_SIGNAL = re.compile(r"\bdelayed_([A-Za-z][A-Za-z0-9_]*)\b")


def identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def run(command: list[str], *, log: Path, timeout: int | None = None) -> None:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
        env={**os.environ, "CCACHE_DISABLE": "1"},
    )
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}\n{completed.stdout[-4000:]}")


def write_functional_stdcell(source: Path, output: Path) -> None:
    text = source.read_text(encoding="utf-8")
    transformed, specify_count = SPECIFY_BLOCK.subn("", text)
    transformed = DELAYED_SIGNAL.sub(r"\1", transformed)
    transformed, notifier_count = re.subn(
        r"(?m)^\s*reg notifier;\s*$", "\twire notifier = 1'b0;", transformed
    )
    if specify_count == 0 or notifier_count == 0 or "delayed_" in transformed:
        raise ValueError("IHP standard-cell functional transformation was incomplete")
    output.write_text(transformed, encoding="utf-8")


def plusarg_value(arguments: list[str], name: str) -> str:
    prefix = f"+{name}="
    matches = [argument[len(prefix) :] for argument in arguments if argument.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"directed netlist case has invalid {name} plusarg")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument(
        "--reuse-physical",
        action="store_true",
        help="reuse an existing isolated-npu.json after validating it (debug only)",
    )
    args = parser.parse_args()
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    output = args.output_dir.resolve()
    physical = output / "physical"
    evidence_path = physical / "isolated-npu.json"
    if not args.reuse_physical:
        run(
            [
                sys.executable,
                str(ROOT / "scripts/run_npu_p1_flow.py"),
                "--build-root",
                str(physical),
                "--top",
                "npu_block_top",
                "--evidence",
                str(evidence_path),
            ],
            log=physical / "driver.log",
            timeout=args.timeout_seconds,
        )
    elif not evidence_path.is_file():
        raise ValueError("--reuse-physical requires an existing isolated-npu.json")
    physical_evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    top = physical_evidence["tops"]["npu_block_top"]
    if physical_evidence.get("verdict") != "PASS" or top["synth"]["sram_macro_count"] != 16:
        raise ValueError("NPU block physical evidence did not pass with exactly 16 SRAM macros")
    netlist = Path(top["synth"]["netlist"])
    transaction_netlist = netlist.with_name(netlist.name.replace("_yosys.v", "_yosys_debug.v"))
    if (
        not transaction_netlist.is_file()
        or transaction_netlist.read_text(encoding="utf-8", errors="replace").count(
            f"{SRAM_MACRO} u_mem"
        )
        != 16
    ):
        raise ValueError("technology-mapped transaction netlist does not contain 16 SRAM macros")
    pdk = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref"
    stdcell_source = pdk / "sg13g2_stdcell/verilog/sg13g2_stdcell.v"
    stdcell_functional = output / "sg13g2_stdcell_functional.v"
    write_functional_stdcell(stdcell_source, stdcell_functional)
    compile_dir = output / "verilator-netlist"
    simulator = compile_dir / "npu_netlist_tb"
    compile_log = output / "compile.log"
    run(
        [
            "verilator",
            "--binary",
            "--timing",
            "--top-module",
            "npu_operator_tb",
            "-Wno-fatal",
            "--x-initial",
            "0",
            "--x-assign",
            "0",
            "-j",
            str(args.jobs),
            "-o",
            simulator.name,
            "--Mdir",
            str(compile_dir),
            "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
            "-I" + str(ROOT / "rtl/ip/multimedia"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(pdk / "sg13g2_stdcell/verilog/sg13g2_udp.v"),
            str(stdcell_functional),
            str(ROOT / "tests/rtl/ihp130_npu_sram_model.sv"),
            str(transaction_netlist),
            str(ROOT / "tests/rtl/npu_operator_tb.sv"),
        ],
        log=compile_log,
        timeout=args.timeout_seconds,
    )
    artifact_dir = output / "artifacts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    generated = _operator_cases(artifact_dir, selected=set(DIRECTED_CASES))
    by_name = {plusarg_value(arguments, "NAME"): arguments for arguments in generated}
    if not set(DIRECTED_CASES) <= set(by_name):
        raise ValueError("P4 fixture generator omitted a required P6 netlist case")
    cases = []
    for name in DIRECTED_CASES:
        plusargs = by_name[name]
        log = output / f"{name}.log"
        command = [str(simulator), *plusargs]
        run(command, log=log, timeout=args.timeout_seconds)
        text = log.read_text(encoding="utf-8", errors="replace")
        if "NPU operator test passed" not in text or REJECTED.search(text):
            raise ValueError(f"{name} netlist workload did not produce a clean pass")
        artifacts = {
            label.lower(): identity(Path(plusarg_value(plusargs, label)))
            for label in ("IMG", "GOLD")
        }
        cases.append({
            "case": name,
            "status": "PASS",
            "command": command,
            "artifacts": artifacts,
            "log": identity(log),
        })
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V017", "NPU-V018"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "physical_reused": args.reuse_physical,
        "physical": identity(evidence_path),
        "netlist": identity(netlist),
        "transaction_netlist": identity(transaction_netlist),
        "stdcell_source": identity(stdcell_source),
        "stdcell_functional": identity(stdcell_functional),
        "simulator": identity(simulator),
        "compile_log": identity(compile_log),
        "sram_functional_model": identity(ROOT / "tests/rtl/ihp130_npu_sram_model.sv"),
        "sram_macro_count": 16,
        "simulation_policy": {
            "simulator": "Verilator",
            "state_model": "2-state",
            "x_initial": "0",
            "x_assign": "0",
            "timing_evidence": False,
        },
        "implementation": {
            name: identity(ROOT / name)
            for name in (
                "scripts/run_npu_p6_netlist.py",
                "scripts/run_npu_p1_flow.py",
                "physical/smoke/syn/yosys/npu_block_top.sv",
                "tests/rtl/npu_operator_tb.sv",
                "tests/rtl/ihp130_npu_sram_model.sv",
                "tests/test_npu_rtl_p4.py",
            )
        },
        "cases": cases,
        "summary": {"required_cases": 4, "passes": 4, "failures": 0, "skipped": 0},
        "verdict": "PASS",
    }
    report_path = output / "qualification-p6-netlist.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 netlist qualification: PASS ({report_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
