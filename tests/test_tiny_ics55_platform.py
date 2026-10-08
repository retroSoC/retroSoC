"""Tiny ICS55 SAFE24 platform and the real locked PLL behavioral view."""
from __future__ import annotations

import os
import json
from pathlib import Path
import shutil
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts.generate_tiny import generate_filelists, platform_values
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from scripts.tiny_ics55_platform import inspect_netlist, RAM
from scripts import tiny_ics55_platform as platform

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
PLL = ROOT / ".cache/retrosoc/sources/ics55_ecos_pll/verilog/PLL_TOP.behavioral.v"


def run(command, **kwargs):
    p = subprocess.run(command, text=True, capture_output=True, **kwargs)
    assert p.returncode == 0, p.stdout + p.stderr
    assert not DEFAULT_FAILURE.search(p.stdout + p.stderr), p.stdout + p.stderr
    return p.stdout


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_actual_pll_backend(simulator, tmp_path):
    assert shutil.which(simulator) and PLL.is_file(), "required locked input unavailable"
    sources = [COMMON / p for p in ["utils/register.sv", "clkrst/rst_sync.sv", "cdc/cdc_sync.sv",
                                   "utils/bin2gray.sv", "utils/gray2bin.sv"]]
    sources += [ROOT / "rtl/tech/tc_pll.sv", ROOT / "rtl/tech/tc_pll_ics55_ecos.sv",
                PLL, ROOT / "tests/rtl/tc_pll_ics55_ecos_tb.sv"]
    flags = [f"-I{COMMON}", "-DSV_ASSRT_DISABLE", "-DPDK_ICS55", "-DHAVE_PLL",
             "-DRETROSOC_SOC__TINY"]
    binary = tmp_path / "sim"
    top = "tc_pll_ics55_ecos_tb"
    if simulator == "iverilog":
        command = [simulator, "-g2012", "-s", top, *flags, *map(str, sources), "-o", str(binary)]
        launch = ["vvp", str(binary)]
    else:
        command = [simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "--top-module", top,
                   *flags, *map(str, sources), "--Mdir", str(tmp_path / "obj"), "-o", str(binary)]
        launch = [str(binary)]
    run(command, timeout=180, env={**os.environ, "CCACHE_DISABLE": "1"})
    assert "SIM_TEST_PASS ICS55 PLL backend" in run(launch, timeout=60)


@pytest.mark.parametrize("pdk,pll,technology", [("IHP130", False, 0x02010082), ("ICS55", True, 0x02040037)])
def test_identity(pdk, pll, technology):
    values = platform_values(pdk, pll)
    assert values["technology"] == technology
    assert values["features0"] == 0x7FFE | pll


@pytest.mark.parametrize("simulator,synthesis", [("VERILATOR", "NONE"), ("IVERILOG", "NONE"), ("IVERILOG", "YOSYS")])
def test_flow_specific_inputs(tmp_path, simulator, synthesis):
    generate_filelists(tmp_path, tmp_path / "generated", ["+define+HAVE_PLL"], "ICS55", simulator, synthesis)
    text = (tmp_path / "pdk_selected.fl").read_text()
    assert "IHP-Open-PDK" not in text and "/cache/" not in text.replace("/.cache/", "")
    assert ("PLL_TOP.behavioral.v" in text) == (synthesis == "NONE")
    assert ("ics55_io_sim_cells.sv" in text) == (simulator == "VERILATOR" and synthesis == "NONE")


