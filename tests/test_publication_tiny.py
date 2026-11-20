"""Historical Tiny publication contracts remain separate from the current book."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

import pytest

from publications import tiny_reference as tiny
from publication_history import ORIGINAL_BOOK, P5_CONTRACT, snapshot

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("revision", [ORIGINAL_BOOK, P5_CONTRACT])
def test_historical_publication_contracts(tmp_path, revision):
    historical = snapshot(tmp_path / "source", revision)
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "tests/test_publication_tiny.py",
         "--basetemp=" + str(tmp_path / "tests"), "--tb=short"],
        cwd=historical, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}, timeout=180,
    )
    (tmp_path / "historical-tests.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout
    assert " passed" in result.stdout and " skipped" not in result.stdout


def test_current_source_cannot_relabel_historical_publication():
    config = tiny.read(ROOT / tiny.BOOK / "tiny.json")
    assert config["version"] == "0.2"
    old = dict(config, source_revision="9c706ba0ff1da1028c299cfff573010a86dfd7ce")
    with pytest.raises(ValueError, match="technical sources differ"):
        tiny.collect(old)


def test_address_map_covers_decoded_windows_and_gaps():
    config = tiny.read(ROOT / tiny.BOOK / "tiny.json")
    reset, regions, topology = tiny.validate_maps(ROOT, tiny.facts(profile_path=config["profile"]))
    model = tiny.address_map_model(reset, regions, topology["main_sram"])
    assert model["reset"] == 0
    left = model["overview"]
    assert (left[0]["end"], left[-1]["base"]) == (0xFFFFFFFF, 0)
    assert [row["symbol"] for row in left if row["kind"] == "memory"] == ["XPI", "SRAM", "FLASH"]
    assert sum(row["kind"] == "unmapped" for row in left) == 5

    decoded = [row for row in left if row["kind"] == "memory"]
    panels = model["apb_groups"]
    assert [(p["base"], p["end"]) for p in panels] == [(0x20000000, 0x20006FFF), (0x10000000, 0x1002FFFF)]
    assert [len(p["bands"]) for p in panels] == [7, 24]
    for panel, count in zip(panels, (6, 18), strict=True):
        rows = panel["bands"]
        assert (rows[0]["end"], rows[-1]["base"]) == (panel["end"], panel["base"])
        windows = [row for row in rows if row["kind"] == "apb-window"]
        assert len(windows) == count
        decoded.extend(windows)
    assert len(decoded) == len(regions) == 27
    assert {(r["symbol"], r["base"], r["end"]) for r in decoded} == {
        (r["symbol"], r["base"], r["end"]) for r in regions
    }
    clint = next(r for r in decoded if r["symbol"] == "APB4_CLINT")
    assert clint["size"] == 64 * 1024
    assert next(t for t in topology["apb_targets"] if t["name"] == "gpio")["regions"] == [
        "APB4_GPIO", "APB4_GPIO_ADMIN"
    ]

    banks = model["sram_banks"]
    assert [(r["name"], r["base"], r["end"]) for r in banks] == [
        ("B3", 0x30018000, 0x3001FFFF), ("B2", 0x30010000, 0x30017FFF),
        ("B1", 0x30008000, 0x3000FFFF), ("B0", 0x30000000, 0x30007FFF),
    ]
    for rows in (left, banks, *(p["bands"] for p in panels)):
        assert all(lower["end"] + 1 == upper["base"] for upper, lower in zip(rows, rows[1:]))


def test_address_map_rejects_overlapping_windows_and_incomplete_sram():
    config = tiny.read(ROOT / tiny.BOOK / "tiny.json")
    reset, regions, topology = tiny.validate_maps(ROOT, tiny.facts(profile_path=config["profile"]))
    with pytest.raises(ValueError, match="SRAM groups do not cover"):
        tiny.address_map_model(reset, regions, dict(topology["main_sram"], groups=3))
    gpio = next(r for r in regions if r["symbol"] == "APB4_GPIO")
    uart = next(r for r in regions if r["symbol"] == "APB4_UART0")
    uart["base"] = gpio["base"]
    with pytest.raises(ValueError, match="overlapping or invalid"):
        tiny.address_map_model(reset, regions, topology["main_sram"])


@pytest.mark.parametrize("before,after", [
    ("s_req_q.write_done && !s_req_q.b_captured", "1'b1"),
    ("s_r_valid && s_rready[s_req_q.owner] && s_r_data[4]", "s_r_valid"),
    (".flush_i(1'b0)", ".flush_i(!enable_i)"),
])
def test_current_reset_binding_still_rejects_unsafe_completion(tmp_path, before, after):
    contract = tiny.read(ROOT / tiny.BOOK / "source-contract.json")
    binding = next(item for item in contract["bindings"]
                   if item["file"] == "rtl/tiny/top/tiny_axi4_target.sv")
    path = tmp_path / binding["file"]
    path.parent.mkdir(parents=True)
    original = (ROOT / binding["file"]).read_text()
    assert before in original
    path.write_text(original.replace(before, after))
    with pytest.raises(ValueError, match="Tiny behavior binding changed"):
        tiny.require_snippets(tmp_path, binding["file"], binding["text"])
