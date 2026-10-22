"""Historical Tiny publication contracts remain separate from P6 source support."""
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
    assert config["source_revision"] == "9c706ba0ff1da1028c299cfff573010a86dfd7ce"
    with pytest.raises(ValueError, match="DMA parameters changed"):
        tiny.collect(config)


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
