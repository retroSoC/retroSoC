"""Publication support claims must cover real IPs and identify their evidence."""
import copy
import json
from pathlib import Path

import pytest

from publications.system_reference import collect_system_reference, source_paths, validate_reference

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def sample(tmp_path):
    for name in ("source.md", "test.py", "report.json", "profile.mk"):
        (tmp_path / name).write_text("test evidence", encoding="utf-8")
    return {"schema_version": 1, "source_revision": "a" * 40, "sources": ["source.md"],
            "support": [{"id": "ip", "implementation": "Integrated", "verification": "Tests available",
                         "sources": ["source.md"], "tests": ["test.py"], "reports": []}], "limitations": []}


def test_complete_source_and_test_inventory(sample, tmp_path):
    validate_reference(sample, {"ip"}, tmp_path)
    assert source_paths(sample) == {"source.md", "test.py"}


@pytest.mark.parametrize("change", ["missing", "extra", "duplicate"])
def test_reject_incomplete_or_ambiguous_ip_inventory(sample, tmp_path, change):
    if change == "missing":
        sample["support"] = []
    else:
        row = copy.deepcopy(sample["support"][0])
        if change == "extra":
            row["id"] = "unknown"
        sample["support"].append(row)
    with pytest.raises(ValueError, match="coverage|duplicate"):
        validate_reference(sample, {"ip"}, tmp_path)


def test_reject_broken_dependency(sample, tmp_path):
    sample["support"][0]["sources"] = ["missing.md"]
    with pytest.raises(ValueError, match="missing system-reference source"):
        validate_reference(sample, {"ip"}, tmp_path)


def test_reject_reportless_pass(sample, tmp_path):
    sample["support"][0]["verification"] = "Reported pass"
    with pytest.raises(ValueError, match="requires a report"):
        validate_reference(sample, {"ip"}, tmp_path)


def test_reject_report_without_profile_or_snapshot(sample, tmp_path):
    sample["support"][0]["reports"] = [{"path": "report.json"}]
    with pytest.raises(ValueError, match="report requires"):
        validate_reference(sample, {"ip"}, tmp_path)


def test_report_dependencies_and_revision_are_enforced(sample, tmp_path):
    row = sample["support"][0]
    row["verification"] = "Reported pass"
    row["reports"] = [{"path": "report.json", "profile": "profile.mk", "revision": "a" * 40,
                       "stage": "simulation", "result": "pass"}]
    validate_reference(sample, {"ip"}, tmp_path)
    assert {"report.json", "profile.mk"} <= source_paths(sample)
    row["reports"][0]["revision"] = "b" * 40
    with pytest.raises(ValueError, match="reviewed snapshot"):
        validate_reference(sample, {"ip"}, tmp_path)


def test_repository_inventory_covers_every_published_ip():
    config = json.loads((ROOT / "publications/datasheets/mini.json").read_text(encoding="utf-8"))
    reference = collect_system_reference(ROOT, config["source_revision"])
    assert reference["limitations"]
    assert "app/apps/hp_boot/main.c" in source_paths(reference)
    assert [row["name"] for row in reference["boot_layout"]] == [
        "OpenSBI FW_JUMP", "Device tree", "Linux Image", "initramfs"]
    assert reference["boot_layout"][0] == {
        "name": "OpenSBI FW_JUMP", "address": "0x38000000", "max_size_kib": 512}
