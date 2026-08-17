"""Tests for Yosys recipe selection and ABC period derivation."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from scripts.yosys_period import period_ps


ROOT = Path(__file__).resolve().parents[1]
DOMAINS = ROOT / "rtl/mini/integration/clock_reset_domains.json"
PERIOD_HELPER = ROOT / "scripts/yosys_period.py"
YOSYS_SCRIPTS = ROOT / "physical/smoke/syn/yosys/script"


def run_period(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(PERIOD_HELPER), *args],
        text=True,
        capture_output=True,
    )


def test_yosys_period_rounds_external_sta_period() -> None:
    assert period_ps({"domains": [{"name": "external", "sta": {"period_ns": 13.888888889}}]}) == 13889

    result = run_period("--domains", str(DOMAINS))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "13889"


def test_yosys_period_rejects_unknown_domain() -> None:
    result = run_period("--domains", str(DOMAINS), "--domain", "missing")
    assert result.returncode != 0
    assert "domain missing is not declared" in result.stderr


def test_yosys_recipe_scripts_and_public_slot_are_stable() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    yosys_mk = (ROOT / "physical/smoke/syn/yosys/yosys.mk").read_text(encoding="utf-8")
    synth_tcl = (YOSYS_SCRIPTS / "synth.tcl").read_text(encoding="utf-8")
    opensta = (ROOT / "physical/smoke/sta/opensta/opensta.mk").read_text(encoding="utf-8")
    iverilog = (ROOT / "rtl/mini/mk/iverilog.mk").read_text(encoding="utf-8")
    vcs = (ROOT / "rtl/mini/mk/vcs.mk").read_text(encoding="utf-8")

    assert "SYNTH_RECIPE ?= balanced" in makefile
    assert "VALID_SYNTH_RECIPE  := balanced area speed" in makefile
    assert "syn/yosys-$(SYNTH_RECIPE)" in makefile
    assert "CONFIG_KEY_VARS" in makefile
    assert "SYNTH_RECIPE" not in makefile.split("CONFIG_KEY_VARS", 1)[1].split("VARIANT_ID", 1)[0]
    assert "--env SYNTH_RECIPE=$(SYNTH_RECIPE)" in yosys_mk
    assert "--env YOSYS_TARGET_PERIOD_PS=$(YOSYS_TARGET_PERIOD_PS)" in yosys_mk
    assert "abc_${synth_recipe}.script" in synth_tcl
    assert "yosys abc {*}$tech_cells_args -D $period_ps -script $abc_script -constr $abc_constr" in synth_tcl
    assert "S110" not in synth_tcl
    assert "$(VARIANT_ROOT)/syn/yosys/out/retrosoc_asic_yosys.v" in opensta
    assert "$(VARIANT_ROOT)/syn/yosys/out/retrosoc_asic_yosys.v" in iverilog
    assert "$(VARIANT_ROOT)/syn/yosys/out/retrosoc_asic_yosys.v" in vcs
    assert "SYN_BUILD_ROOT" not in opensta
    assert "SYN_BUILD_ROOT" not in iverilog.split("NETLIST_PATH", 1)[1][:200]
    assert (YOSYS_SCRIPTS / "abc_balanced.script").read_text(encoding="utf-8").count("&nf {D}") == 1
    assert "&nf {D}" not in (YOSYS_SCRIPTS / "abc_area.script").read_text(encoding="utf-8")
    assert (YOSYS_SCRIPTS / "abc_speed.script").read_text(encoding="utf-8").count("&nf {D}") == 6
    leftover = {
        "abc-opt.script",
        "abc.constr",
        "cell_dont_use.py",
        "filter_output.awk",
    }
    assert leftover.isdisjoint({path.name for path in YOSYS_SCRIPTS.iterdir()})
    assert not (ROOT / "physical/smoke/syn/dc").exists()
    assert not (ROOT / "physical/smoke/syn/Makefile").exists()
