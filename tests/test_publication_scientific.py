"""Scientific display must preserve computational data and literal interfaces."""
from copy import deepcopy

import pytest

from publications import scientific_reference as science
from publications.build_datasheet import validate_character_size


def notation(raw="Iref = 2**((T-25)/25) + k * f_MHz"):
    data = {"specifications": {"records": []}, "text": raw}
    science.prepare(data)
    return data["scientific"]


def test_current_formula_has_real_exponent_and_quantity_scripts():
    parts = science.tokens("Iref[mA] = 0.2 * 2**((T-25)/25) + k * f_MHz * V/1.2")
    assert {p["value"] for p in parts if p["kind"] == "symbol"} == {"ref", "MHz"}
    assert next(p for p in parts if p["kind"] == "power") == {
        "kind": "power", "base": "2", "value": "(T−25)/25"}
    assert "*" not in "".join(p["value"] for p in parts)


@pytest.mark.parametrize("literal", [
    "rs_status_t", "SCLK_DIV", "VDDIO", "GPIO17", "D0 D7 E1 E2 A1",
    "char **argv", "unsigned int *buffer", "RESET_N", "data[2]", "2**(unclosed",
])
def test_interface_and_nonmathematical_text_stay_literal(literal):
    assert science.tokens(literal) == []


def test_mechanical_symbols_are_context_specific():
    assert science.tokens("D2 / E2", mechanical=True) == [
        {"kind": "symbol", "base": "D", "value": "2"},
        {"kind": "text", "value": " / "},
        {"kind": "symbol", "base": "E", "value": "2"}]
    assert science.tokens("D2 / E2") == []


@pytest.mark.parametrize("formula,exponent", [("2^16", "16"), ("mm**2", "2"), ("2**((n+1)/2)", "(n+1)/2")])
def test_balanced_explicit_powers(formula, exponent):
    assert science.tokens(formula)[0]["value"] == exponent


def test_display_collection_does_not_rewrite_source_or_reference_state():
    data = {"specifications": {"records": [{"group": "models", "value": "Iref=2**((T-25)/25)",
            "status": "reference", "formula": "Tref=L/(0.6*Bideal)", "numeric": None}]},
            "blocks": [{"kind": "code", "text": "Iref literal_only_in_code"}], "signature": "VOH"}
    before = deepcopy(data)
    science.prepare(data)
    actual = deepcopy(data)
    actual.pop("scientific")
    actual["specifications"].pop("scientific")
    assert actual == before
    assert "Iref literal_only_in_code" not in data["scientific"]["entries"]
    assert science.plot_text("rs_status_t", data["scientific"]) == ("rs_status_t", None)
    rendered, identity = science.plot_text("Iref=2**((T-25)/25)", data["scientific"])
    assert "^{" in rendered and "_{" in rendered and identity
    assert "**" not in rendered


def region():
    registry = notation()
    identity = next(k for k, v in registry["scripts"].items() if v["text"] == "ref")
    value = dict(kind="scientific-script", id=identity, text="ref", role="sub", renderer="native",
                 page=1, x=20, y=30, width=15, height=6.93, font_size=6.3, base_size=9)
    return registry, value


@pytest.mark.parametrize("change", [
    {"id": "unknown"}, {"text": "unrelated"}, {"text": "r"}, {"role": "super"},
    {"renderer": "page"}, {"font_size": 5}, {"width": 600}, {"height": 90},
    {"base_size": 8}, {"x": float("nan")}, {"page": 0}, {"page": 1.5}, {"font_size": True},
])
def test_arbitrary_small_text_cannot_claim_script_exception(change):
    registry, value = region()
    value.update(change)
    with pytest.raises(ValueError):
        science.validate_regions([value], registry)


def glyph():
    return dict(text="r", fontname="ABCDEF+Inter-Regular", size=6.3, width=3,
                x0=21, x1=24, top=30.2, bottom=36.5)


def test_pdf_font_floor_only_accepts_source_bound_script_glyph():
    registry, value = region()
    science.validate_regions([value], registry)
    char = glyph()
    assert science.script_allowed(char, 1, [value])
    validate_character_size(char, 1, [value])
    for changed in [{"text": "V"}, {"fontname": "DejaVuSans"}, {"fontname": "NotInter-Regular"}, {"size": 5.9}, {"top": 100, "bottom": 106.3}]:
        with pytest.raises(ValueError):
            validate_character_size({**char, **changed}, 1, [value])
    with pytest.raises(ValueError):
        validate_character_size(char, 2, [value])
    with pytest.raises(ValueError):
        validate_character_size(char, 1, [])


