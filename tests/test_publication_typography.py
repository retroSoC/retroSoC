"""Small-type exceptions stay inside the continuation text's layout region."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publications.build_datasheet import validate_character_size  # noqa: E402


REGION = {"kind": "table-continuation", "page": 2,
          "x": 54, "y": 60, "width": 300, "height": 20}


def character(**overrides):
    return {"text": "x", "size": 8.5, "x0": 55, "x1": 60,
            "top": 61, "bottom": 69.5, **overrides}


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
