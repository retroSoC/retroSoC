#!/usr/bin/env python3
"""Initialize or assemble fail-closed APU-P9 evidence reports."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from apu_kws_coeff import validate_layout_manifest


REPORTS = (
    "coefficient-layout.json",
    "coefficient-lifecycle.json",
    "memo-equivalence.json",
    "numerical-latency.json",
    "memory-synthesis-ab.json",
    "physical.json",
)
ROOT = Path(__file__).resolve().parents[1]

REQUIRED_CHECKS = {
    REPORTS[1]: (
        "lp_admission",
        "unsupported_discovery",
        "cache_acl",
        "dma_backpressure",
        "payload_corruption",
        "readback_corruption",
        "partial_retry",
        "lock",
        "ownership",
        "hard_reset",
        "soft_reset",
        "resource_reset",
        "quiesce_load",
        "abort_every_state",
    ),
    REPORTS[2]: (
        "valid_v1_v2",
        "mutated_v1_v2",
        "duplicate_keys",
        "collisions",
        "full_wrap",
        "full_table",
        "deeper_call_bypass",
        "key_boundaries",
        "bitmap_boundaries",
        "interrupted_clear_insert",
        "verdict_equivalence",
        "first_error_equivalence",
        "visit_count_equivalence",
    ),
    REPORTS[3]: (
        "all_coefficients",
        "scalar_table_boundaries",
        "variable_backpressure",
        "no_double_commit",
        "no_stale_response",
        "mfcc_bit_exact",
        "layers_bit_exact",
        "full_1000_windows",
        "complete_window_before_successor",
        "concurrent_60s_zero_xrun",
    ),
    REPORTS[4]: (
        "configuration_matches",
        "revision_qualified",
        "candidate_synthesis_completed",
        "target_inferred_bits_zero",
        "apu_reduction_at_least_90_percent",
        "candidate_apu_bits_at_most_65536",
        "candidate_macro_inventory_76",
        "pass_timing_reported",
        "post_memory_inventory_reported",
        "peak_rss_measured_both",
        "candidate_peak_rss_lower",
        "synthesis_duration_measured_both",
        "candidate_duration_lower",
    ),
    REPORTS[5]: (
        "revision_qualified",
        "macro_inventory_76",
        "logic_macro_area_separate",
        "wns_nonnegative",
        "tns_zero",
        "hold_reported",
        "no_unconstrained_paths",
        "macro_views_complete",
        "netlist_models_complete",
    ),
}
BASELINE_REVISION = "0b73994772068e5fac00fb1a98f87f88ed121cdf"


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read JSON evidence {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"JSON evidence is not an object: {path}")
    return value


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="ascii")


def _full_revision(value: object) -> bool:
    return isinstance(value, str) and len(value) == 40 and all(
        character in "0123456789abcdef" for character in value.lower()
    )


def _require_artifacts(report: dict[str, Any], name: str) -> None:
    artifacts = report.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError(f"{name} passed report lacks named artifacts")
    missing = [
        key
        for key, value in artifacts.items()
        if not isinstance(value, str) or not Path(value).is_file()
    ]
    if missing:
        raise ValueError(f"{name} passed report has missing artifacts: {missing}")


def _require_passed_tests(report: dict[str, Any], name: str) -> None:
    tests = report.get("tests")
    if not isinstance(tests, list) or not tests or any(
        not isinstance(test, dict) or test.get("status") != "passed" for test in tests
    ):
        raise ValueError(f"{name} passed report lacks passed test records")


def _validate_memory_ab(report: dict[str, Any]) -> None:
    baseline = report.get("baseline")
    candidate = report.get("candidate")
    tool = report.get("tool_identity")
    if not isinstance(baseline, dict) or not isinstance(candidate, dict) or not isinstance(tool, dict):
        raise ValueError("memory-synthesis-ab.json lacks baseline/candidate/tool identity")
    if (
        baseline.get("revision") != BASELINE_REVISION
        or baseline.get("dirty") is not False
        or candidate.get("revision") != report.get("revision")
        or candidate.get("dirty") is not False
    ):
        raise ValueError("memory-synthesis-ab.json revisions are not frozen and clean")
    memory = candidate.get("memory")
    macros = candidate.get("macros")
    pass_timing = candidate.get("pass_timing")
    post_memory = candidate.get("post_memory")
    if (
        not isinstance(memory, dict)
        or memory.get("target_bits") != 0
        or not isinstance(memory.get("apu_bits"), int)
        or memory["apu_bits"] > 65536
        or not isinstance(macros, dict)
        or macros.get("apu_wrappers") != 76
        or not isinstance(pass_timing, dict)
        or any(pass_timing.get(name) is None for name in ("memory", "opt_dff", "abc", "total_ns"))
        or not isinstance(post_memory, dict)
        or not isinstance(post_memory.get("cell_types"), dict)
    ):
        raise ValueError("memory-synthesis-ab.json lacks the frozen memory/pass inventory")
    yosys_path = Path(str(tool.get("yosys_path", "")))
    yosys_sha = tool.get("yosys_sha256")
    if not yosys_path.is_file() or not isinstance(yosys_sha, str):
        raise ValueError("memory-synthesis-ab.json lacks the Yosys executable identity")
    if hashlib.sha256(yosys_path.read_bytes()).hexdigest() != yosys_sha:
        raise ValueError("memory-synthesis-ab.json Yosys executable SHA-256 does not match")
    if tool.get("read_slang_provider") != "yosys-executable":
        raise ValueError("memory-synthesis-ab.json does not identify the Slang provider")


def _validate_numerical(report: dict[str, Any]) -> None:
    accuracy = report.get("accuracy")
    concurrency = report.get("concurrency")
    latency = report.get("latency")
    if (
        not isinstance(accuracy, dict)
        or accuracy.get("windows") != 1000
        or not isinstance(accuracy.get("top1_correct"), int)
        or accuracy["top1_correct"] < 900
        or not isinstance(concurrency, dict)
        or concurrency.get("seconds_per_scenario", 0) < 60
        or sorted(concurrency.get("rates", [])) != [48000, 96000]
        or sorted(concurrency.get("precisions", [])) != [16, 24]
        or concurrency.get("xrun_count") != 0
        or not isinstance(latency, dict)
        or not isinstance(latency.get("maximum_window_cycles"), int)
        or latency["maximum_window_cycles"] > 4_800_000
    ):
        raise ValueError("numerical-latency.json lacks the frozen accuracy/latency/concurrency result")


def _validate_physical(report: dict[str, Any]) -> None:
    inventory = report.get("macro_inventory")
    area = report.get("area")
    timing = report.get("timing")
    if (
        not isinstance(inventory, dict)
        or inventory.get("wrappers") != 76
        or not isinstance(area, dict)
        or any(not isinstance(area.get(name), (int, float)) for name in ("logic_um2", "macro_um2", "total_um2"))
        or not isinstance(timing, dict)
        or not isinstance(timing.get("wns_ns"), (int, float))
        or timing["wns_ns"] < 0
        or timing.get("tns_ns") != 0
        or timing.get("unconstrained_paths") != 0
        or not isinstance(timing.get("hold"), dict)
    ):
        raise ValueError("physical.json lacks the frozen macro/area/timing result")


def _validate_passed(name: str, report: dict[str, Any]) -> None:
    if name == REPORTS[0]:
        if report.get("profile") != "configs/ci/ihp130.mk":
            raise ValueError("coefficient-layout.json does not use configs/ci/ihp130.mk")
        layout_source = Path(str(report.get("source", "")))
        apuc_source = Path(str(report.get("apuc_source", "")))
        if not layout_source.is_file() or not apuc_source.is_file():
            raise ValueError("coefficient-layout.json lacks its layout/APUC source artifacts")
        validate_layout_manifest(apuc_source.read_bytes(), _read_json(layout_source))
        return
    if report.get("schema_version") != 1 or report.get("phase") != "APU-P9":
        raise ValueError(f"{name} passed report lacks the APU-P9 schema identity")
    if report.get("profile") != "configs/ci/ihp130.mk":
        raise ValueError(f"{name} passed report does not use configs/ci/ihp130.mk")
    if not _full_revision(report.get("revision")) or report.get("dirty") is not False:
        raise ValueError(f"{name} passed report is not revision-qualified")
    checks = report.get("checks")
    required = REQUIRED_CHECKS[name]
    if not isinstance(checks, dict) or any(checks.get(check) is not True for check in required):
        raise ValueError(f"{name} passed report lacks one or more frozen checks")
    if name in (REPORTS[1], REPORTS[2]):
        _require_passed_tests(report, name)
    if name == REPORTS[2] and (
        report.get("baseline_revision") != BASELINE_REVISION
        or report.get("candidate_revision") != report.get("revision")
    ):
        raise ValueError("memo-equivalence.json revisions do not match the frozen comparison")
    if name == REPORTS[3]:
        _validate_numerical(report)
    elif name == REPORTS[4]:
        _validate_memory_ab(report)
    elif name == REPORTS[5]:
        _validate_physical(report)
    _require_artifacts(report, name)


def _initialize(args: argparse.Namespace) -> None:
    layout = _read_json(args.layout)
    try:
        apuc = args.apuc.read_bytes()
    except OSError as error:
        raise ValueError(f"cannot read APUC evidence {args.apuc}: {error}") from error
    validate_layout_manifest(apuc, layout)
    profile_path = args.profile.resolve()
    try:
        profile = profile_path.relative_to(ROOT).as_posix()
    except ValueError:
        profile = str(profile_path)
    layout["phase"] = "APU-P9"
    layout["profile"] = profile
    layout["status"] = "passed"
    layout["source"] = str(args.layout.resolve())
    layout["apuc_source"] = str(args.apuc.resolve())
    _write_json(args.output_dir / REPORTS[0], layout)
    requirements = {
        REPORTS[1]: "APUC admission, corruption, retry, lock, reset, quiesce and abort matrix",
        REPORTS[2]: "baseline versus macro memo verdict, first-error and visit-count equivalence",
        REPORTS[3]: "bit-exact coefficient, MFCC/layer/window and bounded-cycle qualification",
        REPORTS[4]: "same-input baseline/candidate inferred memory, runtime and peak-RSS comparison",
        REPORTS[5]: "76-wrapper area, WNS/TNS, unconstrained-path and macro-view accounting",
    }
    for name, requirement in requirements.items():
        destination = args.output_dir / name
        if not destination.exists():
            _write_json(
                destination,
                {
                    "schema_version": 1,
                    "phase": "APU-P9",
                    "status": "unrun",
                    "requirement": requirement,
                    "reason": "required qualifying run has not been supplied",
                },
            )


def _assemble(args: argparse.Namespace) -> None:
    sources: dict[str, Path] = {}
    for item in args.report:
        name, separator, raw_path = item.partition("=")
        if not separator or name not in REPORTS:
            raise ValueError(f"report must be NAME=PATH for one of {REPORTS}: {item}")
        sources[name] = Path(raw_path)
    missing = [name for name in REPORTS if name not in sources]
    if missing:
        raise ValueError(f"missing required P9 reports: {missing}")
    for name, source in sources.items():
        report = _read_json(source)
        status = report.get("status")
        if status not in ("passed", "unrun", "failed", "timed_out"):
            raise ValueError(f"{name} lacks a recognized fail-closed status")
        if status == "passed":
            _validate_passed(name, report)
        elif not isinstance(report.get("reason", report.get("failure")), str):
            raise ValueError(f"{name} {status} report lacks a reason/failure")
        report["source"] = str(source.resolve())
        _write_json(args.output_dir / name, report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    initialize = subparsers.add_parser("initialize")
    initialize.add_argument("--layout", type=Path, required=True)
    initialize.add_argument("--apuc", type=Path, required=True)
    initialize.add_argument("--profile", type=Path, required=True)
    initialize.add_argument("--output-dir", type=Path, required=True)
    initialize.set_defaults(handler=_initialize)
    assemble = subparsers.add_parser("assemble")
    assemble.add_argument("--report", action="append", default=[])
    assemble.add_argument("--output-dir", type=Path, required=True)
    assemble.set_defaults(handler=_assemble)
    args = parser.parse_args()
    try:
        args.handler(args)
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