def test_svg_scripts_require_source_identity_and_managed_font(tmp_path):
    registry = notation("VOH")
    identity = registry["entries"]["VOH"]["id"]
    template = ('<svg xmlns="http://www.w3.org/2000/svg"><g id="scientific-{identity}" '
                'transform="translate(10 20) rotate(0 3 4)"><text><tspan '
                'style="font-size:6.3px;font-family:{font}" x="1 6" y="10 10">OH</tspan>'
                '</text></g></svg>')
    path = tmp_path / "plot.svg"
    path.write_text(template.format(identity=identity, font="Inter"), encoding="utf-8")
    values = science.svg_scripts(path, registry)
    assert [r["text"] for r in values] == ["O", "H"]
    assert values[0]["x"] == pytest.approx(10.9)
    assert values[0]["y"] > 20
    science.validate_regions([{**r, "page": 1} for r in values], registry)
    path.write_text(template.format(identity=identity, font="DejaVu Sans"), encoding="utf-8")
    with pytest.raises(ValueError, match="non-Inter"):
        science.svg_scripts(path, registry)
    path.write_text(template.format(identity="unknown", font="Inter"), encoding="utf-8")
    with pytest.raises(ValueError, match="display source"):
        science.svg_scripts(path, registry)


def test_change_markers_follow_actual_rendered_uses_only():
    registry = notation("VOH")
    identity = registry["entries"]["VOH"]["id"]
    markers = science.change_markers([dict(kind="scientific-use", id=identity, page=63)],
                                     {"change_prefix": "test-"}, registry)
    assert [m["page"] for m in markers] == [63, 63]
    assert all(m["id"].startswith("test-") for m in markers)
    with pytest.raises(ValueError, match="no display source"):
        science.change_markers([dict(kind="scientific-use", id="unknown", page=64)],
                              {"change_prefix": "test-"}, registry)


def test_hashed_display_audit_is_bound_to_current_source(tmp_path):
    import hashlib
    import json

    data = {"specifications": {"records": []}, "text": "VOH"}
    science.prepare(data)
    identity = data["scientific"]["entries"]["VOH"]["id"]
    items = [dict(kind="scientific-use", id=identity, page=3)]
    hashes = science.export_audit(tmp_path, data, items)
    manifest = {"scientific_audits": hashes}
    science.verify_audit(tmp_path, manifest, data)
    path = tmp_path / "scientific-notation.json"
    original = path.read_bytes()
    path.write_bytes(original + b" ")
    with pytest.raises(ValueError, match="integrity"):
        science.verify_audit(tmp_path, manifest, data)
    value = json.loads(original)
    value["sources"][0]["raw"] = "tampered quantity"
    path.write_text(json.dumps(value), encoding="utf-8")
    hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    with pytest.raises(ValueError, match="current sources"):
        science.verify_audit(tmp_path, manifest, data)


def test_scientific_units_use_symbols_without_reinterpreting_coulombs():
    registry = notation()
    for raw, expected in {"deg C": "°C", "uA": "µA", "uF": "µF", "us": "µs", "kohm": "kΩ"}.items():
        assert registry["entries"]["unit:" + raw]["tokens"] == [{"kind": "text", "value": expected}]
    assert "unit:C" not in registry["entries"]
    assert science.tokens("Bypass 1.0 uF; load 10 kohm; leakage 1 uA") == [
        {"kind": "text", "value": "Bypass 1.0 µF; load 10 kΩ; leakage 1 µA"}]


def test_equation_typography_preserves_nearby_english_hyphens():
    assert science.tokens("The profile uses SCK=MEM/2, 32-bit four-beat transfers.") == []
    parts = science.tokens("SCK=PCLK/(2*DIV); end-to-end, held-CS and 32-bit payload.")
    assert parts == [{"kind": "text", "value": "SCK=PCLK/(2×DIV); end-to-end, held-CS and 32-bit payload."}]
    assert any(p["kind"] == "text" and "−I×R" in p["value"] for p in science.tokens("VOH=VIO-I*R"))
