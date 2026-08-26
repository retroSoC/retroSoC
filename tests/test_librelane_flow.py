"""Tests for IHP130 LibreLane core and pad-ring flows."""

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
    assert sum(item.startswith("vdd_pads[") for item in placed) == 24
    assert sum(item.startswith("vss_pads[") for item in placed) == 24
    assert sum(item.startswith("iovdd_pads[") for item in placed) == 16
    assert sum(item.startswith("iovss_pads[") for item in placed) == 16
    assert "u_extclk_i_pad.u_sg13g2_IOPadIn" in sides["south"]
    assert "u_gpio_31_io_pad.u_sg13g2_IOPadInOut4mA" in sides["east"]
    assert "u_sdram_dq15_io_pad.u_sg13g2_IOPadInOut4mA" in sides["west"]
    assert config["DIE_AREA"] == [0, 0, 8000, 8000]
    assert config["CORE_AREA"] == [365, 365, 7635, 7635]
    assert config["PL_TARGET_DENSITY_PCT"] == 45
    assert config["USE_SLANG"] is True
    assert config["SLANG_ARGUMENTS"] == ["--keep-hierarchy"]
    assert config["VERILOG_POWER_DEFINE"] is None
    assert config["SYNTH_SHARE_RESOURCES"] is False
    assert config["SYNTH_HIERARCHY_MODE"] == "deferred_flatten"
    assert config["SYNTH_KEEP_HIERARCHY_MODULES"] == [
        "sg13g2_IOPadVdd",
        "sg13g2_IOPadVss",
        "sg13g2_IOPadIOVdd",
        "sg13g2_IOPadIOVss",
    ]
    assert config["YOSYS_LOG_LEVEL"] == "WARNING"
    assert config["SYNTH_STRATEGY"] == "AREA 3"
    assert config["RUN_POST_GPL_DESIGN_REPAIR"] is False
    assert config["RUN_CTS"] is False
    assert config["RUN_POST_CTS_RESIZER_TIMING"] is False
    assert config["EXTRA_EXCLUDED_CELLS"] == ["sg13g2_IOPad*"]
    assert config["VDD_NETS"] == ["VDD"]
    assert config["GND_NETS"] == ["VSS"]
    assert config["PAD_CFG"].endswith("physical/librelane/pad_cfg.tcl")
    assert config["PDN_ENABLE_PINS"] is True
    assert config["ERROR_ON_PDN_VIOLATIONS"] is True
    assert config["STA_EXTRA_CORNER_TCL_FILE"].endswith(
        "physical/librelane/sta_report_limit.tcl"
    )
    assert set(config["MACROS"]) == {
        "RM_IHPSG13_1P_4096x16_c3_bm_bist",
        "RM_IHPSG13_1P_4096x8_c3_bm_bist",
    }
    assert len(config["PDN_MACRO_CONNECTIONS"]) == 6


def test_core_config_uses_a_padless_classic_flow(tmp_path: Path) -> None:
    module = load_module(
        "retrosoc_librelane_core_config", FLOW_ROOT / "scripts/generate_chip_config.py"
    )
    arguments = chip_arguments(tmp_path)
    arguments.target = "core"
    config = module.build_config(arguments)

    assert config["meta"] == {"version": 3, "flow": "Classic"}
    assert config["DESIGN_NAME"] == "retrosoc_core"
    assert config["DIE_AREA"] == [0, 0, 6000, 6000]
    assert config["CORE_AREA"] == [120, 120, 5880, 5880]
    assert config["PDN_CORE_RING_CONNECT_TO_PADS"] is False
    assert "PAD_CFG" not in config
    assert not any(key.startswith("PAD_") for key in config)
    assert "PAD_BONDPAD_NAME" not in config
    assert set(config["MACROS"]) == {
        "RM_IHPSG13_1P_4096x16_c3_bm_bist",
        "RM_IHPSG13_1P_4096x8_c3_bm_bist",
    }


def test_chip_config_includes_configured_onchip_sram_banks(tmp_path: Path) -> None:
    module = load_module(
        "retrosoc_librelane_sram_config", FLOW_ROOT / "scripts/generate_chip_config.py"
    )
    arguments = chip_arguments(tmp_path)
    arguments.have_sram_macro = True
    arguments.sram_size_kib = 32
    config = module.build_config(arguments)

    macro = config["MACROS"]["RM_IHPSG13_1P_1024x32_c2_bm_bist"]
    assert len(macro["instances"]) == 8
    assert "u_retrosoc.u_onchip_ram.gen_memory.gen_bank[0].u_ram.u_mem" in macro["instances"]
    assert "u_retrosoc.u_onchip_ram.gen_memory.gen_bank[7].u_ram.u_mem" in macro["instances"]
    assert any(
        "gen_bank.*0.*\\.u_ram" in connection
        for connection in config["PDN_MACRO_CONNECTIONS"]
    )
    blackboxes = (FLOW_ROOT / "sram_blackboxes.vh").read_text(encoding="utf-8")
    assert "module RM_IHPSG13_1P_1024x32_c2_bm_bist" in blackboxes


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
    assert "u_rcu.u_sys_clk_buf.u_sg13g2_buf_1/X" in sdc
    assert "create_generated_clock -name clk_system" in sdc
    assert "set_clock_groups -name retrosoc_async -asynchronous" in sdc
    assert "set_propagated_clock" not in sdc
    assert "set_input_delay -max" in sdc
    assert "set_output_delay -max" in sdc
    assert "set_false_path -from $reset_ext_rst_n_i_pad" in sdc
    assert "set_false_path -from [all_inputs]" not in sdc
    assert "set_false_path -to [all_outputs]" not in sdc


