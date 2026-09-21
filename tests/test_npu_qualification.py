"""Qualification must reject common-mode numerical errors and incomplete runs."""
import json
import hashlib
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import qualify_npu_p0 as qualification  # noqa: E402
import qualify_npu_p5 as p5_rtl  # noqa: E402
import npu_framework_reference as framework  # noqa: E402
import npu_p5_report as p5_report  # noqa: E402


def test_shared_wrong_result_is_not_acceptance():
    # Old VWW output accepted by the two Python paths, rejected by pinned TFLite.
    wrong, right = bytes((128, 127)), bytes((137, 119))
    findings = qualification.compare_layers([wrong], [wrong], [right])
    assert {item["path"] for item in findings} == {"executor", "reference"}
    assert all(item["first_byte"] == 0 for item in findings)
    assert qualification.compare_layers([right], [right], [right]) == []


def test_corrupted_intermediate_and_missing_layers():
    assert qualification.compare_layers([b"x", b"b"], [b"a", b"b"], [b"a", b"b"])[0]["layer"] == 0
    with pytest.raises(RuntimeError, match="layer count"):
        qualification.compare_layers([b"a"], [], [b"a"])
    with pytest.raises(RuntimeError):
        qualification.compare_layers([], [], [])


def test_missing_reference_records_blocked(tmp_path, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["qualify_npu_p0.py", "--output-dir", str(tmp_path)])
    def blocked():
        raise qualification.QualificationBlocked("missing required oracle")
    monkeypatch.setattr(qualification, "_check_assets", blocked)
    assert qualification.main() == 2
    report = json.loads((tmp_path / "qualification-p0.json").read_text())
    assert report["verdict"] == "BLOCKED" and report["skipped"] == 0


@pytest.mark.parametrize("limit", ["0", "-1", "1001"])
def test_invalid_limit_is_rejected(tmp_path, monkeypatch, limit):
    monkeypatch.setattr(sys, "argv", ["qualify_npu_p0.py", "--output-dir", str(tmp_path),
                                     "--limit", limit])
    with pytest.raises(SystemExit) as error:
        qualification.main()
    assert error.value.code == 2


def test_missing_compiler_fails(tmp_path, monkeypatch):
    monkeypatch.setattr(framework, "checked_sources", lambda: {})
    with pytest.raises(framework.OracleError, match="missing host"):
        framework.build_oracle(tmp_path, "no-such-npu-cxx")


@pytest.mark.parametrize("dirty,revision", [("", "wrong"), (" M modified.h", "expected")])
def test_stale_or_dirty_source_fails(tmp_path, monkeypatch, dirty, revision):
    (tmp_path / "dependencies").mkdir()
    (tmp_path / "dependencies/dependencies.lock.json").write_text(json.dumps({
        "sources": {name: {"destination": name, "revision": "expected"}
                    for name in framework.SOURCES}}))
    monkeypatch.setattr(framework, "ROOT", tmp_path)
    monkeypatch.setattr(framework.subprocess, "check_output",
                        lambda args, **kwargs: dirty if "status" in args else revision)
    with pytest.raises(framework.OracleError, match="stale or dirty"):
        framework.checked_sources()


@pytest.mark.parametrize("limit,mismatch,verdict,code", [
    (None, 0, "PASS", 0), ("1", 0, "SMOKE-ONLY", 1),
    (None, 1, "FAIL", 1), ("1", 1, "FAIL", 1),
])
def test_main_verdict_requires_full_matching_corpora(tmp_path, monkeypatch,
                                                  limit, mismatch, verdict, code):
    from types import SimpleNamespace

    argv = ["qualify_npu_p0.py", "--output-dir", str(tmp_path)]
    if limit is not None:
        argv += ["--limit", limit]
    monkeypatch.setattr(sys, "argv", argv)
    monkeypatch.setattr(qualification, "_check_assets", lambda: None)
    monkeypatch.setattr(qualification, "build_oracle", lambda *args: (tmp_path / "oracle", {}))
    monkeypatch.setattr(qualification, "_load_kws_corpus", lambda: [])
    monkeypatch.setattr(qualification, "_load_vww_corpus", lambda: [])
    for name in ("load_kws_model", "load_vww_model"):
        monkeypatch.setattr(qualification.npu_model, name,
                            lambda: SimpleNamespace(main_graph=lambda: None))
    for name in ("compile_kws", "compile_vww"):
        monkeypatch.setattr(qualification.npu_compiler_p0, name, lambda: None)
    monkeypatch.setattr(qualification.npu_compiler_p0, "write_artifacts", lambda *args: None)
    monkeypatch.setattr(qualification, "FrameworkOracle", lambda *args: None)
    monkeypatch.setattr(qualification, "_qualify_model", lambda workload, *args, **kwargs: {
        "workload": workload, "inputs": 1000 if limit is None else 1,
        "layer_mismatches": mismatch, "accuracy": {"correct": 1, "total": 1, "ratio": 1.0},
    })
    assert qualification.main() == code
    assert json.loads((tmp_path / "qualification-p0.json").read_text())["verdict"] == verdict


