import json
from pathlib import Path

import pytest

from publications import r1_specifications as specs


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def inputs():
    source = json.loads((ROOT / specs.CATALOG).read_text(encoding="utf-8"))
    family = json.loads((ROOT / specs.CATALOG.with_name("r1-roadmap.json")).read_text(encoding="utf-8"))
    return source, family["products"], {"profile_path": "configs/ci/ics55-tiny.mk", "sram": {"CapacityKiB": 128}}


def test_source_identity_values_and_states(inputs):
    catalog = inputs[0]
    specs.verify_sources(ROOT, catalog["sources"])
    result = specs.resolve(*inputs)
    assert [topic["key"] for topic in result["topics"]] == list(specs.TOPICS)
    assert sum(len(topic["metrics"]) for topic in result["topics"]) == 32
    facts = result["metrics"]
    assert [facts["cpu-count"]["cells"][p]["value"] for p in specs.MODELS] == [1, 2, 3, 5, 18, 36]
    assert [facts["gpu-cores"]["cells"][p]["state"] for p in specs.MODELS] == ["None", "None", "TBD", "TBD", "target", "target"]
    assert facts["mac-lanes"]["cells"]["MINI"]["value"] == "64 dense + 8 depthwise"
    assert facts["sram"]["cells"]["MINI"]["display"] == "32 KiB"
    assert facts["system-memory"]["cells"]["MINI"]["display"] == "64 MiB SDRAM window"
    assert facts["system-memory"]["cells"]["TINY"]["depends_on"] == "r1.tiny.sram"
    for name, gpu, neural, memory, bandwidth, prores in (
        ("MAX", 40, 16, "128 GB unified", "614 GB/s", 2), ("ULTRA", 80, 32, "512 GB unified", "1.2 TB/s", 4)
    ):
        assert facts["gpu-cores"]["cells"][name]["value"] == gpu
        assert facts["graphics"]["cells"][name]["display"] == f"{gpu}-core GPU"
        assert facts["neural-cores"]["cells"][name]["value"] == neural
        assert facts["system-memory"]["cells"][name]["display"] == memory
        assert facts["bandwidth"]["cells"][name]["display"] == bandwidth
        assert facts["prores"]["cells"][name]["value"] == prores
        assert facts["drivers"]["cells"][name]["value"] is None
        assert facts["int8-tops"]["cells"][name]["state"] == "TBD"
        for metric in ("gpu-cores", "neural-cores", "system-memory", "bandwidth", "prores", "usb"):
            cell = facts[metric]["cells"][name]
            assert cell["state"] == "target" and cell["source"].startswith("concept-")


@pytest.mark.parametrize("fault", ["wrong-soc", "positioning", "missing", "role", "absence", "zero", "derived-unknown", "capacity"])
def test_invalid_specifications_fail(inputs, fault):
    catalog, _, facts = inputs
    rows = catalog["metrics"]
    if fault == "wrong-soc":
        rows["mac-lanes"]["cells"]["MINI"]["source"] = "tiny-topology"
    elif fault == "positioning":
        rows["gpu-cores"]["cells"]["MAX"] = {"value": 40, "source": "family-status"}
    elif fault == "missing":
        del rows["int8-tops"]["cells"]["STD"]
    elif fault == "role":
        rows["core-layout"]["cells"]["PRO"]["management"] = 0
    elif fault == "absence":
        rows["gpu-cores"]["cells"]["STD"] = "None"
    elif fault == "zero":
        rows["gpu-cores"]["cells"]["STD"] = 0
    elif fault == "derived-unknown":
        rows["gpu-cores"]["cells"]["MAX"] = None
    else:
        facts["sram"]["CapacityKiB"] = 32
    with pytest.raises(ValueError):
        specs.resolve(*inputs)


def test_all_four_pages_bind_a_fixed_grid_and_paired_rows(inputs):
    data = specs.resolve(*inputs)
    regions, headings, items = [], [], []
    master = dict(width=75.12, height=75.12, scale=0.637)
    for page, topic in enumerate(data["topics"], 404):
        regions.append(dict(kind="spec-plate", page=page, x=54, y=90, width=489, height=700))
        headings.append(dict(label=f"<tiny-family-{topic['key']}>", page=page))
        regions.extend(dict(kind="spec-chip", page=page, x=59+79*i, y=190, **master) for i in range(6))
        for group in (0, 1):
            items.extend(dict(kind="r1-spec-row", page=page, topic=topic["key"], metric=m,
                              group=group, top=350+30*i) for i, m in enumerate(topic["metrics"]))
    headings.append(dict(label="<tiny-r1-roadmap>", page=408))
    assert len(specs.validate_pages(data, regions, headings, items, master)) == 4
    items[-1]["top"] += 1
    with pytest.raises(ValueError, match="align"):
        specs.validate_pages(data, regions, headings, items, master)
    items[-1]["top"] -= 1
    regions[-1]["x"] += 1
    with pytest.raises(ValueError, match="fixed"):
        specs.validate_pages(data, regions, headings, items, master)
