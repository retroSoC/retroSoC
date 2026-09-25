"""Focused RTL coverage for the APU-P9 physical storage transactions."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def test_apu_p9_production_storage_inventory() -> None:
    multimedia = ROOT / "rtl/ip/multimedia"
    engine = (multimedia / "apu_kws_engine.sv").read_text(encoding="utf-8")
    model_loader = (multimedia / "apu_kws_model_loader.sv").read_text(encoding="utf-8")
    microcode_loader = (multimedia / "apu_microcode_loader.sv").read_text(encoding="utf-8")
    coefficient_store = (multimedia / "apu_kws_coeff_store.sv").read_text(encoding="utf-8")
    proof_memo = (multimedia / "apu_proof_memo.sv").read_text(encoding="utf-8")

    assert 'include "apu_kws_rom.svh"' not in engine
    assert 'include "apu_kws_apum_profile.svh"' not in model_loader
    assert "s_key_mem" not in microcode_loader
    assert "localparam int unsigned BankCount = 15" in coefficient_store
    assert "for (genvar bank = 0; bank < BankCount; bank++)" in coefficient_store
    assert proof_memo.count("tc_sram_1024x32") == 3
    assert "for (genvar bank = 0; bank < 8; bank++)" in proof_memo
    assert "u_valid_bitmap_sram" in proof_memo

    inventory = {
        "control_store": 8,
        "codec_common_data": 12,
        "kws_model_scratch": 16,
        "loader_path_stack": 8,
        "verifier_memo": 17,
        "coefficient_store": 15,
    }
    assert sum(inventory.values()) == 76
    assert sum(inventory.values()) * 4 == 304


def test_apu_p9_coefficient_store_and_proof_memo(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        pytest.fail("APU-P9 storage validation requires locked iverilog, vvp, and sv2v tools")
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p9_storage.fl"
    source_list.write_text(
        "\n".join(
            (
                f"+incdir+{multimedia}",
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(multimedia / "apu_kws_coeff_store.sv"),
                str(multimedia / "apu_proof_memo.sv"),
                str(ROOT / "tests/rtl/apu_p9_storage_tb.sv"),
                "",
            )
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p9_storage.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "apu_p9_storage"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p9_storage_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P9 coefficient store and proof memo test passed" in result.stdout
