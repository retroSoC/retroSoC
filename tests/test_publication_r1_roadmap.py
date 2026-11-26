"""Check quarter-boundary semantics and tightly scoped roadmap chip typography."""
import json
from pathlib import Path

import pytest

from publications.build_tiny_datasheet import r1_roadmap_regions
from publications.r1_roadmap import roadmap_reference

SOURCE = Path(__file__).resolve().parents[1] / "publications/datasheets/tiny/r1-roadmap.json"


@pytest.fixture
def source():
    return json.loads(SOURCE.read_text(encoding="utf-8"))


def test_recorded_dates_and_inclusive_planning_quarters(source):
    chart = roadmap_reference(source)
    assert len(chart["quarters"]) == 14
    assert chart["quarters"][:3] == [{"year": 2025, "label": "Q3"}, {"year": 2025, "label": "Q4"},
                                     {"year": 2026, "label": "Q1"}]
    tiny, mini, *planned = chart["products"]
    assert tiny["start_offset"] == pytest.approx(4 + 86/92)
    assert mini["start_offset"] == 0
    assert mini["milestone"]["offset"] == pytest.approx(5 + 9/92)
    assert mini["milestone"]["quarter"] == "2026 Q4"
    assert tiny["end_offset"] == mini["end_offset"] == pytest.approx(5 + 57/92)
    assert tiny["end"] is mini["end"] is None
    assert [p["period"] for p in planned] == ["2027 Q1–Q3", "2027 Q3–2028 Q2", "2027 Q4–2028 Q3", "2028 Q1–Q4"]
    assert [(p["start_offset"], p["end_offset"]) for p in planned] == [(6, 9), (8, 12), (9, 13), (10, 14)]
    for quarter in (10, 11):
        assert [p["name"] for p in planned if p["start_offset"] <= quarter < p["end_offset"]] == ["PRO", "MAX", "ULTRA"]


@pytest.mark.parametrize(("row", "change"), [
    (0, {"end": "2026Q4"}), (1, {"source": "r1-plan"}), (2, {"end": "2026Q4"}),
    (3, {"start": "2027Q0"}), (4, {"status": "In development"}), (5, {"end": "2029Q1"}),
    (1, {"milestone": {"date": "2027-01-01", "label": "OpenC906 integration", "source": "mini-c906"}}),
])
def test_roadmap_rejects_unsubstantiated_or_invalid_windows(source, row, change):
    source["products"][row].update(change)
    with pytest.raises(ValueError):
        roadmap_reference(source)


def test_open_endpoint_in_a_leap_quarter(source):
    source["as_of"] = "2028-02-29"
    # Test an active span without introducing an already elapsed planned window.
    for product in source["products"][2:]:
        product.update(start="2028Q2", end="2028Q4")
    assert roadmap_reference(source)["cutoff_offset"] == pytest.approx(10 + 60/91)


@pytest.mark.parametrize("bad", ["overlap", "wrong-scale", "foreign-page", "missing"])
def test_only_the_six_translated_master_regions_receive_font_exceptions(bad):
    plate = dict(kind="r1-roadmap", page=405, x=50, y=210, width=486, height=538)
    master = dict(width=75, height=75, scale=.63675)
    chips = [dict(kind="roadmap-chip", page=405, x=56+i*26, y=242+i*82, **master) for i in range(6)]
    assert r1_roadmap_regions([plate, *reversed(chips)], master) == (plate, chips)
    if bad == "missing":
        chips.pop()
    elif bad == "overlap":
        chips[1]["y"] = chips[0]["y"] + 70
    elif bad == "foreign-page":
        chips[-1]["page"] = 404
    else:
        chips[-1]["scale"] = .5
    with pytest.raises(ValueError, match="roadmap"):
        r1_roadmap_regions([plate, *chips], master)
