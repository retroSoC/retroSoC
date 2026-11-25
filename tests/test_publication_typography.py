"""Small-type exceptions stay inside their renderer-bound layout regions."""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publications.build_datasheet import validate_character_size  # noqa: E402
from publications.build_tiny_datasheet import (  # noqa: E402
    r1_card_copy_regions,
    r1_product_line_regions,
    r1_ultra_type_limit,
    scaled_chip_type_limits,
)


REGION = {"kind": "table-continuation", "page": 2,
          "x": 54, "y": 60, "width": 300, "height": 20}


def character(**overrides):
    return {"text": "x", "size": 8.5, "x0": 55, "x1": 60,
            "top": 61, "bottom": 69.5, **overrides}


def test_r1_chip_regions_are_read_down_each_column():
    figure = {"kind": "r1-product-line", "page": 3, "x": 54, "width": 488}
    chips = [
        {"kind": "r1-chip", "page": 3, "x": x, "y": y, "width": 68}
        for x, y in ((65.1, 450), (65, 555), (65.2, 660), (316, 450), (316.1, 555), (316, 660))
    ]
    assert r1_product_line_regions([figure, *reversed(chips)]) == (figure, chips)
    chips[-1]["x"] = 260
    with pytest.raises(ValueError, match="three R1 product chips in each column"):
        r1_product_line_regions([figure, *chips])


def test_r1_card_copy_regions_are_confined_to_their_cards():
    figure = {"kind": "r1-product-line", "page": 3, "x": 54, "y": 400, "width": 488, "height": 373}
    chips = [
        {"kind": "r1-chip", "page": 3, "x": x, "y": y, "width": 68, "height": 68}
        for x, y in ((66, 460), (66, 558), (66, 656), (312, 460), (312, 558), (312, 656))
    ]
    copies = [
        {**chip, "kind": "r1-card-copy", "x": chip["x"] + 75, "y": chip["y"] - 9,
         "width": 144, "height": 92}
        for chip in chips
    ]
    assert r1_card_copy_regions([*chips, *reversed(copies)], figure, chips) == copies
    copies[-1]["x"] = chips[-1]["x"] + 60
    with pytest.raises(ValueError, match="must stay beside its chip"):
        r1_card_copy_regions([*chips, *copies], figure, chips)


def test_r1_ultra_type_limit_accepts_only_the_scoped_positioning_text():
    region = {"kind": "r1-card-copy", "page": 3, "x": 370, "y": 640, "width": 144, "height": 92}
    glyph = character(text="M", size=7.25, x0=400, x1=405, top=655, bottom=662.25)
    matches = [{**glyph, "chars": [glyph]}, {**glyph, "top": 600, "bottom": 607.25, "chars": []}]
    page = SimpleNamespace(search=lambda label, **_: matches if label == "— Maximum compute & memory" else [])
    assert r1_ultra_type_limit(page, region) == ([glyph], 7.20)
    glyph["size"] = 7
    with pytest.raises(ValueError, match="must use 7.25 pt"):
        r1_ultra_type_limit(page, region)


def test_continuation_size_allowed_only_inside_its_region():
    validate_character_size(character(), 2, [REGION])
    validate_character_size(character(size=9), 1, [])


@pytest.mark.parametrize("overrides,page,regions", [
    ({}, 2, []),
    ({}, 1, [REGION]),
    ({"x0": 53}, 2, [REGION]),
    ({"x1": 355}, 2, [REGION]),
    ({"top": 59}, 2, [REGION]),
    ({"bottom": 81}, 2, [REGION]),
    ({}, 2, [{**REGION, "kind": "ordinary-caption"}]),
])
def test_unmarked_or_partly_outside_text_keeps_nine_point_minimum(overrides, page, regions):
    with pytest.raises(ValueError, match="smaller than 9 pt"):
        validate_character_size(character(**overrides), page, regions)


def test_even_marked_continuation_text_cannot_shrink_below_eight_point_five():
    with pytest.raises(ValueError, match="smaller than 8.5 pt"):
        validate_character_size(character(size=8), 2, [REGION])


def test_quarter_turn_uses_rendered_font_height_not_glyph_advance():
    validate_character_size(character(size=2.2, width=9, matrix=(0, 1, -1, 0, 0, 0)), 1, [])
    with pytest.raises(ValueError, match="smaller than 9 pt"):
        validate_character_size(character(size=12, width=8, matrix=(0, -1, 1, 0, 0, 0)), 1, [])