def test_execution_failure_is_not_blocked_or_pass(tmp_path, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["qualify_npu_p0.py", "--output-dir", str(tmp_path)])
    monkeypatch.setattr(qualification, "_check_assets", lambda: None)
    monkeypatch.setattr(qualification, "build_oracle", lambda *args: (tmp_path / "oracle", {}))
    monkeypatch.setattr(qualification, "_load_kws_corpus", lambda: [])
    monkeypatch.setattr(qualification, "_load_vww_corpus", lambda: [])
    def fail():
        raise RuntimeError("oracle execution failed")
    monkeypatch.setattr(qualification.npu_model, "load_kws_model", fail)
    assert qualification.main() == 1
    assert json.loads((tmp_path / "qualification-p0.json").read_text())["verdict"] == "FAIL"


@pytest.mark.parametrize("payload", [
    {"status": "passed"},
    {"status": "passed", "exit_code": 0},
])
def test_p5_report_accepts_check_and_run_flow_results(tmp_path, payload):
    result = tmp_path / "result.json"
    result.write_text(json.dumps(payload))
    assert p5_report.passed_result(result) == payload


@pytest.mark.parametrize("payload", [
    {"status": "failed"},
    {"status": "passed", "exit_code": 1},
])
def test_p5_report_rejects_failed_results(tmp_path, payload):
    result = tmp_path / "result.json"
    result.write_text(json.dumps(payload))
    with pytest.raises(ValueError, match="failed structured result"):
        p5_report.passed_result(result)


def test_p5_rtl_reject_marker_detection():
    assert p5_rtl.rejected_markers("NPU operator test passed\n") == []
    markers = p5_rtl.rejected_markers(
        "NPU operator test passed\nassertion failed\nSIM_TEST_TIMEOUT\n"
    )
    assert {marker.lower() for marker in markers} == {"assertion failed", "sim_test_timeout"}


def test_p5_report_rejects_unproven_rtl_pass():
    with pytest.raises(ValueError, match="provenance"):
        p5_report.validate_rtl({"verdict": "PASS", "verification_ids": ["NPU-V014"]})


def test_p5_report_rejects_changed_implementation_identity(tmp_path, monkeypatch):
    implementation = tmp_path / "implementation.py"
    implementation.write_text("original\n")
    identity = p5_report.file_identity(implementation)
    monkeypatch.setattr(p5_report, "ROOT", tmp_path)
    monkeypatch.setattr(p5_report, "RTL_IMPLEMENTATION_REQUIRED", {"implementation.py"})
    p5_report.validate_implementation({"implementation.py": identity})
    identity["sha256"] = "0" * 64
    with pytest.raises(ValueError, match="identity mismatch"):
        p5_report.validate_implementation({"implementation.py": identity})


def test_p5_report_rejects_missing_implementation_identity(tmp_path, monkeypatch):
    implementation = tmp_path / "implementation.py"
    implementation.write_text("original\n")
    monkeypatch.setattr(p5_report, "ROOT", tmp_path)
    monkeypatch.setattr(
        p5_report, "RTL_IMPLEMENTATION_REQUIRED", {"implementation.py", "missing.py"}
    )
    with pytest.raises(ValueError, match="lacks required"):
        p5_report.validate_implementation({
            "implementation.py": p5_report.file_identity(implementation)
        })