def test_core_sdc_constrains_logical_top_ports(tmp_path: Path) -> None:
    module = load_module("retrosoc_librelane_core_sdc", FLOW_ROOT / "scripts/generate_sdc.py")
    arguments = SimpleNamespace(
        domains=DOMAINS,
        pin_map=PIN_MAP,
        ext_clk_hz=72_000_000,
        aud_clk_hz=18_432_000,
        have_pll=False,
        target="core",
    )
    sdc = module.render(arguments)

    assert 'require_ports "clock external" {extclk_i_pad}' in sdc
    assert 'require_ports "clock usb2_ulpi" {usb2_ulpi_clk_i_pad}' in sdc
    assert "u_extclk_i_pad.u_sg13g2_IOPadIn/p2c" not in sdc
    assert "u_rcu.u_sys_clk_buf.u_sg13g2_buf_1/X" in sdc


def test_librelane_flow_exposes_core_and_chip_targets() -> None:
    makefile = (FLOW_ROOT / "Makefile").read_text(encoding="utf-8")
    top_makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text())

    assert "librelane-chip:" in makefile
    assert "librelane-core:" in makefile
    assert "librelane-core-package:" in makefile
    assert "LIBRELANE_TARGET         ?= chip" in makefile
    assert "LIBRELANE_COMMAND       := $(LIBRELANE_PYTHON) -m librelane" in makefile
    assert "--skip OpenROAD.STAMidPNR" in makefile
    assert "--librelane-safe" in makefile
    assert "librelane-all" not in makefile
    assert "include physical/librelane/Makefile" in top_makefile
    ihp_filelist = (ROOT / "rtl/filelist/pdk_ihp130.fl").read_text(encoding="utf-8")
    assert ihp_filelist.index("sg13g2_udp.v") < ihp_filelist.index("sg13g2_stdcell.v")
    assert lock["sources"]["pdk_ihp130"]["revision"] == ("970a7688e7dcce2a6172797df9ef47bde2f60f9f")
    doctor = (FLOW_ROOT / "scripts/doctor.py").read_text(encoding="utf-8")
    assert 'EXPECTED_OPENSTA_VERSION = "3.0.0"' in doctor


def test_bondpad_lef_matches_the_generated_master_contract() -> None:
    lef = (FLOW_ROOT / "bondpad/bondpad_70x70.lef").read_text(encoding="utf-8")

    assert "MACRO bondpad_70x70" in lef
    assert "CLASS COVER" in lef
    assert "SIZE 70.0 BY 70.0" in lef
    assert "SITE sg13g2_ioSite" in lef


def test_sta_report_wrapper_caps_only_expanded_path_enumeration() -> None:
    wrapper = (FLOW_ROOT / "sta_report_limit.tcl").read_text(encoding="utf-8")
    assert "set ::retrosoc_sta_group_path_count 10" in wrapper
    assert "OpenSTA executable" in wrapper
    assert "rename report_checks ::retrosoc_report_checks" in wrapper
    assert "lsearch -exact $args -group_path_count" in wrapper
    assert "lappend args -group_path_count" in wrapper
    assert "rename report_check_types ::retrosoc_report_check_types" in wrapper
    assert "lsearch -exact $args -violators" in wrapper
    assert "rename report_parasitic_annotation" in wrapper
    assert "lsearch -exact $args -report_unannotated" in wrapper
    assert "::retrosoc_report_checks" in wrapper


def test_pdn_connects_all_ihp_pad_power_rails() -> None:
    pdn = (FLOW_ROOT / "pdn_cfg.tcl").read_text(encoding="utf-8")

    assert "findNet $vdd" in pdn
    assert "findNet $gnd" in pdn
    assert "foreach {net signal_type} {IOVDD POWER IOVSS GROUND}" in pdn
    pad_cfg = (FLOW_ROOT / "pad_cfg.tcl").read_text(encoding="utf-8")
    assert "make_instance $instance_name $master" in pad_cfg
    assert "proc reconnect_ihp_padring_rails" in pdn
    assert "odb::dbITerm_connect $iterm $net" in pdn
    assert "set stdcell_grid_args [list]" in pdn
    assert '-pins "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"' in pdn
    assert "odb::dbTechLayer_setDirection" not in pdn
    assert "Metal4 HORIZONTAL" not in pdn
    assert '-layers "Metal2 Metal3"' in pdn
    assert "-extend_to_core_ring" in pdn
    assert "-connect_to_pad_layers TopMetal2" in pdn
    assert '-layers "Metal3 Metal4"' in pdn
    assert "-layer Metal4" in pdn
    assert "-net $::env(VDD_NET) -inst_pattern .* -pin_pattern vdd -power" in pdn
    assert "-net $::env(GND_NET) -inst_pattern .* -pin_pattern vss -ground" in pdn
    assert "-net IOVDD -inst_pattern .* -pin_pattern iovdd -power" in pdn
    assert "-net IOVSS -inst_pattern .* -pin_pattern iovss -ground" in pdn
