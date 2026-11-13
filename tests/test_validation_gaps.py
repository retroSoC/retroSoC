from __future__ import annotations

import copy
import json
from datetime import date
from pathlib import Path

from scripts.validation_gaps import load_gaps, relevant_gaps, validate_document

ROOT = Path(__file__).resolve().parents[1]


def test_gap_registry_is_owned_bounded_and_reviewable() -> None:
    document = json.loads((ROOT / "quality/validation-gaps.json").read_text(encoding="utf-8"))
    assert validate_document(document, today=date(2026, 11, 14)) == []
    gaps = load_gaps(ROOT)
    assert len(gaps) == 1
    assert gaps[0]["status"] == "deferred"
    assert gaps[0]["owner"] == "@maksyuki"


def test_gap_registry_rejects_overdue_invalid_and_unsafe_records() -> None:
    document = json.loads((ROOT / "quality/validation-gaps.json").read_text(encoding="utf-8"))
    overdue = copy.deepcopy(document)
    overdue["gaps"][0]["review_by"] = "2020-01-01"
    assert "gap review_by is overdue" in validate_document(overdue, today=date(2026, 11, 14))

    invalid = copy.deepcopy(document)
    invalid["gaps"][0]["source_revision"] = "z" * 40
    invalid["gaps"][0]["review_by"] = None
    issues = validate_document(invalid, today=date(2026, 11, 14))
    assert "gap source_revision must be a full lowercase SHA" in issues
    assert any("review_by is invalid" in issue for issue in issues)

    unsafe = copy.deepcopy(document)
    unsafe["gaps"][0]["evidence"][0]["uri"] = "../outside.json"
    assert any("evidence URI is unsafe" in issue for issue in validate_document(unsafe, today=date(2026, 11, 14)))


def test_gap_selection_is_scoped_and_explicitly_resolvable() -> None:
    gaps = load_gaps(ROOT)
    task = {
        "target_socs": ["MINI"],
        "validation": {"pdks": ["IHP130"]},
    }
    assert [item["id"] for item in relevant_gaps(task, gaps)] == ["mini-yosys-backend"]
    task["target_socs"] = ["TINY"]
    assert relevant_gaps(task, gaps) == []
    task["target_socs"] = ["MINI"]
    task["resolves_gaps"] = ["mini-yosys-backend"]
    assert relevant_gaps(task, gaps) == []