def _valid_rtl_cases(tmp_path, monkeypatch):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"artifact")
    identity = p5_report.file_identity(artifact)
    expected = {
        (workload, f"{workload}-{index}"): hashlib.sha256(
            f"{workload}-{index}".encode()
        ).hexdigest()
        for workload in ("kws", "vww") for index in range(10)
    }
    monkeypatch.setattr(p5_report, "frozen_rtl_samples", lambda: expected)
    cases = [{
        "workload": workload, "input": name, "source_input_sha256": digest,
        "descriptors": 1, "layer_sha256": [digest],
        "artifacts": {key: identity for key in ("memory", "final", "write_trace")},
        "plusargs": [f"+CASE={name}"],
    } for (workload, name), digest in expected.items()]
    return cases, identity


def test_p5_report_rejects_changed_or_duplicate_frozen_cases(tmp_path, monkeypatch):
    cases, _identity = _valid_rtl_cases(tmp_path, monkeypatch)
    p5_report.validate_rtl_cases(cases)
    cases[0]["source_input_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="input hash"):
        p5_report.validate_rtl_cases(cases)
    cases, _identity = _valid_rtl_cases(tmp_path, monkeypatch)
    cases[1] = dict(cases[0])
    with pytest.raises(ValueError, match="ten cases"):
        p5_report.validate_rtl_cases(cases)


def test_p5_report_binds_simulator_command_to_case(tmp_path, monkeypatch):
    cases, identity = _valid_rtl_cases(tmp_path, monkeypatch)
    case_map = p5_report.validate_rtl_cases(cases)
    prefix = ["simulator"]
    records = [{
        "workload": case["workload"], "input": case["input"], "status": "PASS",
        "exit_code": 0, "timed_out": False, "rejected_markers": [],
        "command": [*prefix, *case["plusargs"]], "log": identity,
    } for case in cases]
    p5_report.validate_simulator_records("iverilog", records, case_map, prefix)
    records[0]["command"] = ["simulator", "+CASE=wrong"]
    with pytest.raises(ValueError, match="does not match"):
        p5_report.validate_simulator_records("iverilog", records, case_map, prefix)


def test_p5_report_binds_firmware_to_simulator_start(tmp_path):
    firmware = tmp_path / "firmware.bin"
    firmware.write_bytes(b"firmware")
    command = [str(firmware.resolve())]
    identity = p5_report.firmware_identity(
        {"command": command, "started_at": "2099-01-01T00:00:00+00:00"}, firmware
    )
    assert identity["sha256"]
    with pytest.raises(ValueError, match="changed after simulator start"):
        p5_report.firmware_identity(
            {"command": command, "started_at": "1970-01-01T00:00:00+00:00"}, firmware
        )


def _bare_metal_evidence(tmp_path):
    simulator = tmp_path / "simulator"
    simulator.mkdir()
    emulator = simulator / "emu"
    firmware = tmp_path / "firmware.bin"
    log = simulator / "sim.log"
    result = simulator / "result-sim.json"
    check = simulator / "result-check.json"
    required = ["NPU_P5_LP model=kws", "SIM_TEST_PASS code=0"]
    emulator.write_bytes(b"emulator")
    firmware.write_bytes(b"firmware")
    log.write_text("NPU_P5_LP model=kws active=1 read=2 write=3 softmax=4\nSIM_TEST_PASS code=0\n")
    result.write_text(json.dumps({
        "schema_version": 1,
        "tool": "verilator-sim",
        "status": "passed",
        "exit_code": 0,
        "cwd": str(simulator.resolve()),
        "log": str(log.resolve()),
        "started_at": "2099-01-01T00:00:00+00:00",
        "finished_at": "2099-01-01T00:00:01+00:00",
        "command": [str(emulator.resolve()), "-i", str(firmware.resolve()),
                    "--fast-flash", "-t", "3600"],
    }))
    check.write_text(json.dumps({
        "schema_version": 1,
        "status": "passed",
        "log": str(log.resolve()),
        "required_markers": required,
        "missing_markers": [],
        "rejected_matches": [],
    }))
    return result, check, log, firmware, emulator, required


def test_p5_report_binds_complete_bare_metal_evidence(tmp_path):
    result, check, log, firmware, emulator, required = _bare_metal_evidence(tmp_path)
    _run, _text, evidence = p5_report.validate_simulation_evidence(
        result, check, log, firmware, required
    )
    assert set(evidence) == {
        "result_identity", "check_identity", "log", "emulator", "firmware",
        "required_markers",
    }
    emulator.write_bytes(b"changed")
    with pytest.raises(ValueError, match="identity mismatch"):
        p5_report.verify_identity(evidence["emulator"])


@pytest.mark.parametrize("mutation", [
    "status_only", "wrong_log", "marker_set", "check_rejected", "log_missing",
    "log_rejected", "wrong_command", "missing_exit_code", "new_emulator",
])
def test_p5_report_rejects_invalid_bare_metal_evidence(tmp_path, mutation):
    result, check, log, firmware, emulator, required = _bare_metal_evidence(tmp_path)
    result_data = json.loads(result.read_text())
    check_data = json.loads(check.read_text())
    if mutation == "status_only":
        check_data = {"status": "passed"}
    elif mutation == "wrong_log":
        check_data["log"] = str((tmp_path / "other.log").resolve())
    elif mutation == "marker_set":
        check_data["required_markers"].append("EXTRA")
    elif mutation == "check_rejected":
        check_data["rejected_matches"] = ["SIM_TEST_FAIL"]
    elif mutation == "log_missing":
        log.write_text("NPU_P5_LP model=kws active=1 read=2 write=3 softmax=4\n")
    elif mutation == "log_rejected":
        log.write_text(log.read_text() + "SIM_TEST_FAIL\n")
    elif mutation == "wrong_command":
        result_data["command"][-1] = "3599"
    elif mutation == "missing_exit_code":
        result_data.pop("exit_code")
    else:
        result_data["started_at"] = "1970-01-01T00:00:00+00:00"
    result.write_text(json.dumps(result_data))
    check.write_text(json.dumps(check_data))
    with pytest.raises(ValueError, match="bare-metal|changed after simulator start"):
        p5_report.validate_simulation_evidence(result, check, log, firmware, required)


def _deployment(tmp_path, workload, prefix):
    directory = tmp_path / workload
    directory.mkdir()
    names = {
        "descriptors.bin", "weights.bin", "params.bin",
        f"{prefix}_npu.c", f"{prefix}_npu.h",
    }
    files = {}
    for name in names:
        path = directory / name
        path.write_bytes(name.encode())
        files[name] = {
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    manifest = {
        "schema": 1,
        "workload": workload,
        "numeric_profile": 1,
        "source_model_sha256": p5_report.MODEL_SHA256[workload],
        "compiler": {"contract": p5_report.DEPLOYMENT_CONTRACT},
        "files": files,
    }
    (directory / "npu.json").write_text(json.dumps(manifest))
    return directory, manifest


def test_p5_report_accepts_exact_deployment_contract(tmp_path):
    directory, manifest = _deployment(tmp_path, "kws", "kws")
    assert p5_report.validate_deployment(directory, workload="kws", prefix="kws") == manifest


@pytest.mark.parametrize("mutation", ["model", "contract", "missing", "extra"])
def test_p5_report_rejects_deployment_contract_drift(tmp_path, mutation):
    directory, manifest = _deployment(tmp_path, "vww", "vww")
    if mutation == "model":
        manifest["source_model_sha256"] = "0" * 64
    elif mutation == "contract":
        manifest["compiler"]["contract"] = "npu-p5/0.0.0"
    elif mutation == "missing":
        manifest["files"].pop("descriptors.bin")
    else:
        extra = directory / "extra.bin"
        extra.write_bytes(b"extra")
        manifest["files"][extra.name] = {
            "bytes": extra.stat().st_size,
            "sha256": hashlib.sha256(extra.read_bytes()).hexdigest(),
        }
    (directory / "npu.json").write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="invalid deployment"):
        p5_report.validate_deployment(directory, workload="vww", prefix="vww")