def test_default_and_compatibility_configurations():
    output = run(["make", "-s", "SOC=TINY", "config"], cwd=ROOT)
    assert "ics55-tiny.mk" in output and "ICS55" in output
    output = run(["make", "-s", "CONFIG=configs/ci/ihp130-tiny.mk", "config"], cwd=ROOT)
    assert "IHP130" in output
    result = subprocess.run(["make", "-s", "CONFIG=configs/ci/ics55.mk", "SOC=MINI",
                             "HAVE_PLL=YES", "TINY_SAFE24_PLL_OFF=YES", "STA=OPENSTA", "config"],
                            cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0 and "qualified PDK PLL timing profile" in result.stderr


@pytest.mark.parametrize("changed", [None, "netlist", "json", "config", "script", "missing"])
def test_consumed_netlist_provenance(tmp_path, monkeypatch, changed):
    monkeypatch.setattr(platform, "check_configuration", lambda *args: None)
    paths = [tmp_path / name for name in ("net.v", "net.v.json", "net.config")]
    for path in paths:
        path.write_text("original")
    report = {"phase": platform.PHASE, "status": "passed",
              "audit_script": platform.b.artifact(Path(platform.__file__)),
              "inputs": [platform.b.artifact(path) for path in paths]}
    if changed in ("netlist", "json", "config"):
        paths[("netlist", "json", "config").index(changed)].write_text("changed")
    elif changed == "script":
        report["audit_script"] = platform.b.artifact(paths[0])
    elif changed == "missing":
        report["inputs"].pop()
    output = tmp_path / "audit.json"
    output.write_text(json.dumps(report))
    if changed:
        with pytest.raises(ValueError):
            platform.verify_netlist(tmp_path, paths[0], paths[2], output)
    else:
        assert platform.verify_netlist(tmp_path, paths[0], paths[2], output) == report


@pytest.fixture
def mapped_netlist():
    def cell(kind, **ports):
        return {"type": kind, "connections": {k: [v] for k, v in ports.items()},
                "port_directions": {k: "inout" if k == "PAD" else "output"
                                    if k in ("Y", "Z", "C", "CKOUT1", "CKOUT2", "CKTST")
                                    else "input" for k in ports}}
    cells = {"u_clock_buffer": cell("clock_buffer", clk_i=7, clk_o=2),
             "receiver": cell("P65_1233_PBMUX", PAD=1, C=7, IE="1", OE="0", CS="1"),
             "u_soc.u_cpu.u_hazard3_cpu_1port.core.pc_reg": cell("DFF", CK=2),
             "pll": cell("PLL_TOP", EN=3, CKOUT1=4, CKOUT2=5, CKTST=6),
             "low": cell("TIELOH7R", Z=3)}
    cells.update({f"bank{i}": cell(RAM, CLK=2) for i in range(32)})
    return {"modules": {
        "retrosoc_tiny_asic": {"ports": {"extclk_i_pad": {"direction": "inout", "bits": [1]},
                                         "jtag_tck_i_pad": {"direction": "inout", "bits": [11]}},
                               "cells": cells},
        "clock_buffer": {"ports": {"clk_i": {"direction": "input", "bits": [100]},
                                    "clk_o": {"direction": "output", "bits": [101]}},
                         "cells": {"u_buf": cell("BUFX0P7H7R", A=100, Y=101)}}}}


def test_safe24_structural_binding(mapped_netlist):
    result = inspect_netlist(mapped_netlist)
    assert len(result["sram"]) == 32 and result["cpu_clocked_cells"] == 1
    assert result["pll_enable"] == 0
    assert result["system_clock_source"]["port"] == "extclk_i_pad"
    assert [c["type"] for c in result["system_clock_source"]["path"]] == [
        "BUFX0P7H7R", "P65_1233_PBMUX"]


@pytest.mark.parametrize("source", ["0", "1", "x", "z", 99, 11, 4, 2])
def test_clock_buffer_cannot_hide_invalid_source(mapped_netlist, source):
    # Constants, undriven nets, JTAG, PLL output and feedback all leave the
    # output-side CPU/SRAM net unchanged. The old audit accepted these cases.
    mapped_netlist["modules"]["retrosoc_tiny_asic"]["cells"]["u_clock_buffer"]["connections"]["clk_i"] = [source]
    with pytest.raises(ValueError):
        inspect_netlist(mapped_netlist)


@pytest.mark.parametrize("mutation", ["missing_ref", "wrong_pad", "disabled_input",
                                      "unknown_enable", "driven_pad", "unknown_mode",
                                      "duplicate_sys_driver", "driven_ref", "inverter", "mux"])
def test_ref24_path_must_be_unambiguous_and_enabled(mapped_netlist, mutation):
    modules = mapped_netlist["modules"]
    top = modules["retrosoc_tiny_asic"]
    cells = top["cells"]
    pad = cells["receiver"]["connections"]
    if mutation == "missing_ref":
        del top["ports"]["extclk_i_pad"]
    elif mutation == "wrong_pad":
        pad["PAD"] = [11]
    elif mutation == "disabled_input":
        pad["IE"] = ["0"]
    elif mutation == "unknown_enable":
        pad["IE"] = ["x"]
    elif mutation == "driven_pad":
        pad["OE"] = ["1"]
    elif mutation == "unknown_mode":
        pad["CS"] = ["x"]
    elif mutation == "duplicate_sys_driver":
        cells["second_driver"] = {"type": "BUFX0P7H7R", "connections": {"A": [7], "Y": [2]},
                                  "port_directions": {"A": "input", "Y": "output"}}
    elif mutation == "driven_ref":
        cells["pll"]["connections"]["CKOUT1"] = [1]
    else:
        modules["clock_buffer"]["cells"]["u_buf"]["type"] = (
            "INVX0P5H7R" if mutation == "inverter" else "MUX2X1H7R")
    with pytest.raises(ValueError):
        inspect_netlist(mapped_netlist)


def test_ref24_path_accepts_hierarchical_receiver_and_tie_cells(mapped_netlist):
    modules = mapped_netlist["modules"]
    cells = modules["retrosoc_tiny_asic"]["cells"]
    receiver = cells.pop("receiver")
    receiver["connections"].update(PAD=[100], C=[101], IE=[102], CS=[102], OE=[103])
    cells["receiver"] = {"type": "input_receiver", "connections": {
        "pad": [1], "data": [7], "high": [8], "low": [3]}}
    cells["high"] = {"type": "TIEHIH7R", "connections": {"Z": [8]},
                     "port_directions": {"Z": "output"}}
    modules["input_receiver"] = {"ports": {
        "pad": {"direction": "inout", "bits": [100]},
        "data": {"direction": "output", "bits": [101]},
        "high": {"direction": "input", "bits": [102]},
        "low": {"direction": "input", "bits": [103]}}, "cells": {"u_pad": receiver}}
    assert inspect_netlist(mapped_netlist)["system_clock_source"]["port"] == "extclk_i_pad"


def test_hierarchical_constant_output_is_resolved(mapped_netlist):
    modules = mapped_netlist["modules"]
    modules["constant_zero"] = {"ports": {"result": {"direction": "output", "bits": ["0"]}}, "cells": {}}
    modules["retrosoc_tiny_asic"]["cells"]["low"] = {
        "type": "constant_zero", "connections": {"result": [3]}}
    assert inspect_netlist(mapped_netlist)["pll_enable"] == 0


@pytest.mark.parametrize("mutation", ["missing_pll", "missing_ram", "live_pll", "unknown_enable",
                                      "divided_ram", "wrong_cpu", "pll_sys"])
def test_unsafe_or_incomplete_mapping_is_rejected(mapped_netlist, mutation):
    cells = mapped_netlist["modules"]["retrosoc_tiny_asic"]["cells"]
    if mutation == "missing_pll":
        del cells["pll"]
    elif mutation == "missing_ram":
        del cells["bank0"]
    elif mutation == "live_pll":
        cells["low"]["type"] = "TIEHIH7R"
    elif mutation == "unknown_enable":
        cells["pll"]["connections"]["EN"] = [99]
    elif mutation == "divided_ram":
        cells["bank0"]["connections"]["CLK"] = [99]
    elif mutation == "wrong_cpu":
        cells["u_soc.u_cpu.u_hazard3_cpu_1port.core.pc_reg"]["connections"]["CK"] = [99]
    else:
        cells["pll"]["connections"]["CKOUT1"] = [2]
    with pytest.raises(ValueError):
        inspect_netlist(mapped_netlist)


def test_tiny_uses_32_actual_ics55_small_macros(tmp_path):
    assert shutil.which("verilator"), "required simulator unavailable"
    generated = tmp_path / "map"
    generate_memory_map(ROOT / "rtl/tiny/address_map/memory_map.json", generated, "YES", 128)
    sram = ROOT / ".cache/retrosoc/pdk/ics55/sram"
    sources = [COMMON / p for p in ["interface/axi4_if.sv", "interface/apb4_if.sv",
                                   "interface/axi4_addr_gen.sv", "utils/register.sv", "tech/ram.sv"]]
    sources += [ROOT / p for p in ["rtl/tech/tc_sram.sv", "rtl/ip/memory/onchip_ram_reg.sv",
                                  "rtl/ip/memory/onchip_ram.sv", "tests/rtl/onchip_ram_tb.sv"]]
    sources += [sram / "ics55_ecos_sram_1024x32_m8/verilog/ics55_ecos_sram_1024x32_m8_core.v",
                sram / "ics55_ecos_sram_4096x32_m8/verilog/ics55_ecos_sram_4096x32_m8_stub.v"]
    binary = tmp_path / "sim"
    run(["verilator", "--binary", "--timing", "--assert", "-Wno-fatal", "--top-module", "onchip_ram_tb",
         "-GCapacityKiB=128", "-GIcs55SmallBanks=1", "-DPDK_ICS55", "-DHAVE_SRAM_MACRO", "-DSV_ASSRT_DISABLE",
         *(f"-I{p}" for p in [generated / "rtl", ROOT / "rtl/ip/memory", COMMON, COMMON / "interface"]),
         *map(str, sources), "--Mdir", str(tmp_path / "obj"), "-o", str(binary)],
        timeout=180, env={**os.environ, "CCACHE_DISABLE": "1"})
    assert "on-chip SRAM AXI4 test passed capacity_kib=128" in run([str(binary)], timeout=60)


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_gpio_readback_preserves_legacy_default(tmp_path, simulator):
    assert shutil.which(simulator), "required simulator unavailable"
    model = ROOT / ("rtl/tech/ics55_io_sim_cells.sv" if simulator == "verilator" else
                    "physical/pdk/icsprout55-pdk/IP/IO/ICsprout_55LLULP1233_IO_251013/verilog/icsIOA_N55_3P3.v")
    sources = [str(ROOT / "rtl/tech/tc_io.sv"), str(model), str(ROOT / "tests/rtl/tc_ics55_gpio_readback_tb.sv")]
    binary = tmp_path / "sim"
    if simulator == "iverilog":
        compile_command = [simulator, "-g2012", "-DPDK_ICS55", "-Dfunctional", "-s",
                           "tc_ics55_gpio_readback_tb", *sources, "-o", str(binary)]
        launch = ["vvp", str(binary)]
    else:
        compile_command = [simulator, "--binary", "--timing", "-Wno-fatal", "-DPDK_ICS55",
                           "--top-module", "tc_ics55_gpio_readback_tb", *sources,
                           "--Mdir", str(tmp_path / "obj"), "-o", str(binary)]
        launch = [str(binary)]
    run(compile_command, timeout=120, env={**os.environ, "CCACHE_DISABLE": "1"})
    assert "SIM_TEST_PASS ICS55 GPIO" in run(launch, timeout=30)
