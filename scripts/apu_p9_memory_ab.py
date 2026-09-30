#!/usr/bin/env python3
"""Compare revision-qualified APU-P9 baseline/candidate synthesis artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any


BASELINE_REVISION = "0b73994772068e5fac00fb1a98f87f88ed121cdf"
TARGET_MODULES = (
    "apu_kws_engine",
    "apu_kws_model_loader",
    "apu_microcode_loader",
    "apu_kws_coeff_store",
    "apu_proof_memo",
)
APU_PATH_MARKER = ".u_apb4_apu."
REQUIRED_CONFIGURATION = {
    "PDK": "IHP130",
    "APU_ENABLE_P7": "YES",
    "HAVE_SRAM_MACRO": "YES",
    "SYNTH": "YOSYS",
}


def _one(root: Path, pattern: str) -> Path:
    matches = sorted(root.glob(pattern))
    if len(matches) != 1:
        raise ValueError(f"expected one {pattern} below {root}, found {len(matches)}")
    return matches[0]


def _json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _memory_inventory(path: Path) -> dict[str, Any]:
    report = _json(path)
    modules = report.get("modules")
    if not isinstance(modules, dict):
        raise ValueError(f"Yosys stat report lacks modules: {path}")
    rows: list[dict[str, Any]] = []
    for name, values in modules.items():
        if not isinstance(values, dict):
            continue
        bits = int(values.get("num_memory_bits", 0))
        memories = int(values.get("num_memories", 0))
        if bits == 0 and memories == 0:
            continue
        rows.append({"module": name, "memories": memories, "bits": bits})
    apu_rows = [row for row in rows if APU_PATH_MARKER in row["module"]]
    target_rows = [
        row for row in apu_rows if any(name in row["module"] for name in TARGET_MODULES)
    ]
    return {
        "artifact": str(path.resolve()),
        "whole_soc_bits": sum(row["bits"] for row in rows),
        "apu_bits": sum(row["bits"] for row in apu_rows),
        "target_bits": sum(row["bits"] for row in target_rows),
        "apu_rows": sorted(apu_rows, key=lambda row: (-row["bits"], row["module"])),
        "target_rows": sorted(target_rows, key=lambda row: (-row["bits"], row["module"])),
    }


def _logic_inventory(path: Path) -> dict[str, Any]:
    report = _json(path)
    design = report.get("design")
    if not isinstance(design, dict):
        raise ValueError(f"post-memory report lacks design statistics: {path}")
    cell_types = design.get("num_cells_by_type")
    if not isinstance(cell_types, dict):
        raise ValueError(f"post-memory report lacks cell types: {path}")
    normalized = {str(name): int(count) for name, count in cell_types.items()}
    return {
        "artifact": str(path.resolve()),
        "cells": int(design.get("num_cells", sum(normalized.values()))),
        "flops": sum(count for name, count in normalized.items() if "DFF" in name.upper()),
        "muxes": sum(count for name, count in normalized.items() if "MUX" in name.upper()),
        "cell_types": normalized,
    }


def _pass_timing(path: Path) -> dict[str, Any]:
    report = _json(path)
    passes = report.get("passes")
    if not isinstance(passes, dict) or not isinstance(report.get("total_ns"), int):
        raise ValueError(f"Yosys performance report is incomplete: {path}")
    timings: dict[str, Any] = {
        "artifact": str(path.resolve()),
        "total_ns": report["total_ns"],
        "generator": report.get("generator"),
    }
    for name in ("memory", "opt_dff", "abc"):
        entry = passes.get(name)
        timings[name] = int(entry["runtime_ns"]) if isinstance(entry, dict) and "runtime_ns" in entry else None
    return timings


def _macro_inventory(path: Path) -> dict[str, Any]:
    instances = [line.strip().replace("/", ".") for line in path.read_text().splitlines() if line.strip()]
    apu = [instance for instance in instances if APU_PATH_MARKER in instance]
    classes = {
        "control_store": sum(".u_control_store." in value for value in apu),
        "codec_common_data": sum(".u_local_sram." in value for value in apu),
        "kws_model_scratch": sum(".u_kws_sram_client." in value for value in apu),
        "loader_path_stack": sum(
            (".u_microcode_loader." in value) and (".u_proof_memo." not in value) for value in apu
        ),
        "verifier_memo": sum(".u_proof_memo." in value for value in apu),
        "coefficient_store": sum(".u_kws_coeff_store." in value for value in apu),
    }
    return {
        "artifact": str(path.resolve()),
        "apu_wrappers": len(apu),
        "classes": classes,
        "instances": apu,
    }


def _variant(root: Path) -> dict[str, Any]:
    pre_memory_path = _one(root, "syn/yosys/rpt/*_pre_memory.json")
    pre_tech_path = _one(root, "syn/yosys/rpt/*_pre_tech.json")
    macro_path = _one(root, "syn/yosys/rpt/*_macros.rpt")
    perf_path = _one(root, "syn/yosys/yosys-perf.json")
    result_path = _one(root, "syn/yosys/result-synth.json")
    manifest_path = _one(root, "meta/manifest.json")
    memory = _memory_inventory(pre_memory_path)
    result = _json(result_path)
    manifest = _json(manifest_path)
    repository = manifest.get("repository")
    if not isinstance(repository, dict):
        raise ValueError(f"manifest lacks repository identity: {manifest_path}")
    return {
        "root": str(root.resolve()),
        "memory": memory,
        "post_memory": _logic_inventory(pre_tech_path),
        "pass_timing": _pass_timing(perf_path),
        "synthesis": {
            "status": result.get("status"),
            "exit_code": result.get("exit_code"),
            "duration_seconds": result.get("duration_seconds"),
            "peak_rss_kib": result.get("peak_rss_kib"),
            "result": str(result_path.resolve()),
        },
        "macros": _macro_inventory(macro_path),
        "manifest": manifest,
        "revision": repository.get("commit"),
        "dirty": repository.get("dirty"),
        "artifacts": {
            "pre_memory": str(pre_memory_path.resolve()),
            "pre_tech": str(pre_tech_path.resolve()),
            "macros": str(macro_path.resolve()),
            "yosys_perf": str(perf_path.resolve()),
            "synthesis_result": str(result_path.resolve()),
            "manifest": str(manifest_path.resolve()),
        },
    }


def _configuration_digest(variant: dict[str, Any]) -> Any:
    manifest = variant.get("manifest")
    if not isinstance(manifest, dict):
        return None
    comparable = {
        "configuration": manifest.get("configuration"),
        "dependency_lock": manifest.get("dependency_lock"),
        "tools": manifest.get("tools"),
    }
    if any(value is None for value in comparable.values()):
        return None
    return json.dumps(comparable, sort_keys=True, separators=(",", ":"))


def _configuration_is_frozen(variant: dict[str, Any]) -> bool:
    configuration = variant["manifest"].get("configuration")
    return (
        variant["manifest"].get("profile") == "ihp130"
        and isinstance(configuration, dict)
        and all(configuration.get(name) == value for name, value in REQUIRED_CONFIGURATION.items())
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-root", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--yosys", type=Path, default=None)
    args = parser.parse_args()
    try:
        baseline = _variant(args.baseline_root)
        candidate = _variant(args.candidate_root)
    except ValueError as error:
        parser.error(str(error))

    baseline_bits = baseline["memory"]["apu_bits"]
    candidate_bits = candidate["memory"]["apu_bits"]
    reduction = 0.0 if baseline_bits == 0 else 1.0 - (candidate_bits / baseline_bits)
    expected_macros = {
        "control_store": 8,
        "codec_common_data": 12,
        "kws_model_scratch": 16,
        "loader_path_stack": 8,
        "verifier_memo": 17,
        "coefficient_store": 15,
    }
    baseline_digest = _configuration_digest(baseline)
    candidate_digest = _configuration_digest(candidate)
    baseline_duration = baseline["synthesis"]["duration_seconds"]
    candidate_duration = candidate["synthesis"]["duration_seconds"]
    yosys_path = args.yosys
    if yosys_path is None:
        resolved_yosys = shutil.which("yosys")
        if resolved_yosys is None:
            parser.error("yosys executable is required to record its SHA-256")
        yosys_path = Path(resolved_yosys)
    if not yosys_path.is_file():
        parser.error(f"yosys executable does not exist: {yosys_path}")
    baseline_passes = baseline["pass_timing"]
    candidate_passes = candidate["pass_timing"]
    revision_qualified = (
        baseline["revision"] == BASELINE_REVISION
        and candidate["revision"] != BASELINE_REVISION
        and isinstance(candidate["revision"], str)
        and len(candidate["revision"]) == 40
        and baseline["dirty"] is False
        and candidate["dirty"] is False
    )
    checks = {
        "configuration_matches": baseline_digest is not None
        and baseline_digest == candidate_digest
        and _configuration_is_frozen(baseline)
        and _configuration_is_frozen(candidate),
        "revision_qualified": revision_qualified,
        "candidate_synthesis_completed": candidate["synthesis"]["status"] == "passed",
        "target_inferred_bits_zero": candidate["memory"]["target_bits"] == 0,
        "apu_reduction_at_least_90_percent": reduction >= 0.90,
        "candidate_apu_bits_at_most_65536": candidate_bits <= 65536,
        "candidate_macro_inventory_76": candidate["macros"]["apu_wrappers"] == 76
        and candidate["macros"]["classes"] == expected_macros,
        "pass_timing_reported": all(candidate_passes[name] is not None for name in ("memory", "opt_dff", "abc"))
        and baseline_passes["memory"] is not None
        and baseline_passes["opt_dff"] is not None,
        "post_memory_inventory_reported": baseline["post_memory"]["cells"] > 0
        and candidate["post_memory"]["cells"] > 0,
        "peak_rss_measured_both": baseline["synthesis"]["peak_rss_kib"] is not None
        and candidate["synthesis"]["peak_rss_kib"] is not None,
        "candidate_peak_rss_lower": baseline["synthesis"]["peak_rss_kib"] is not None
        and candidate["synthesis"]["peak_rss_kib"] is not None
        and candidate["synthesis"]["peak_rss_kib"] < baseline["synthesis"]["peak_rss_kib"],
        "synthesis_duration_measured_both": baseline_duration is not None
        and candidate_duration is not None,
        "candidate_duration_lower": baseline_duration is not None
        and candidate_duration is not None
        and candidate_duration < baseline_duration,
    }
    report = {
        "schema_version": 1,
        "phase": "APU-P9",
        "profile": "configs/ci/ihp130.mk",
        "revision": candidate["revision"],
        "dirty": candidate["dirty"],
        "status": "passed" if all(checks.values()) else "failed",
        "reason": None if all(checks.values()) else "one or more frozen APU-P9 A/B checks failed",
        "baseline": baseline,
        "candidate": candidate,
        "apu_inferred_reduction": reduction,
        "expected_candidate_macro_classes": expected_macros,
        "tool_identity": {
            "yosys_path": str(yosys_path.resolve()),
            "yosys_sha256": _sha256(yosys_path),
            "read_slang_provider": "yosys-executable",
        },
        "artifacts": {
            **{f"baseline_{name}": path for name, path in baseline["artifacts"].items()},
            **{f"candidate_{name}": path for name, path in candidate["artifacts"].items()},
        },
        "checks": checks,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="ascii")
    print(f"APU-P9 memory A/B: {report['status']} ({args.output})")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
