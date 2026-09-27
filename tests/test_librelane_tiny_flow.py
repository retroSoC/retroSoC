"""Tests for the Tiny IHP130 LibreLane chip flow."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
PIN_MAP = ROOT / "rtl/tiny/pin_map/pin_map.json"
DOMAINS = ROOT / "rtl/tiny/integration/clock_reset_domains.json"
FLOW_ROOT = ROOT / "physical/librelane/tiny"
BONDPAD_LEF = ROOT / "physical/librelane/bondpad/bondpad_70x70.lef"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def chip_arguments(tmp_path: Path) -> SimpleNamespace:
    return SimpleNamespace(
        pin_map=PIN_MAP,
        rtl=tmp_path / "retrosoc_tiny_asic_sources.sv",
        sdc=tmp_path / "retrosoc_tiny_chip.sdc",
        pdn=FLOW_ROOT / "pdn_cfg.tcl",
        bondpad_gds=tmp_path / "bondpad_70x70.gds",
        bondpad_lef=BONDPAD_LEF,
        sram_vh=FLOW_ROOT / "sram_blackboxes.vh",
        ext_clk_hz=24_000_000,
        have_sram_macro=True,
        sram_size_kib=128,
        output=tmp_path / "config.json",
    )


def test_chip_config_places_every_signal_and_power_pad_once(tmp_path: Path) -> None:
    module = load_module(
        "retrosoc_tiny_librelane_config", FLOW_ROOT / "scripts/generate_chip_config.py"
    )
    config = module.build_config(chip_arguments(tmp_path))
    sides = {name: config[f"PAD_{name.upper()}"] for name in module.SIDE_ORDER}
    placed = [instance for side in module.SIDE_ORDER for instance in sides[side]]

    assert len(placed) == 84
    assert len(placed) == len(set(placed))
    assert {side: len(instances) for side, instances in sides.items()} == {
        "south": 19,
        "east": 24,
        "north": 17,
        "west": 24,
    }
    assert sum(item.startswith("vdd_pads[") for item in placed) == 8
    assert sum(item.startswith("vss_pads[") for item in placed) == 8
    assert sum(item.startswith("iovdd_pads[") for item in placed) == 8
    assert sum(item.startswith("iovss_pads[") for item in placed) == 8
    assert "u_extclk_i_pad.u_sg13g2_IOPadIn" in sides["south"]
    assert "u_jtag_tck_i_pad.u_sg13g2_IOPadIn" in sides["south"]
    assert "u_uart0_tx_o_pad.u_sg13g2_IOPadOut4mA" in sides["south"]
    assert "u_xpi_sck_o_pad.u_sg13g2_IOPadOut4mA" in sides["north"]
    assert "u_gpio_0_io_pad.u_sg13g2_IOPadInOut4mA" in sides["east"]
    assert "u_gpio_15_io_pad.u_sg13g2_IOPadInOut4mA" in sides["east"]
    assert "u_gpio_16_io_pad.u_sg13g2_IOPadInOut4mA" in sides["west"]
    assert "u_gpio_31_io_pad.u_sg13g2_IOPadInOut4mA" in sides["west"]
    assert config["meta"] == {"version": 3, "flow": "Chip"}
    assert config["DESIGN_NAME"] == "retrosoc_tiny_asic"
    assert config["DIE_AREA"] == [0, 0, 4700, 4700]
    assert config["CORE_AREA"] == [365, 365, 4335, 4335]
    assert config["CLOCK_PORT"] == ["extclk_i_pad", "jtag_tck_i_pad"]
    assert config["CLOCK_PERIOD"] == 1_000_000_000 / 24_000_000
    assert config["PL_TARGET_DENSITY_PCT"] == 45
    assert config["USE_SLANG"] is True
    assert config["SLANG_ARGUMENTS"] == ["--keep-hierarchy"]
    assert config["SYNTH_HIERARCHY_MODE"] == "deferred_flatten"
    assert config["SYNTH_KEEP_HIERARCHY_MODULES"] == [
        "sg13g2_IOPadVdd",
        "sg13g2_IOPadVss",
        "sg13g2_IOPadIOVdd",
        "sg13g2_IOPadIOVss",
    ]
    assert config["RUN_CTS"] is False
    assert config["ERROR_ON_SYNTH_CHECKS"] is False
    assert config["EXTRA_EXCLUDED_CELLS"] == ["sg13g2_IOPad*"]
    assert config["VDD_NETS"] == ["VDD"]
    assert config["GND_NETS"] == ["VSS"]
    assert config["PAD_CFG"].endswith("physical/librelane/tiny/pad_cfg.tcl")
    assert config["PDN_ENABLE_PINS"] is True
    assert config["ERROR_ON_PDN_VIOLATIONS"] is True
    assert config["STA_EXTRA_CORNER_TCL_FILE"].endswith(
        "physical/librelane/tiny/sta_report_limit.tcl"
    )
    assert config["PAD_BONDPAD_NAME"] == "bondpad_70x70"
    assert set(config["MACROS"]) == {"RM_IHPSG13_1P_1024x32_c2_bm_bist"}


def test_chip_config_covers_every_onchip_sram_bank(tmp_path: Path) -> None:
    module = load_module(
        "retrosoc_tiny_librelane_sram_config", FLOW_ROOT / "scripts/generate_chip_config.py"
    )
    config = module.build_config(chip_arguments(tmp_path))

    macro = config["MACROS"]["RM_IHPSG13_1P_1024x32_c2_bm_bist"]
    assert len(macro["instances"]) == 32
    assert (
        "u_soc.u_sram.gen_memory.gen_bank[0].u_ram.u_mem" in macro["instances"]
    )
    assert (
        "u_soc.u_sram.gen_memory.gen_bank[31].u_ram.u_mem" in macro["instances"]
    )
    for instance in macro["instances"].values():
        x, y = instance["location"]
        assert 365 <= x <= 4335
        assert 365 <= y <= 4335
        assert instance["orientation"] == "N"
    assert len(config["PDN_MACRO_CONNECTIONS"]) == 64
    assert any(
        "gen_bank.*0.*\\.u_ram" in connection
        for connection in config["PDN_MACRO_CONNECTIONS"]
    )
    blackboxes = (FLOW_ROOT / "sram_blackboxes.vh").read_text(encoding="utf-8")
    assert "module RM_IHPSG13_1P_1024x32_c2_bm_bist" in blackboxes
    assert "RM_IHPSG13_1P_4096x16_c3_bm_bist" not in blackboxes


def test_chip_sdc_is_pad_aware_and_does_not_false_path_all_io() -> None:
    module = load_module(
        "retrosoc_tiny_librelane_sdc", FLOW_ROOT / "scripts/generate_sdc.py"
    )
    arguments = SimpleNamespace(
        domains=DOMAINS,
        pin_map=PIN_MAP,
        ext_clk_hz=24_000_000,
    )
    sdc = module.render(arguments)

    assert "u_extclk_i_pad.u_sg13g2_IOPadIn/p2c" in sdc
    assert "u_jtag_tck_i_pad.u_sg13g2_IOPadIn/p2c" in sdc
    assert "u_clock_buffer.u_sg13g2_buf_1/X" in sdc
    assert "create_clock -name clk_external -period 41.6666666667" in sdc
    assert "create_clock -name clk_jtag -period 100" in sdc
    assert "create_generated_clock -name clk_system" in sdc
    assert "set_clock_groups -name retrosoc_async -asynchronous" in sdc
    assert "-group [get_clocks {clk_external clk_system}]" in sdc
    assert "-group [get_clocks {clk_jtag}]" in sdc
    assert "set_input_delay -max" in sdc
    assert "set_output_delay -max" in sdc
    assert "set_false_path -from $reset_ext_rst_n_i_pad" in sdc
    assert "set_false_path -from $reset_jtag_trst_n_i_pad" in sdc
    assert "set_false_path -from [all_inputs]" not in sdc
    assert "set_false_path -to [all_outputs]" not in sdc


def test_tiny_flow_exposes_chip_target_only() -> None:
    makefile = (FLOW_ROOT / "Makefile").read_text(encoding="utf-8")
    top_makefile = (ROOT / "Makefile").read_text(encoding="utf-8")

    assert "librelane-chip:" in makefile
    assert "librelane-core:" not in makefile
    assert "--soc TINY" in makefile
    assert "--source-filelist-dir" in makefile
    assert re.search(r"ifeq \(\$\(SOC\),TINY\)\ninclude physical/librelane/tiny/Makefile", top_makefile)
    assert "include physical/librelane/mini/Makefile" in top_makefile
    doctor = (FLOW_ROOT / "scripts/doctor.py").read_text(encoding="utf-8")
    assert "EXPECTED_SIGNAL_PADS = 52" in doctor
    pad_cfg = (FLOW_ROOT / "pad_cfg.tcl").read_text(encoding="utf-8")
    assert "vdd sg13g2_IOPadVdd 8" in pad_cfg
    assert "iovss sg13g2_IOPadIOVss 8" in pad_cfg
    pdn = (FLOW_ROOT / "pdn_cfg.tcl").read_text(encoding="utf-8")
    assert "RM_IHPSG13_1P_1024x32_c2_bm_bist" in pdn
    assert "RM_IHPSG13_1P_4096x16_c3_bm_bist" not in pdn
