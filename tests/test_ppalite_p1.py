"""Fail-closed PPALITE-P1 driver and deterministic corpus checks."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ppalite_p1_vectors import cases  # noqa: E402


def load_driver():
    spec = importlib.util.spec_from_file_location("ppalite_p1_driver", ROOT / "scripts/ppalite_p1.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_frozen_corpus_has_97_independent_cases():
    corpus = cases()
    assert len(corpus) == 97
    assert len({(case.width, case.height, case.input_format, case.gray8, case.rgb_swap,
                  case.output_byte_swap, case.step_x, case.step_y, case.phase_x, case.phase_y)
                 for case, _, _ in corpus}) == 97
    assert {case.input_format for case, _, _ in corpus} == set(range(6))
    assert {(case.step_x, case.step_y, case.phase_x, case.phase_y) for case, _, _ in corpus
            if case.width == 9} == {(x, y, px, py) for x in (1, 2, 4) for y in (1, 2, 4)
                                    for px in range(x) for py in range(y)}


def test_success_marker_and_forbidden_marker_rules():
    driver = load_driver()
    result = {"status": "passed", "exit_code": 0}
    driver.require_pass("PPALITE_P1_PASS case\n", result, "PPALITE_P1_PASS case")
    for content in ("", "PPALITE_P1_PASS case\nPPALITE_P1_PASS case\n",
                    "PPALITE_P1_PASS case\nSIM_TEST_TIMEOUT\n",
                    "PPALITE_P1_PASS case\nassertion failed\n"):
        with pytest.raises(ValueError):
            driver.require_pass(content, result, "PPALITE_P1_PASS case")
    with pytest.raises(ValueError):
        driver.require_pass("PPALITE_P1_PASS case\n", {"status": "failed", "exit_code": 1},
                            "PPALITE_P1_PASS case")


def test_vector_execution_rejects_empty_missing_duplicate_and_reordered_logs():
    driver = load_driver()
    valid = "".join(f"PPALITE_P1_VECTOR {index}\n" for index in range(97))
    driver.require_vector_execution(valid + "PPALITE_P1_PASS ppalite_core_tb\n", "ppalite_core_tb")
    for altered in ("", "PPALITE_P1_VECTOR 0\n", valid.replace("PPALITE_P1_VECTOR 96\n", ""),
                    valid.replace("PPALITE_P1_VECTOR 96\n", "PPALITE_P1_VECTOR 95\n"),
                    "PPALITE_P1_VECTOR 1\n" + valid):
        with pytest.raises(ValueError, match="vector execution marker"):
            driver.require_vector_execution(altered, "ppalite_core_tb")
    body = (ROOT / "tests/rtl/ppalite_test_body.svh").read_text()
    assert "vector_count !== 97" in body
    assert "vector_count != 97" not in body


def test_checked_record_rejects_stale_source_and_changed_artifact(tmp_path: Path):
    driver = load_driver()
    artifact = tmp_path / "artifact.log"
    artifact.write_text("original\n")
    record = tmp_path / "record.json"
    record.write_text(json.dumps({"status": "passed", "source": {"source.sv": "abc"},
                                  "artifacts": {str(artifact): driver.digest(artifact)}}))
    assert driver.checked_record(record, {"source.sv": "abc"})["status"] == "passed"
    with pytest.raises(ValueError, match="stale"):
        driver.checked_record(record, {"source.sv": "different"})
    artifact.write_text("changed\n")
    with pytest.raises(ValueError, match="changed"):
        driver.checked_record(record, {"source.sv": "abc"})


def test_storage_rejects_extra_or_missing_ram():
    driver = load_driver()
    expected = {"\\fifo$input": {"num_memory_bits": 66},
                "\\fifo$output": {"num_memory_bits": 272},
                "process_without_storage": {"num_memory_bits": 0}}
    assert driver.storage_geometry(expected) == ([66, 272], 2)
    for altered in (
            {**expected, "\\line_ram": {"num_memory_bits": 128}},
            {"\\fifo$input": {"num_memory_bits": 66}},
            {"\\fifo$input": {"num_memory_bits": 64},
             "\\fifo$output": {"num_memory_bits": 272}},
            {"\\other$input": {"num_memory_bits": 66},
             "\\fifo$output": {"num_memory_bits": 272}},
    ):
        with pytest.raises(ValueError, match="unexpected PPALITE memory"):
            driver.storage_geometry(altered)


def test_deleted_assertion_changes_identity(tmp_path: Path):
    driver = load_driver()
    model = tmp_path / "design.smt2"
    model.write_text("; yosys-smt2-assert first\n; yosys-smt2-assert second\n")
    original = driver.assertion_digest(model)
    model.write_text("; yosys-smt2-assert second\n")
    assert driver.assertion_digest(model) != original
    model.write_text("; no assertions\n")
    with pytest.raises(ValueError):
        driver.assertion_digest(model)
