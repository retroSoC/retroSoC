"""Std-series VexiiRiscv generator preservation contract tests."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts/vexiiriscv/GenerateRetroSocStd.scala"
DRIVER = ROOT / "scripts/generate_vexiiriscv.py"
LOCK = ROOT / "dependencies/dependencies.lock.json"


def test_std_generator_scala_preserves_the_frozen_hp_configuration() -> None:
    assert GENERATOR.is_file()
    generator = GENERATOR.read_text(encoding="utf-8")

    assert "object GenerateRetroSocStd extends App" in generator
    assert 'setDefinitionName("vexiiriscv_std_generated")' in generator
    assert "param.resetVector = 0x38000000L" in generator
    assert "param.plugins(hartId = 1)" in generator
    assert "param.xlen = 64" in generator

    for base, size in (
        ("0x00000000L", "0x01000000L"),
        ("0x02000000L", "0x2E000000L"),
        ("0x30000000L", "0x00020000L"),
        ("0x38000000L", "0x04000000L"),
        ("0x40000000L", "0x02000000L"),
        ("0x48000000L", "0x08000000L"),
    ):
        assert f"SizeMapping({base}, {size})" in generator


def test_std_driver_pins_the_std_generator_and_module_names() -> None:
    driver = DRIVER.read_text(encoding="utf-8")

    assert 'GENERATOR_CLASS = "vexiiriscv.GenerateRetroSocStd"' in driver
    assert 'GENERATED_MODULE = "vexiiriscv_std_generated"' in driver
    assert '"configuration": "rv64imafdc_zicbom_max"' in driver
    assert '"product": "std"' in driver
    assert "GenerateRetroSocStd.scala" in driver


def test_vexiiriscv_lock_entry_remains_a_locked_std_asset() -> None:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    vexii = lock["sources"]["vexiiriscv"]

    assert re.fullmatch(r"[0-9a-f]{40}", vexii["revision"])
    assert vexii["destination"].startswith(".cache/")
