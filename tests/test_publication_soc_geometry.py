"""Physical routing rules reject hidden or ambiguous arrow connections."""
import copy

import pytest

from publications.soc_diagram_geometry import geometry_issues, routes, validate_geometry


@pytest.fixture
def drawing():
    return {"routing": {"arrow_length_mm": 1, "arrow_width_mm": .8, "visible_shaft_mm": 1,
                        "arrow_clearance_mm": .5, "stroke_pt": .65},
            "nodes": [{"id": "a", "x": 0, "y": 0, "w": 10, "h": 4, "role": "module"},
                      {"id": "b", "x": 20, "y": 0, "w": 10, "h": 4, "role": "module"}],
            "edges": [{"id": "ab", "from": "a", "to": "b", "source_side": "east", "target_side": "west",
                       "source_position": .5, "target_position": .5, "via": [], "kind": "data", "arrow": True}]}


def crossing(drawing, x):
    drawing["nodes"] += [{"id": "c", "x": x, "y": -3, "w": 0, "h": 1, "role": "io"},
                         {"id": "d", "x": x, "y": 5, "w": 0, "h": 1, "role": "io"}]
    drawing["edges"].append({"id": "cd", "from": "c", "to": "d", "source_side": "east", "target_side": "west",
                             "source_position": .5, "target_position": .5, "via": [], "kind": "io", "arrow": False})


def test_plain_crossing_away_from_arrow_is_allowed(drawing):
    crossing(drawing, 15)
    validate_geometry(drawing)
    head = routes(drawing)[0]["heads"][0]
    assert head[1] == [20, 2]
    assert max(p[0] for p in head) - min(p[0] for p in head) == 1
    assert max(p[1] for p in head) - min(p[1] for p in head) == pytest.approx(.8)


@pytest.mark.parametrize("x", [19.5, 19, 18.5])
def test_crossing_or_insufficient_stroke_clearance_at_head_is_rejected(drawing, x):
    crossing(drawing, x)
    with pytest.raises(ValueError, match="arrow clearance"):
        validate_geometry(drawing)


def test_duplex_start_head_is_protected_too(drawing):
    drawing["edges"][0].update(kind="stream", duplex=True)
    crossing(drawing, 10.5)
    with pytest.raises(ValueError, match="arrow clearance"):
        validate_geometry(drawing)


@pytest.mark.parametrize("duplex,gap", [(False, 1.9), (True, 2.9)])
def test_visible_shaft_must_fit_beyond_arrowheads(drawing, duplex, gap):
    drawing["nodes"][1]["x"] = 10 + gap
    drawing["edges"][0].update(kind="stream", duplex=duplex)
    with pytest.raises(ValueError, match="short .*shaft"):
        validate_geometry(drawing)


def test_diagonal_and_foreign_symbol_intersection_are_rejected(drawing):
    diagonal = copy.deepcopy(drawing)
    diagonal["edges"][0]["target_position"] = .6
    assert any("non-orthogonal" in issue for issue in geometry_issues(diagonal))
    drawing["nodes"].append({"id": "obstacle", "x": 14, "y": 1, "w": 2, "h": 2, "role": "module"})
    with pytest.raises(ValueError, match="unrelated symbol"):
        validate_geometry(drawing)


def test_out_of_bounds_port_is_rejected(drawing):
    drawing["edges"][0]["target_position"] = 1.1
    with pytest.raises(ValueError, match="invalid port"):
        validate_geometry(drawing)
