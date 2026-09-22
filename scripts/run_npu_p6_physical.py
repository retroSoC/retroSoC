#!/usr/bin/env python3
"""Run and validate isolated-NPU plus full-PRODUCT IHP130 physical evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "configs/ci/ihp130.mk"
SRAM_MACRO = "RM_IHPSG13_1P_1024x32_c2_bm_bist"
LATCH = re.compile(r"(?:\$dlatch|\blatch inferred)", re.IGNORECASE)
BLACKBOX = re.compile(r"(?:unresolved|unknown module)", re.IGNORECASE)


def identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {
        "path": str(path.resolve()),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"physical evidence is not an object: {path}")
    return data


def make_command(timestamp: str, *targets: str) -> list[str]:
    return [
        "make",
        f"CONFIG={CONFIG}",
        "SIMU=IVERILOG",
        "SYNTH=YOSYS",
        "STA=OPENSTA",
        "SYNTH_RECIPE=balanced",
        f"BUILD_TIMESTAMP={timestamp}",
        *targets,
    ]


def run(command: list[str], *, log: Path) -> None:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        env={**os.environ, "CCACHE_DISABLE": "1"},
    )
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"P6 physical command failed: {log}")


def variant_root(timestamp: str) -> Path:
    completed = subprocess.run(
        make_command(timestamp, "-s", "config"),
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"failed to resolve P6 physical variant\n{completed.stdout}")
    match = re.search(r"(?m)^VARIANT_ROOT\s+(.+)$", completed.stdout)
    if match is None:
        raise ValueError("P6 physical config omitted VARIANT_ROOT")
    return Path(match.group(1)).resolve()


def timing_metrics(path: Path) -> dict[str, float]:
    values: dict[str, float] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        name, separator, value = line.partition("=")
        if separator and name in {"wns_min", "wns_max", "tns_min", "tns_max"}:
            values[name] = float(value)
    if set(values) != {"wns_min", "wns_max", "tns_min", "tns_max"}:
        raise ValueError("PRODUCT STA did not report all WNS/TNS metrics")
    if values["wns_max"] < 0.0 or values["tns_max"] != 0.0:
        raise ValueError("PRODUCT setup timing did not close")
    if values["wns_min"] < 0.0 or values["tns_min"] != 0.0:
        raise ValueError("PRODUCT hold timing did not close")
    return values


def npu_macro_count(netlist: Path) -> int:
    text = netlist.read_text(encoding="utf-8", errors="replace")
    count = 0
    for match in re.finditer(r"(?ms)^module\s+([^\s(]+).*?^endmodule", text):
        module_name = match.group(1).lower()
        if "npu" in module_name and "tc_sram_1024x32" in module_name:
            count += match.group(0).count(f"{SRAM_MACRO} u_mem")
    return count


def validate_result(path: Path) -> dict[str, Any]:
    result = load(path)
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        raise ValueError(f"required physical flow failed: {path}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--isolated-report", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--build-timestamp", default=datetime.now().astimezone().strftime("%Y-%m-%d-%H-%M")
    )
    parser.add_argument("--reuse-product", action="store_true", help="reuse existing PRODUCT flow")
    args = parser.parse_args()
    isolated = load(args.isolated_report)
    if (
        isolated.get("verdict") != "PASS"
        or isolated.get("sram_macro_count") != 16
        or isolated.get("verification_ids") != ["NPU-V017", "NPU-V018"]
    ):
        raise ValueError("isolated NPU synthesis/STA/netlist evidence is incomplete")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    variant = variant_root(args.build_timestamp)
    if not args.reuse_product:
        run(
            make_command(
                args.build_timestamp,
                "manifest",
                "synth",
                "sta",
                "check-warnings",
                "metrics",
                "check-metrics",
            ),
            log=output / "product-physical.log",
        )
    manifest_path = variant / "meta/manifest.json"
    synth_result_path = variant / "syn/yosys/result-synth.json"
    sta_result_path = variant / "sta/opensta/result-sta.json"
    warning_path = variant / "meta/warnings.json"
    metrics_path = variant / "meta/metrics.json"
    netlist = variant / "syn/yosys/out/retrosoc_asic_yosys.v"
    for required in (
        manifest_path,
        synth_result_path,
        sta_result_path,
        warning_path,
        metrics_path,
        netlist,
    ):
        if not required.is_file():
            raise ValueError(f"missing PRODUCT physical artifact: {required}")
    synth_result = validate_result(synth_result_path)
    sta_result = validate_result(sta_result_path)
    manifest = load(manifest_path)
    config = manifest.get("configuration", {})
    expected_config = {
        "MINI_MODE": "PRODUCT",
        "PDK": "IHP130",
        "HAVE_HP": "YES",
        "HAVE_SRAM_MACRO": "YES",
        "EXT_CLK_HZ": "72000000",
        "SYNTH": "YOSYS",
        "STA": "OPENSTA",
        "SYNTH_RECIPE": "balanced",
    }
    if any(config.get(name) != value for name, value in expected_config.items()):
        raise ValueError("PRODUCT physical configuration differs from the P6 contract")
    warnings = load(warning_path)
    if warnings.get("status") != "passed" or warnings.get("failed_tools"):
        raise ValueError("PRODUCT warning review did not pass")
    metrics = load(metrics_path)
    synthesis = metrics.get("synthesis", {})
    if synthesis.get("top_area", 0) <= 0 or synthesis.get("top_cells", 0) <= 0:
        raise ValueError("PRODUCT metrics omit positive area or cell count")
    timing = timing_metrics(variant / "sta/opensta/timing_metrics.rpt")
    synth_log = variant / "syn/yosys/retrosoc_asic.log"
    synth_text = synth_log.read_text(encoding="utf-8", errors="replace")
    suspicious = [
        line
        for line in synth_text.splitlines()
        if (LATCH.search(line) or BLACKBOX.search(line))
        and "PROC_DLATCH pass" not in line
        and "no latch inferred" not in line.lower()
    ]
    if suspicious:
        raise ValueError(f"PRODUCT synthesis reported latches or unresolved black boxes: {suspicious[:3]}")
    product_npu_macros = npu_macro_count(netlist)
    if product_npu_macros != 16:
        raise ValueError(f"PRODUCT netlist contains {product_npu_macros} NPU SRAM macros, expected 16")
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V017"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "profile": "configs/ci/ihp130.mk",
        "target_frequency_hz": 72_000_000,
        "product_reused": args.reuse_product,
        "implementation": {
            name: identity(ROOT / name)
            for name in (
                "scripts/run_npu_p6_physical.py",
                "physical/smoke/syn/yosys/script/synth.tcl",
                "physical/smoke/sta/opensta/opensta.tcl",
                "physical/smoke/sta/opensta/generate_sdc.py",
            )
        },
        "isolated": identity(args.isolated_report),
        "product": {
            "variant_root": str(variant),
            "manifest": identity(manifest_path),
            "synthesis_result": {**identity(synth_result_path), "duration_seconds": synth_result.get("duration_seconds")},
            "sta_result": {**identity(sta_result_path), "duration_seconds": sta_result.get("duration_seconds")},
            "warnings": identity(warning_path),
            "metrics": identity(metrics_path),
            "netlist": identity(netlist),
            "area_um2": synthesis["top_area"],
            "cells": synthesis["top_cells"],
            "npu_sram_macros": product_npu_macros,
            "timing": timing,
        },
        "summary": {"required_checks": 2, "passes": 2, "failures": 0, "skipped": 0},
        "verdict": "PASS",
    }
    report_path = output / "qualification-p6-physical.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 physical qualification: PASS ({report_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
