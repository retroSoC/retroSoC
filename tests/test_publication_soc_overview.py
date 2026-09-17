"""Dense overview labels and fan-in must stay tied to current PRODUCT sources."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from publications.soc_diagram_reference import validate_soc_diagram

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def diagram():
    return json.loads((ROOT / "publications/datasheets/soc-architecture.json").read_text(encoding="utf-8"))


def test_dense_overview_retains_instances_and_independent_gateway_fan_in(diagram):
    validate_soc_diagram(ROOT, diagram)
    assert diagram["font_weight"] == 400
    assert [len(gateway["members"]) for gateway in diagram["gateways"]] == [3, 2]
    assert len(diagram["masters"]) == 9
    nodes = {node["id"]: node for node in diagram["nodes"]}
    assert nodes["sram"]["domain"] == nodes["monitor"]["domain"] == "hp"
    assert nodes["gwa"]["domain"] == nodes["gwb"]["domain"] == "pclk"
    assert {nodes[id]["domain"] for id in ["sdram", "qpi", "opi", "xpi"]} == {"memory"}
    assert diagram["pclk_parent"] == "lp"


@pytest.mark.parametrize("mutation", ["bold", "small-font", "module-width-label", "wire-width-label",
                                      "gateway-input", "gateway-output", "gateway-source", "bridge-width",
                                      "printed-width", "bus-width", "clock-domain", "clock-pin", "clock-parent",
                                      "interface-source", "interface-token", "interface-af", "interface-bus",
                                      "ip-coverage", "instance-coverage", "stream-source", "missing-source"])
def test_overview_rejects_visual_claims_that_contradict_its_scope_or_sources(diagram, mutation):
    nodes = {node["id"]: node for node in diagram["nodes"]}
    if mutation == "bold":
        diagram["font_weight"] = 700
    elif mutation == "small-font":
        diagram["font_size_pt"] = 8
    elif mutation == "module-width-label":
        nodes["dma"]["label"] += " AXI32"
    elif mutation == "wire-width-label":
        diagram["edges"][0]["label"] = "AXI64"
    elif mutation == "gateway-input":
        diagram["edges"] = [edge for edge in diagram["edges"] if not (edge["from"] == "apu" and edge["to"] == "gwa")]
    elif mutation == "gateway-output":
        edge = copy.deepcopy(next(edge for edge in diagram["edges"] if edge["from"] == "gwa"))
        edge["to"] = "hp_bus"
        diagram["edges"].append(edge)
    elif mutation == "gateway-source":
        diagram["gateways"][0]["members"]["icache"]["signal"] = "jpeg_axi4"
    elif mutation == "bridge-width":
        diagram["bridges"][0]["input_bits"] = 32
    elif mutation == "printed-width":
        nodes["gca"]["label"] = "AXI64→AXI32 / CDC"
    elif mutation == "bus-width":
        nodes["hp_bus"]["label"] = "HP data interconnect · AXI32"
    elif mutation == "clock-domain":
        nodes["sram"]["domain"] = "pclk"
    elif mutation == "clock-pin":
        nodes["sram"]["clock"]["signal"] = "clk_lp_i"
    elif mutation == "clock-parent":
        diagram["pclk_parent"] = "hp"
    elif mutation == "interface-source":
        diagram["interfaces"][0]["source"] = "missing.sv"
    elif mutation == "interface-token":
        diagram["interfaces"][0]["tokens"] = ["nonexistent_pin"]
    elif mutation == "interface-af":
        next(row for row in diagram["interfaces"] if "af_prefix" in row)["af_prefix"] = "u_nonexistent_if."
    elif mutation == "interface-bus":
        next(row for row in diagram["interfaces"] if "pin_bus" in row)["pin_bus"]["count"] += 1
    elif mutation == "ip-coverage":
        nodes["crypto"]["ips"] = []
    elif mutation == "instance-coverage":
        nodes["i2c1"]["id"] = "merged-i2c"
    elif mutation == "stream-source":
        diagram["stream_bindings"][0]["ports"]["i2s_tx_axis"] = "wrong_stream"
    else:
        diagram["sources"].remove("rtl/mini/pin_map/pin_map.json")
    with pytest.raises(ValueError, match="SoC diagram"):
        validate_soc_diagram(ROOT, diagram)
