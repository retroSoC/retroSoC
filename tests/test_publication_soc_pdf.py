"""Scoped PDF type checks distinguish compact cells, bold buses and normal IPs."""
from types import SimpleNamespace

import pytest

from publications import soc_diagram_pdf as checker


@pytest.fixture
def sample(monkeypatch):
    monkeypatch.setattr(checker, "font_weights", lambda *_: {"regular": 400, "bold": 700})
    regions = [dict(kind="soc-compact", id="gca", page=1, x=0, y=0, width=40, height=20),
               dict(kind="soc-bus", id="lp_bus", page=1, x=50, y=0, width=40, height=20)]
    compact = dict(text="C", fontname="regular", size=8, width=5, x0=1, x1=6, top=2, bottom=10)
    bus = dict(text="B", fontname="bold", size=9, width=6, x0=51, x1=57, top=2, bottom=11)
    ordinary = dict(text="I", fontname="regular", size=9, width=3, x0=100, x1=103, top=2, bottom=11)
    page = SimpleNamespace(chars=[compact, bus, ordinary], page_number=1)
    model = {"nodes": [dict(id="lp_bus", x=0, y=0)], "edges": [], "routing": {}}
    return page, model, regions


def run(sample):
    page, model, regions = sample
    return checker.check_diagram_pdf(page, None, model, regions, dict(top=0, bottom=20), None)


def test_scoped_font_size_and_weight_are_checked_in_exported_characters(sample):
    assert run(sample)["characters"] == dict(compact=1, bold=1, regular=1)


@pytest.mark.parametrize("index,changes", [
    (0, dict(fontname="bold")), (0, dict(size=9)), (0, dict(x0=-1)),
    (1, dict(fontname="regular")), (1, dict(size=8)),
    (2, dict(fontname="bold")), (2, dict(size=8)),
])
def test_wrong_font_weight_size_or_outside_cell_is_rejected(sample, index, changes):
    sample[0].chars[index].update(changes)
    with pytest.raises(ValueError, match="PDF type mismatch"):
        run(sample)


def test_rotated_cdc_label_uses_physical_font_height(sample):
    sample[0].chars[0].update(size=3, width=8, matrix=(0, 1, -1, 0, 0, 0))
    run(sample)
    sample[0].chars[0].update(width=7)
    with pytest.raises(ValueError, match="PDF type mismatch"):
        run(sample)


def test_missing_or_overlapping_label_region_is_rejected(sample):
    sample[2].append({**sample[2][0], "x": 200})
    with pytest.raises(ValueError, match="no rendered text"):
        run(sample)
    sample[2][-1]["x"] = 0
    with pytest.raises(ValueError, match="overlapping typography regions"):
        run(sample)
