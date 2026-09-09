"""Signal labels must refer to real, scoped declarations with valid bit selections."""

from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from publications.waveform_reference import validate_waveforms  # noqa: E402


@pytest.fixture
def example(tmp_path):
    directory = tmp_path / "rtl"
    directory.mkdir()
    (directory / "sample.sv").write_text("""
module sample #(parameter int Count = 4) (
 input logic clk_i,
 output logic [Count-1:0][7:0] data_o
);
 logic [15:0] words [0:1];
 logic ready_o, valid_o;
 // logic invented_o;
endmodule
module other;
 logic elsewhere;
endmodule
""", encoding="utf-8")
    wave = {"test": {
        "source": {"signal": [{"name": "data_o[2][3:0]", "wave": "x=..", "data": ["nibble"]}]},
        "signals": {"data_o[2][3:0]": {
            "file": "rtl/sample.sv", "scope": "sample", "symbol": "data_o",
            "meaning": "Selected data nibble.", "polarity": "data"}},
        "clock_domain": "clk_i", "review_note": "Example control review.",
        "note": "Illustrative stimulus.", "review_sources": ["rtl/sample.sv"],
    }}
    return tmp_path, wave


def rename(wave, name, symbol=None):
    value = wave["test"]
    old = value["source"]["signal"][0]["name"]
    value["signals"][name] = value["signals"].pop(old)
    value["source"]["signal"][0]["name"] = name
    value["signals"][name]["symbol"] = symbol or name.split("[")[0]


def test_scoped_packed_selection_and_declaration_evidence(example):
    root, wave = example
    signal = validate_waveforms(wave, root)["waveforms"]["test"]["signals"][0]
    assert signal["width"] == 4
    assert signal["direction"] == "output"
    assert signal["line"] == 4


def test_unpacked_array_and_comma_declarations(example):
    root, wave = example
    rename(wave, "words[1][7:0]")
    assert validate_waveforms(wave, root)["waveforms"]["test"]["signals"][0]["width"] == 8
    rename(wave, "valid_o")
    wave["test"]["source"]["signal"][0] = {"name": "valid_o", "wave": "010."}
    assert validate_waveforms(wave, root)["waveforms"]["test"]["signals"][0]["width"] == 1


@pytest.mark.parametrize("name", ["data_o[4]", "data_o[0][8]", "data_o[1][8:0]", "words[2]", "words"])
def test_invalid_bit_or_array_selection_is_rejected(example, name):
    root, wave = example
    rename(wave, name)
    with pytest.raises(ValueError, match="selection|array elements"):
        validate_waveforms(wave, root)


@pytest.mark.parametrize("name", ["invented_o", "elsewhere"])
def test_comments_and_other_modules_are_not_signal_declarations(example, name):
    root, wave = example
    rename(wave, name)
    with pytest.raises(ValueError, match="not declared"):
        validate_waveforms(wave, root)


@pytest.mark.parametrize("name", ["DATA", "configuration", "data / addr"])
def test_uppercase_or_behavior_only_labels_are_rejected(example, name):
    root, wave = example
    rename(wave, name)
    with pytest.raises(ValueError, match="lowercase|not declared"):
        validate_waveforms(wave, root)


def test_missing_duplicate_and_unused_bindings_are_rejected(example):
    root, wave = example
    for mode in ["missing", "duplicate", "unused"]:
        candidate = copy.deepcopy(wave)
        if mode == "missing":
            candidate["test"]["signals"].clear()
        elif mode == "duplicate":
            candidate["test"]["source"]["signal"] *= 2
        else:
            candidate["test"]["signals"]["unused"] = {}
        with pytest.raises(ValueError, match="provenance"):
            validate_waveforms(candidate, root)


def test_scalar_lane_cannot_be_mislabeled_as_multibit_bus(example):
    root, wave = example
    rename(wave, "ready_o")
    with pytest.raises(ValueError, match="scalar"):
        validate_waveforms(wave, root)


def test_unresolved_parameter_and_unreviewed_override_fail(example):
    root, wave = example
    wave["test"]["parameters"] = {"Count": 8}
    with pytest.raises(ValueError, match="parameter qualification"):
        validate_waveforms(wave, root)
    wave["test"]["parameter_note"] = "Reference instance has eight words."
    rename(wave, "data_o[7]")
    assert validate_waveforms(wave, root)["waveforms"]["test"]["signals"][0]["width"] == 8