def test_wide_upright_or_slanted_glyph_does_not_bypass_type_minimum():
    for matrix in [(1, 0, 0, 1, 0, 0), (.7, .7, -.7, .7, 0, 0)]:
        with pytest.raises(ValueError, match="smaller than 9 pt"):
            validate_character_size(character(size=8, width=12, matrix=matrix), 1, [])


COMPACT = {**REGION, "kind": "soc-compact", "id": "gca"}


def test_eight_point_type_is_allowed_in_approved_cdc_or_gateway_cell():
    validate_character_size(character(size=8), 2, [COMPACT])
    validate_character_size(character(size=3, width=8, matrix=(0, 1, -1, 0, 0, 0)), 2, [COMPACT])
    validate_character_size(character(size=8), 2, [{**COMPACT, "id": "gwa"}])


@pytest.mark.parametrize("changes,region", [
    ({"x0": 53.9}, COMPACT), ({"top": 59.9}, COMPACT),
    ({}, {**COMPACT, "page": 1}), ({}, {**COMPACT, "id": "ordinary-ip"}),
    ({}, {**COMPACT, "kind": "soc-bus"}), ({}, {**COMPACT, "kind": "soc-emphasis-region"}),
])
def test_compact_exception_does_not_leak_into_other_text(changes, region):
    with pytest.raises(ValueError, match="smaller than 9 pt"):
        validate_character_size(character(size=8, **changes), 2, [region])


def test_compact_text_still_has_eight_point_floor():
    with pytest.raises(ValueError, match="smaller than 8 pt"):
        validate_character_size(character(size=7.8), 2, [COMPACT])


@pytest.fixture
def cover_chip_text():
    region = {"kind": "cover-chip", "page": 1, "x": 54, "y": 60, "width": 95, "height": 95, "scale": 0.8}
    rows = {
        label: [character(size=size * region["scale"], chars=[character(size=size * region["scale"])])]
        for label, size in (("Edge AI", 9), ("RISC-V AI MCU", 10), ("Open Silicon Design", 6))
    }
    page = SimpleNamespace(search=lambda label, **_: rows[label])
    return page, region, rows


def test_cover_limits_include_only_scaled_inscriptions_inside_chip(cover_chip_text):
    page, region, rows = cover_chip_text
    rows["Edge AI"].append(character(x0=10, x1=52, chars=[character(x0=10, x1=13, size=7.2)]))
    limits = scaled_chip_type_limits(page, region)
    assert [glyphs for glyphs, _ in limits] == [
        rows[label][0]["chars"] for label in ("Edge AI", "RISC-V AI MCU", "Open Silicon Design")
    ]
    assert [limit for _, limit in limits] == pytest.approx([7.15, 7.95, 4.75])


@pytest.mark.parametrize("changes,message", [
    ({"x1": 150}, "inside the artwork"),
    ({"chars": [character(size=6)]}, "must scale to 4.80 pt"),
])
def test_cover_limits_reject_outside_or_unscaled_inscriptions(cover_chip_text, changes, message):
    page, region, rows = cover_chip_text
    rows["Open Silicon Design"][0].update(changes)
    with pytest.raises(ValueError, match=message):
        scaled_chip_type_limits(page, region)


def test_r1_soc_chip_type_limits_match_scaled_inscriptions(cover_chip_text):
    page, region, rows = cover_chip_text
    rows["Physical AI"] = rows.pop("Edge AI")
    rows["RISC-V AI SoC"] = rows.pop("RISC-V AI MCU")
    limits = scaled_chip_type_limits(page, region, "Physical AI", "RISC-V AI SoC")
    assert [glyphs for glyphs, _ in limits] == [
        rows[label][0]["chars"] for label in ("Physical AI", "RISC-V AI SoC", "Open Silicon Design")
    ]


def test_r1_soc_chip_type_limits_reject_mcu_badge(cover_chip_text):
    _, region, rows = cover_chip_text
    page = SimpleNamespace(search=lambda label, **_: rows.get(label, []))
    with pytest.raises(ValueError, match="requires one 'Physical AI'"):
        scaled_chip_type_limits(page, region, "Physical AI", "RISC-V AI SoC")
