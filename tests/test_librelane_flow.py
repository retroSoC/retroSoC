"""Tests for the single-level IHP130 LibreLane pad-ring flow."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
PIN_MAP = ROOT / "rtl/mini/pin_map/pin_map.json"
DOMAINS = ROOT / "rtl/mini/integration/clock_reset_domains.json"
FLOW_ROOT = ROOT / "physical/librelane"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def chip_arguments(tmp_path: Path) -> SimpleNamespace:
    return SimpleNamespace(
        pin_map=PIN_MAP,
        rtl=tmp_path / "retrosoc_asic_sources.sv",
        sdc=tmp_path / "retrosoc_asic.sdc",
        pdn=FLOW_ROOT / "pdn_cfg.tcl",
        bondpad_gds=tmp_path / "bondpad_70x70.gds",
        bondpad_lef=FLOW_ROOT / "bondpad/bondpad_70x70.lef",
        sram_vh=FLOW_ROOT / "sram_blackboxes.vh",
        ext_clk_hz=72_000_000,
        aud_clk_hz=18_432_000,
        have_pll=False,
        output=tmp_path / "config.json",
    )


def test_chip_config_places_every_signal_and_power_pad_once(tmp_path: Path) -> None:
    module = load_module("retrosoc_librelane_config", FLOW_ROOT / "scripts/generate_chip_config.py")
    config = module.build_config(chip_arguments(tmp_path))
    sides = {name: config[f"PAD_{name.upper()}"] for name in module.SIDE_ORDER}
    placed = [instance for side in module.SIDE_ORDER for instance in sides[side]]

    assert len(placed) == 189
    assert len(placed) == len(set(placed))
    assert {side: len(instances) for side, instances in sides.items()} == {
        "south": 30,
        "east": 52,
        "north": 48,
        "west": 59,
    }
    assert sum(item.startswith("vdd_pads\\[") for item in placed) == 24
    assert sum(item.startswith("vss_pads\\[") for item in placed) == 24
    assert sum(item.startswith("iovdd_pads\\[") for item in placed) == 16
    assert sum(item.startswith("iovss_pads\\[") for item in placed) == 16
    assert "u_extclk_i_pad.u_sg13g2_IOPadIn" in sides["south"]
    assert "u_gpio_31_io_pad.u_sg13g2_IOPadInOut4mA" in sides["east"]
    assert "u_sdram_dq15_io_pad.u_sg13g2_IOPadInOut4mA" in sides["west"]
    assert config["DIE_AREA"] == [0, 0, 8000, 8000]
    assert config["CORE_AREA"] == [365, 365, 7635, 7635]
    assert config["VDD_NETS"] == ["VDD", "IOVDD"]
    assert config["GND_NETS"] == ["VSS", "IOVSS"]
    assert set(config["MACROS"]) == {
        "RM_IHPSG13_1P_4096x16_c3_bm_bist",
        "RM_IHPSG13_1P_4096x8_c3_bm_bist",
    }
    assert len(config["PDN_MACRO_CONNECTIONS"]) == 6


def test_chip_sdc_is_pad_aware_and_does_not_false_path_all_io(tmp_path: Path) -> None:
    module = load_module("retrosoc_librelane_sdc", FLOW_ROOT / "scripts/generate_sdc.py")
    arguments = SimpleNamespace(
        domains=DOMAINS,
        pin_map=PIN_MAP,
        ext_clk_hz=72_000_000,
        aud_clk_hz=18_432_000,
        have_pll=False,
    )
    sdc = module.render(arguments)

    assert "u_extclk_i_pad.u_sg13g2_IOPadIn/p2c" in sdc
    assert "u_usb2_ulpi_clk_i_pad.u_sg13g2_IOPadIn/p2c" in sdc
    assert "create_generated_clock -name clk_system" in sdc
    assert "set_clock_groups -name retrosoc_async -asynchronous" in sdc
    assert "set_input_delay -max" in sdc
    assert "set_output_delay -max" in sdc
    assert "set_false_path -from $reset_ext_rst_n_i_pad" in sdc
    assert "set_false_path -from [all_inputs]" not in sdc
    assert "set_false_path -to [all_outputs]" not in sdc


def test_librelane_flow_is_single_level_chip_only() -> None:
    makefile = (FLOW_ROOT / "Makefile").read_text(encoding="utf-8")
    top_makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text())

    assert "librelane-chip:" in makefile
    assert "librelane-core" not in makefile
    assert "librelane-all" not in makefile
    assert "include physical/librelane/Makefile" in top_makefile
    ihp_filelist = (ROOT / "rtl/filelist/pdk_ihp130.fl").read_text(encoding="utf-8")
    assert ihp_filelist.index("sg13g2_udp.v") < ihp_filelist.index("sg13g2_stdcell.v")
    assert lock["sources"]["pdk_ihp130"]["revision"] == ("970a7688e7dcce2a6172797df9ef47bde2f60f9f")


def test_bondpad_lef_matches_the_generated_master_contract() -> None:
    lef = (FLOW_ROOT / "bondpad/bondpad_70x70.lef").read_text(encoding="utf-8")

    assert "MACRO bondpad_70x70" in lef
    assert "CLASS COVER" in lef
    assert "SIZE 70.0 BY 70.0" in lef
    assert "SITE sg13g2_ioSite" in lef
