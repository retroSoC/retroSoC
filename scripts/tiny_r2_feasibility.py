#!/usr/bin/env python3
"""Retain reset-load and same-frequency CPU/SRAM feasibility; never qualify a rate."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import math
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as baseline  # noqa: E402

PHASE = "TINY-R2-P2"
RATES = (24, 96, 192, 240)
CORNERS = {
    "slow": ("slow_1p08V_125C", "slow_1p08V_3p0V_125C", "slow_1p08V_125C"),
    "typ": ("typ_1p20V_25C", "typ_1p2V_3p3V_25C", "typ_1p20V_25C"),
    "fast": ("fast_1p32V_m40C", "fast_1p32V_3p6V_m40C", "fast_1p32V_m55C"),
}
MACRO = "RM_IHPSG13_1P_1024x32_c2_bm_bist"
SDC_CLOCK = re.compile(r"^(create_clock -name clk_system -period )([0-9.]+)( \$clk_system_pin)$", re.MULTILINE)


def source_inputs(root: Path) -> dict:
    inputs = baseline.source_inputs(root)
    for path in (root / "tests").rglob("*"):
        if path.is_file() and path.suffix in (".py", ".sv", ".svh"):
            inputs[str(path.relative_to(root))] = baseline.sha256(path)
    return inputs


def generated_inputs(root: Path, variant: Path) -> dict:
    return {str(p.relative_to(root)): baseline.sha256(p)
            for p in (variant / "generated/tiny").rglob("*") if p.is_file()}


def require_variant(root: Path, variant: Path) -> dict:
    if not variant.is_relative_to(root / "build"):
        raise ValueError("evidence must remain below repository build variants")
    manifest = baseline.configuration(variant)
    config = manifest["configuration"]
    if config["PDK"] != "IHP130" or config["APP"] != "ci_smoke" or config["MGMT_CPU_CLK_HZ"] != "24000000":
        raise ValueError("feasibility requires the 24 MHz Tiny ci_smoke variant")
    return manifest


def candidate_sdc(original: str, mhz: int) -> str:
    if mhz not in RATES or len(SDC_CLOCK.findall(original)) != 1:
        raise ValueError("expected one baseline system clock and a frozen candidate rate")
    if abs(float(SDC_CLOCK.search(original)[2]) - 1000 / 24) > 1e-6:
        raise ValueError("source SDC is not the 24 MHz baseline")
    if mhz == 24:
        return original
    return SDC_CLOCK.sub(lambda m: m[1] + f"{1000 / mhz:.12g}" + m[3], original)


def timing_metrics(path: Path) -> dict:
    values = {}
    for line in path.read_text().splitlines():
        key, _, value = line.partition("=")
        values[key] = float(value.split()[-1])
    if (set(values) != {"wns_min", "wns_max", "tns_min", "tns_max"}
            or not all(math.isfinite(value) for value in values.values())):
        raise ValueError("incomplete STA measurements")
    return values


def reset_loads(path: Path, candidate: bool) -> dict:
    rows = {}
    for line in path.read_text().splitlines()[1:]:
        name, driver, direct, endpoints = line.split("\t")
        if name in rows or min(int(direct), int(endpoints)) < 0:
            raise ValueError("invalid reset-load accounting")
        rows[name] = {"driver": driver, "direct_loads": int(direct), "structural_endpoints": int(endpoints)}
    expected = {"system"} | ({f"leaf-{index}" for index in range(17)} if candidate else set())
    if set(rows) != expected or len({r["driver"] for r in rows.values()}) != len(rows):
        raise ValueError("reset drivers merged or missing")
    return rows


def path_slack(path: Path) -> float:
    match = re.search(r"(?m)^\s*([-+]?\d+(?:\.\d+)?)\s+slack\b", path.read_text())
    if match is None:
        raise ValueError(f"missing constrained SYS path: {path}")
    return float(match[1])


def capture(args: argparse.Namespace) -> int:
    root, variant = args.root.resolve(), args.variant_root.resolve()
    manifest = require_variant(root, variant)
    parent = variant / "meta/tiny-r2-p2"
    directory = baseline.new_attempt(parent, "inputs-")
    inputs = source_inputs(root) | generated_inputs(root, variant)
    record = {"phase": PHASE, "created_at": datetime.now(timezone.utc).isoformat(),
              "manifest": manifest, "tools": baseline.tools_identity(root),
              "source": baseline.snapshot(root, directory, inputs)}
    baseline.dump(directory / "identity.json", record)
    baseline.dump(parent / "latest-inputs.json", {"path": str(directory / "identity.json")})
    print(f"Tiny P2 captured candidate inputs: {directory}")
    return 0


def consumed_files(variant: Path) -> dict:
    return {name: baseline.artifact(variant / name) for name in (
        "meta/manifest.json", "syn/yosys/result-synth.json", "sta/opensta/result-sta.json",
        "syn/yosys/out/retrosoc_tiny_asic_yosys.v", "syn/yosys/out/retrosoc_tiny_asic_yosys.config",
        "sta/opensta/retrosoc_core.sdc")}


def run(args: argparse.Namespace) -> int:
    root, variant = args.root.resolve(), args.variant_root.resolve()
    old_variant = args.baseline_root.resolve()
    require_variant(root, variant)
    require_variant(root, old_variant)
    parent = variant / "meta/tiny-r2-p2"
    directory = baseline.new_attempt(parent, "feasibility-")
    output = directory / "report.json"
    baseline.dump(parent / "latest-feasibility.json", {"path": str(output)})
    record = {"phase": PHASE, "status": "running", "points": [],
              "qualification": "early unextracted feasibility only; no qualified operating point"}
    try:
        identity_path = Path(baseline.read_json(parent / "latest-inputs.json")["path"])
        identity = baseline.read_json(identity_path)
        before = source_inputs(root) | generated_inputs(root, variant)
        if before != baseline.read_json(baseline.check_artifact(identity["source"]["inputs"])):
            raise ValueError("candidate inputs changed after capture")
        for key in ("inputs", "snapshot", "patch"):
            baseline.check_artifact(identity["source"][key])
        record.update(candidate_identity=baseline.artifact(identity_path), tools=baseline.tools_identity(root))
        original = baseline.read_json(old_variant / "meta/tiny-r2-p2/baseline-artifacts.json")
        for key in ("inputs", "snapshot", "patch"):
            baseline.check_artifact(original["source"][key])
        for artifact in original["artifacts"].values():
            baseline.check_artifact(artifact)
        record["baseline_identity"] = baseline.artifact(old_variant / "meta/tiny-r2-p2/baseline-artifacts.json")
        record["inputs"] = {"baseline": consumed_files(old_variant), "candidate": consumed_files(variant)}
        for role, files in record["inputs"].items():
            for key in ("syn/yosys/result-synth.json", "sta/opensta/result-sta.json"):
                result = baseline.read_json(Path(files[key]["path"]))
                if result.get("status") != "passed" or result.get("exit_code") != 0:
                    raise ValueError(f"{role} lacks completed synthesis/STA")
            if role == "candidate":
                synth = baseline.read_json(Path(files["syn/yosys/result-synth.json"]["path"]))
                if datetime.fromisoformat(synth["started_at"]) < datetime.fromisoformat(identity["created_at"]):
                    raise ValueError("candidate synthesis predates its captured inputs")
        libraries = root / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref"
        script = root / "physical/smoke/sta/opensta/tiny_r2_feasibility.tcl"
        record["script"] = baseline.artifact(script)
        record["macro_views"] = {}
        for corner, (std, io, ram) in CORNERS.items():
            paths = [libraries / f"sg13g2_stdcell/lib/sg13g2_stdcell_{std}.lib",
                     libraries / f"sg13g2_io/lib/sg13g2_io_{io}.lib",
                     libraries / f"sg13g2_sram/lib/{MACRO}_{ram}.lib"]
            text = paths[2].read_text()
            record["macro_views"][corner] = {
                "libraries": [baseline.artifact(p) for p in paths],
                "explicit_minimum_period": bool(re.search(r"\b(?:minimum_period|min_period)\b", text)),
                "setup": "setup_rising" in text, "hold": "hold_rising" in text,
                "clock_to_output": "rising_edge" in text, "pulse_width": "min_pulse_width" in text,
                "temperature_pairing": ram + "; stdcell " + std,
            }
            for role, files in record["inputs"].items():
                original_sdc = Path(files["sta/opensta/retrosoc_core.sdc"]["path"]).read_text()
                for mhz in RATES:
                    point = directory / role / corner / str(mhz)
                    point.mkdir(parents=True)
                    sdc = point / "analysis.sdc"
                    baseline.atomic_write(sdc, candidate_sdc(original_sdc, mhz))
                    environment = {
                        "OPENSTA_TOP": "retrosoc_tiny_asic",
                        "OPENSTA_NETLIST": files["syn/yosys/out/retrosoc_tiny_asic_yosys.v"]["path"],
                        "OPENSTA_LIBERTY": str(paths[0]), "OPENSTA_LINK_LIBS": str(paths[1]),
                        "OPENSTA_SRAM_LIBS": str(paths[2]), "OPENSTA_SDC": str(sdc),
                        "OPENSTA_REPORT": str(point / "timing.rpt"),
                        "OPENSTA_METRICS": str(point / "timing_metrics.rpt"),
                        "TINY_R2_OUTPUT": str(point), "TINY_R2_CANDIDATE": str(int(role == "candidate")),
                    }
                    command = [sys.executable, str(root / "scripts/run_flow.py"), "--tool", "opensta-p2",
                               "--log", str(point / "sta.log"), "--result", str(point / "result.json")]
                    for key, value in environment.items():
                        command += ["--env", f"{key}={value}"]
                    command += ["--", record["tools"]["opensta"]["executable"]["path"],
                                "-no_init", "-exit", "-threads", "2", str(script)]
                    subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800)
                    log = (point / "sta.log").read_text()
                    if "TINY_R2_FEASIBILITY_PASS:" not in log or re.search(r"(?im)^Error:|\bFATAL\b", log):
                        raise ValueError(f"STA audit incomplete: {point}")
                    metrics = timing_metrics(point / "timing_metrics.rpt")
                    record["points"].append({"role": role, "corner": corner, "sys_mhz": mhz,
                                             "metrics": metrics,
                                             "sys_setup_path_slack_ns": path_slack(point / "sys-setup.rpt"),
                                             "sys_hold_path_slack_ns": path_slack(point / "sys-hold.rpt"),
                                             "reset_loads": reset_loads(point / "reset-loads.tsv", role == "candidate"),
                                             "timing": "failed" if any(v < 0 for v in metrics.values()) else "nonnegative_reported_slack",
                                             "artifacts": {p.name: baseline.artifact(p) for p in point.iterdir() if p.is_file()}})
                    baseline.dump(output, record)
                    print(f"{role} {corner} SYS={mhz} MHz: WNS={metrics['wns_max']} ns; not qualification", flush=True)
        if before != source_inputs(root) | generated_inputs(root, variant):
            raise ValueError("candidate inputs changed during feasibility")
        for files in record["inputs"].values():
            for artifact in files.values():
                baseline.check_artifact(artifact)
        for views in record["macro_views"].values():
            for artifact in views["libraries"]:
                baseline.check_artifact(artifact)
        for key in ("candidate_identity", "baseline_identity", "script"):
            baseline.check_artifact(record[key])
        for tool in record["tools"].values():
            baseline.check_artifact(tool["executable"])
        record["status"] = "completed"
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        print(f"Tiny P2 feasibility: {error}", file=sys.stderr)
    finally:
        baseline.dump(output, record)
    return int(record["status"] != "completed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--variant-root", type=Path, required=True)
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("capture")
    execute = subparsers.add_parser("run")
    execute.add_argument("--baseline-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        return capture(args) if args.action == "capture" else run(args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Tiny P2: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
