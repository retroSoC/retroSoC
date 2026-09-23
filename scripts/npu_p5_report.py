#!/usr/bin/env python3
"""Assemble NPU-P5 V013/V014 evidence from completed structured results."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REJECTED = re.compile(
    r"(?:\bFAIL(?:ED)?\b|\bFATAL\b|assertion failed|%Error|SIM_TEST_FAIL|SIM_TEST_TIMEOUT)",
    re.IGNORECASE,
)
DEPLOYMENT_CONTRACT = "npu-p5/1.0.1"
MODEL_SHA256 = {
    "kws": "aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae",
    "vww": "597a384c8c2c8a1276f04702f25013b7838f2f814f1ca7c174d295b73e3d6b7b",
}
RTL_IMPLEMENTATION_REQUIRED = {
    "rtl/ip/multimedia/npu_accumulator.sv",
    "rtl/ip/multimedia/npu_core.sv",
    "rtl/ip/multimedia/npu_dma.sv",
    "rtl/ip/multimedia/npu_job_decoder.sv",
    "rtl/ip/multimedia/npu_local_sram.sv",
    "rtl/ip/multimedia/npu_mac_array.sv",
    "rtl/ip/multimedia/npu_patch_packer.sv",
    "rtl/ip/multimedia/npu_pkg.sv",
    "rtl/ip/multimedia/npu_requantizer.sv",
    "rtl/ip/multimedia/npu_scheduler.sv",
    "rtl/ip/multimedia/npu_vector.sv",
    "scripts/npu_compiler.py",
    "scripts/npu_compiler_p0.py",
    "scripts/npu_executor.py",
    "scripts/npu_model.py",
    "scripts/npu_reference.py",
    "scripts/qualify_npu_p5.py",
    "tests/rtl/npu_operator_tb.sv",
}
P0_IMPLEMENTATION_REQUIRED = {
    "scripts/qualify_npu_p0.py",
    "scripts/npu_framework_reference.py",
    "scripts/npu_model.py",
    "scripts/npu_reference.py",
    "scripts/npu_compiler_p0.py",
    "scripts/npu_executor.py",
    "scripts/setup_npu_reference.py",
    "tests/cpp/npu_framework_reference.cc",
}


def load(path: Path) -> dict:
    if not path.is_file():
        raise ValueError(f"missing evidence: {path}")
    return json.loads(path.read_text())


def file_identity(path: Path) -> dict[str, int | str]:
    payload = path.read_bytes()
    return {"path": str(path), "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest()}


def verify_identity(identity: dict, *, path: Path | None = None) -> None:
    payload = path if path is not None else Path(identity["path"])
    if (not payload.is_file() or payload.stat().st_size != identity["bytes"] or
            hashlib.sha256(payload.read_bytes()).hexdigest() != identity["sha256"]):
        raise ValueError(f"artifact identity mismatch: {payload}")


def frozen_rtl_samples() -> dict[tuple[str, str], str]:
    kws = load(ROOT / "docs/ip/npu-kws-manifest.json")
    kws_hashes = {item["name"]: item["sha256"] for item in kws["inputs"]}
    vww_hashes = {}
    for line in (ROOT / "docs/ip/npu-vww-corpus.tsv").read_text().splitlines():
        _index, name, _jpeg, _label, _jpeg_sha, bin_sha = line.split("\t")
        vww_hashes[name] = bin_sha
    expected = {}
    for workload, manifest, hashes in (
        ("kws", kws, kws_hashes),
        ("vww", load(ROOT / "docs/ip/npu-vww-manifest.json"), vww_hashes),
    ):
        for name in manifest["rtl_sample_ids"]:
            expected[(workload, name)] = hashes[name]
    return expected


def validate_implementation(implementation: dict) -> None:
    if not RTL_IMPLEMENTATION_REQUIRED <= set(implementation):
        raise ValueError("RTL qualification lacks required implementation identities")
    for name, identity in implementation.items():
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"implementation name is not repository-relative: {name}")
        expected = (ROOT / name).resolve()
        if Path(identity.get("path", "")).resolve() != expected:
            raise ValueError(f"implementation path mismatch: {name}")
        verify_identity(identity, path=expected)


def validate_p0(report: dict) -> None:
    if (report.get("verdict") != "PASS" or report.get("skipped") != 0 or
            not report.get("acceptance_run")):
        raise ValueError("P0 dependency evidence is not a full zero-skip PASS")
    results = report.get("results", [])
    if Counter(item.get("workload") for item in results) != {"kws": 1, "vww": 1}:
        raise ValueError("P0 dependency evidence lacks both workloads")
    for item in results:
        if (item.get("inputs") != 1000 or not item.get("full_corpus") or
                item.get("layer_mismatches") != 0):
            raise ValueError(f"P0 workload is incomplete: {item.get('workload')}")
    implementation = report.get("implementation_sha256", {})
    if set(implementation) != P0_IMPLEMENTATION_REQUIRED:
        raise ValueError("P0 dependency evidence lacks required implementation identities")
    for name, digest in implementation.items():
        path = (ROOT / name).resolve()
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"P0 implementation identity mismatch: {name}")


def validate_required_command(result: dict, expected: list[str], label: str) -> None:
    if result.get("command") != expected:
        raise ValueError(f"{label} result command is not the required gate")


def validate_variant_path(manifest_path: Path, profile: str, digest: str) -> None:
    variant = manifest_path.resolve().parent.parent.name
    if not variant.startswith(f"{profile}-") or not variant.endswith(f"-{digest}"):
        raise ValueError(f"manifest path does not bind {profile} digest {digest}")


def validate_rtl_cases(cases: list[dict]) -> dict[tuple[str, str], dict]:
    expected_cases = frozen_rtl_samples()
    case_keys = [(case.get("workload"), case.get("input")) for case in cases]
    if len(cases) != 20 or len(set(case_keys)) != 20 or set(case_keys) != set(expected_cases):
        raise ValueError("RTL qualification does not contain ten cases per model")
    for case in cases:
        key = (case.get("workload"), case.get("input"))
        if case.get("source_input_sha256") != expected_cases[key]:
            raise ValueError(f"RTL case input hash is not frozen: {key[0]}/{key[1]}")
        if len(case.get("layer_sha256", [])) != case.get("descriptors"):
            raise ValueError(f"RTL case lacks per-layer hashes: {case.get('input')}")
        if set(case.get("artifacts", {})) != {"memory", "final", "write_trace"}:
            raise ValueError(f"RTL case artifact set is incomplete: {case.get('input')}")
        for identity in case["artifacts"].values():
            verify_identity(identity)
        if not case.get("plusargs"):
            raise ValueError(f"RTL case has no command arguments: {case.get('input')}")
    return {key: case for key, case in zip(case_keys, cases, strict=True)}


def validate_simulator_records(
    simulator: str, records: list[dict], case_map: dict[tuple[str, str], dict], prefix: list[str]
) -> None:
    record_keys = [(record.get("workload"), record.get("input")) for record in records]
    if len(records) != 20 or len(set(record_keys)) != 20 or set(record_keys) != set(case_map):
        raise ValueError(f"{simulator} did not execute all twenty cases")
    if not prefix:
        raise ValueError(f"{simulator} build lacks a run prefix")
    for record in records:
        if (record.get("status") != "PASS" or record.get("exit_code") != 0 or
                record.get("timed_out") or record.get("rejected_markers") or
                not record.get("command")):
            raise ValueError(f"failed or incomplete RTL case: {simulator}/{record.get('input')}")
        case = case_map[(record["workload"], record["input"])]
        if record["command"] != [*prefix, *case["plusargs"]]:
            raise ValueError(
                f"RTL command does not match case artifacts: {simulator}/{record.get('input')}"
            )
        verify_identity(record["log"])


def validate_deployment(directory: Path, *, workload: str, prefix: str) -> dict:
    manifest = load(directory / "npu.json")
    required_files = {
        "descriptors.bin", "weights.bin", "params.bin",
        f"{prefix}_npu.c", f"{prefix}_npu.h",
    }
    if (manifest.get("schema") != 1 or manifest.get("workload") != workload or
            manifest.get("numeric_profile") != 1 or
            manifest.get("source_model_sha256") != MODEL_SHA256[workload] or
            manifest.get("compiler", {}).get("contract") != DEPLOYMENT_CONTRACT or
            set(manifest.get("files", {})) != required_files):
        raise ValueError(f"invalid deployment schema: {directory}")
    for name, identity in manifest["files"].items():
        payload = directory / name
        if not payload.is_file() or payload.stat().st_size != identity["bytes"]:
            raise ValueError(f"deployment size mismatch: {payload}")
        if hashlib.sha256(payload.read_bytes()).hexdigest() != identity["sha256"]:
            raise ValueError(f"deployment hash mismatch: {payload}")
    return manifest


def validate_rtl(report: dict) -> None:
    required = ("profile", "config_digest", "pdk", "command", "git", "lock",
                "implementation", "coverage", "tools", "simulator_builds", "summary")
    if report.get("verdict") != "PASS" or any(key not in report for key in required):
        raise ValueError("RTL qualification lacks required provenance or PASS verdict")
    if report.get("verification_ids") != ["NPU-V014"]:
        raise ValueError("RTL qualification verification IDs are invalid")
    validate_implementation(report["implementation"])
    verify_identity(report["lock"], path=ROOT / "dependencies/dependencies.lock.json")
    cases = report.get("cases", [])
    if report.get("coverage", {}).get("skipped") != 0:
        raise ValueError("RTL qualification contains skipped coverage")
    case_map = validate_rtl_cases(cases)
    simulators = report.get("simulators", {})
    if set(simulators) != {"iverilog", "verilator"}:
        raise ValueError("RTL qualification must contain Icarus and Verilator")
    if set(report.get("simulator_builds", {})) != set(simulators):
        raise ValueError("RTL qualification lacks simulator build provenance")
    for simulator, records in simulators.items():
        prefix = report["simulator_builds"][simulator].get("run_prefix")
        validate_simulator_records(simulator, records, case_map, prefix)
    summary = report["summary"]
    if summary != {"cases": 20, "passes": 40, "failures": 0, "skipped": 0}:
        raise ValueError("RTL qualification summary is inconsistent")


def validate_build(manifest: dict, *, app: str, acceptance: str) -> None:
    config = manifest.get("configuration", {})
    if (manifest.get("schema_version") != 1 or config.get("PDK") != "IHP130" or
            config.get("APP") != app or config.get("NPU_P5_ACCEPTANCE") != acceptance or
            config.get("SYNTH") != "NONE" or config.get("STA") != "NONE"):
        raise ValueError(f"unexpected build manifest for APP={app}")


def same_deployment(reference: dict, candidate: dict, label: str) -> None:
    keys = ("source_model_sha256", "numeric_profile", "required_capability_mask",
            "required_opcode_mask", "arena_bytes", "files", "relocations", "steps",
            "preprocessing")
    if any(candidate.get(key) != reference.get(key) for key in keys):
        raise ValueError(f"{label} KWS deployment differs from the qualified package")


def firmware_identity(result: dict, firmware: Path) -> dict[str, int | str]:
    resolved = firmware.resolve()
    if str(resolved) not in result.get("command", []):
        raise ValueError(f"simulator command does not identify firmware: {resolved}")
    try:
        started = datetime.fromisoformat(result["started_at"]).timestamp()
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("simulator result lacks a valid start timestamp") from error
    # The managed builders can observe up to roughly 12 seconds of host clock
    # skew. Anything newer than that tolerance was not the retained run input.
    if resolved.stat().st_mtime > started + 30.0:
        raise ValueError(f"firmware changed after simulator start: {resolved}")
    identity = file_identity(resolved)
    identity["mtime"] = resolved.stat().st_mtime
    return identity


def validate_simulation_evidence(
    result_path: Path,
    check_path: Path,
    log_path: Path,
    firmware: Path,
    required_markers: list[str],
) -> tuple[dict, str, dict]:
    result = passed_result(result_path)
    check = passed_result(check_path)
    resolved_result = result_path.resolve()
    resolved_check = check_path.resolve()
    resolved_log = log_path.resolve()
    resolved_firmware = firmware.resolve()
    simulator_dir = resolved_result.parent
    emulator = (simulator_dir / "emu").resolve()
    expected_command = [
        str(emulator), "-i", str(resolved_firmware), "--fast-flash", "-t", "3600"
    ]
    if (result.get("schema_version") != 1 or result.get("tool") != "verilator-sim" or
            result.get("exit_code") != 0 or
            Path(result.get("cwd", "")).resolve() != simulator_dir or
            Path(result.get("log", "")).resolve() != resolved_log or
            result.get("command") != expected_command):
        raise ValueError("bare-metal simulation result provenance is invalid")
    if (check.get("schema_version") != 1 or
            Path(check.get("log", "")).resolve() != resolved_log or
            Counter(check.get("required_markers", [])) != Counter(required_markers) or
            check.get("missing_markers") != [] or check.get("rejected_matches") != []):
        raise ValueError("bare-metal simulation check is not bound to the required log verdict")
    log_text = resolved_log.read_text(errors="replace")
    missing = [marker for marker in required_markers if marker not in log_text]
    rejected = sorted({match.group(0) for match in REJECTED.finditer(log_text)})
    if missing or rejected:
        raise ValueError(
            f"bare-metal simulation log failed validation: missing={missing}, rejected={rejected}"
        )
    emulator_record = firmware_identity(result, emulator)
    firmware_record = firmware_identity(result, resolved_firmware)
    evidence = {
        "result_identity": file_identity(resolved_result),
        "check_identity": file_identity(resolved_check),
        "log": file_identity(resolved_log),
        "emulator": emulator_record,
        "firmware": firmware_record,
        "required_markers": required_markers,
    }
    return result, log_text, evidence


def passed_result(path: Path) -> dict:
    result = load(path)
    if result.get("status") != "passed" or (
        "exit_code" in result and result["exit_code"] != 0
    ):
        raise ValueError(f"failed structured result: {path}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kws", type=Path, required=True)
    parser.add_argument("--vww", type=Path, required=True)
    parser.add_argument("--host-result", type=Path, required=True)
    parser.add_argument("--c-quality-result", type=Path, required=True)
    parser.add_argument("--p0-report", type=Path, required=True)
    parser.add_argument("--rtl-report", type=Path, required=True)
    parser.add_argument("--build-manifest", type=Path, required=True)
    parser.add_argument("--config-digest", required=True)
    parser.add_argument("--lp-result", type=Path, required=True)
    parser.add_argument("--lp-check", type=Path, required=True)
    parser.add_argument("--lp-log", type=Path, required=True)
    parser.add_argument("--lp-manifest", type=Path, required=True)
    parser.add_argument("--lp-config-digest", required=True)
    parser.add_argument("--lp-kws", type=Path, required=True)
    parser.add_argument("--lp-firmware", type=Path, required=True)
    parser.add_argument("--hp-result", type=Path, required=True)
    parser.add_argument("--hp-check", type=Path, required=True)
    parser.add_argument("--hp-log", type=Path, required=True)
    parser.add_argument("--hp-manifest", type=Path, required=True)
    parser.add_argument("--hp-config-digest", required=True)
    parser.add_argument("--hp-kws", type=Path, required=True)
    parser.add_argument("--hp-firmware", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = {
        "schema": 1, "phase": "NPU-P5", "verification_ids": ["NPU-V013", "NPU-V014"],
        "verdict": "FAIL", "command": [sys.executable, *sys.argv],
        "implementation": {
            "scripts/npu_p5_report.py": file_identity(Path(__file__).resolve()),
            "scripts/qualify_npu_p5.py": file_identity(
                Path(__file__).resolve().with_name("qualify_npu_p5.py")
            ),
        },
    }
    try:
        deployments = {
            "kws": validate_deployment(args.kws, workload="kws", prefix="kws"),
            "vww": validate_deployment(args.vww, workload="vww", prefix="vww"),
        }
        lp_kws = validate_deployment(args.lp_kws, workload="kws", prefix="kws")
        hp_kws = validate_deployment(args.hp_kws, workload="kws", prefix="kws")
        same_deployment(deployments["kws"], lp_kws, "LP")
        same_deployment(deployments["kws"], hp_kws, "HP")
        host = passed_result(args.host_result)
        c_quality = passed_result(args.c_quality_result)
        p0 = load(args.p0_report)
        validate_p0(p0)
        rtl = load(args.rtl_report)
        validate_rtl(rtl)
        build_manifest = load(args.build_manifest)
        lp_manifest = load(args.lp_manifest)
        hp_manifest = load(args.hp_manifest)
        validate_build(build_manifest, app="bringup", acceptance="NO")
        validate_build(lp_manifest, app="ci_smoke", acceptance="YES")
        validate_build(hp_manifest, app="hp_boot", acceptance="YES")
        validate_variant_path(args.build_manifest, build_manifest["profile"], args.config_digest)
        validate_variant_path(args.lp_manifest, lp_manifest["profile"], args.lp_config_digest)
        validate_variant_path(args.hp_manifest, hp_manifest["profile"], args.hp_config_digest)
        revisions = {item["repository"]["commit"]
                     for item in (build_manifest, lp_manifest, hp_manifest)}
        dirty_states = {item["repository"]["dirty"]
                        for item in (build_manifest, lp_manifest, hp_manifest)}
        locks = {item["dependency_lock"]["sha256"]
                 for item in (build_manifest, lp_manifest, hp_manifest)}
        if len(revisions) != 1 or len(dirty_states) != 1 or len(locks) != 1:
            raise ValueError("build manifests disagree on revision or dependency lock")
        revision = next(iter(revisions))
        lock_sha256 = next(iter(locks))
        if (rtl["profile"] != build_manifest["profile"] or
                rtl["config_digest"] != args.config_digest or
                rtl["pdk"] != build_manifest["configuration"]["PDK"] or
                rtl["git"]["revision"] != revision or
                rtl["lock"]["sha256"] != lock_sha256):
            raise ValueError("RTL report provenance disagrees with the selected build")
        for deployment in (deployments["kws"], deployments["vww"]):
            if deployment["compiler"]["git_revision"] != revision:
                raise ValueError("deployment compiler revision disagrees with the build")
        validate_required_command(host, [
            "python3", "-m", "pytest", "-q",
            str(ROOT / "tests/test_npu_compiler.py"),
            str(ROOT / "tests/test_npu_executor.py"),
            str(ROOT / "tests/test_npu_register_parity.py"),
        ], "host")
        validate_required_command(c_quality, [
            "make", "sw-format-check", "sw-policy-check", "sw-host-test"
        ], "C quality")
        lp, lp_log, lp_evidence = validate_simulation_evidence(
            args.lp_result, args.lp_check, args.lp_log, args.lp_firmware,
            ["NPU_P5_LP model=kws", "SIM_TEST_PASS code=0"],
        )
        hp, hp_log, hp_evidence = validate_simulation_evidence(
            args.hp_result, args.hp_check, args.hp_log, args.hp_firmware,
            ["HP_NPU_PASS", "SIM_TEST_PASS code=0"],
        )
        marker = re.search(
            r"NPU_P5_LP model=kws active=(\d+) read=(\d+) write=(\d+) softmax=(\d+)", lp_log
        )
        if marker is None:
            raise ValueError("bare-metal log markers are incomplete")
        report.update({
            "verdict": "PASS",
            "provenance": {
                "git_revision": revision, "git_dirty": next(iter(dirty_states)),
                "dependency_lock_sha256": lock_sha256,
                "profile": build_manifest["profile"], "config_digest": args.config_digest,
                "pdk": build_manifest["configuration"]["PDK"],
                "tools": build_manifest["tools"],
                "lp": {"profile": lp_manifest["profile"],
                       "config_digest": args.lp_config_digest},
                "hp": {"profile": hp_manifest["profile"],
                       "config_digest": args.hp_config_digest},
            },
            "deployments": {name: {
                "path": str(path), "source_model_sha256": deployments[name]["source_model_sha256"],
                "arena_bytes": deployments[name]["arena_bytes"],
                "files": deployments[name]["files"],
                "preprocessing": deployments[name]["preprocessing"],
                "cpu_steps": [step for step in deployments[name]["steps"] if step["kind"] == "cpu"],
            } for name, path in (("kws", args.kws), ("vww", args.vww))},
            "host": {"path": str(args.host_result), "identity": file_identity(args.host_result),
                     "command": host["command"]},
            "c_quality": {"path": str(args.c_quality_result),
                          "identity": file_identity(args.c_quality_result),
                          "command": c_quality["command"]},
            "p0": {"path": str(args.p0_report), "identity": file_identity(args.p0_report),
                   "implementation_sha256": p0["implementation_sha256"]},
            "rtl": {"path": str(args.rtl_report), "identity": file_identity(args.rtl_report),
                    "simulators": {
                name: len(cases) for name, cases in rtl["simulators"].items()},
                "model_inputs": len(rtl["cases"])},
            "lp": {"result": str(args.lp_result), "check": str(args.lp_check),
                "command": lp["command"], "active_cycles": int(marker.group(1)),
                "dma_read_bytes": int(marker.group(2)), "dma_write_bytes": int(marker.group(3)),
                "softmax_cycles": int(marker.group(4)),
                **lp_evidence},
            "hp": {"result": str(args.hp_result), "check": str(args.hp_check),
                "command": hp["command"], "mode": "polling-zicbom",
                **hp_evidence},
            "summary": {
                "required_checks": 47,
                "passes": 47,
                "failures": 0,
                "blocked": 0,
                "skipped": 0,
                "breakdown": {
                    "deployments": 2,
                    "p0": 1,
                    "host": 1,
                    "c_quality": 1,
                    "rtl_simulations": 40,
                    "lp_bare_metal": 1,
                    "hp_bare_metal": 1,
                },
            },
            "constraints": {"synthesis": "DEFERRED_TO_P6", "sta": "DEFERRED_TO_P6",
                            "netlist": "DEFERRED_TO_P6"},
        })
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        report["error"] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"NPU-P5 qualification: {report['verdict']} ({args.output})")
    return 0 if report["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
