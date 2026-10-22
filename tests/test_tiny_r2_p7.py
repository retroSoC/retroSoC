"""Tiny P7 clock, reset and crossing contracts; behavioral evidence only."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts.generate_tiny import generate_bindings, read_topology
from scripts.tiny_r2_p7 import inspect_netlist
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from test_tiny_ics55_platform import mapped_netlist  # noqa: F401 -- shared synthetic fixture

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"


def run_rtl(tmp_path: Path, simulator: str, fixture: str, extra: list[Path],
            defines: list[str] | None = None, plusargs: list[str] | None = None,
            packages: list[Path] | None = None) -> str:
    for tool in (simulator, *([] if simulator == "verilator" else ["sv2v", "vvp"])):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    # Put the fixture first so its explicit timescale applies during sv2v.
    sources = [*(packages or []), ROOT / f"tests/rtl/{fixture}.sv",
               *[COMMON / p for p in (
                   "utils/register.sv", "utils/xchecker.sv", "utils/bin2gray.sv",
                   "utils/gray2bin.sv", "interface/apb4_if.sv", "interface/axi4_if.sv",
                   "cdc/cdc_sync.sv", "cdc/cdc_rst_ctrlr.sv", "cdc/cdc_2phase.sv",
                   "clkrst/rst_sync.sv", "clock/safe_clock_mux.sv", "clock/clock_divider.sv")],
               *extra]
    includes = [f"-I{p}" for p in (COMMON, COMMON / "interface", ROOT / "tests/rtl",
                                  ROOT / "rtl/tiny/top")]
    args = ["-DSV_ASSRT_DISABLE", *(defines or []), *includes, *(str(p) for p in sources)]
    output = tmp_path / "sim"

    def execute(command: list[str], log: str, timeout: int = 120) -> str:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                env={**os.environ, "CCACHE_DISABLE": "1"}, timeout=timeout)
        content = result.stdout + result.stderr
        (tmp_path / log).write_text(content)
        assert result.returncode == 0, content
        return content

    if simulator == "verilator":
        execute([simulator, "--binary", "--timing", "--assert", "--timescale", "1ns/1ps",
                 "-Wno-fatal", "--top-module", fixture, *args, "--Mdir", str(tmp_path / "obj"),
                 "-o", str(output)], "compile.log")
        launch = [str(output)]
    else:
        converted = subprocess.run(["sv2v", *args], cwd=ROOT, capture_output=True,
                                   text=True, timeout=60)
        assert converted.returncode == 0, converted.stderr
        # sv2v strips timescale directives; restore the fixture's declared
        # units so fractional PLL/reference delays are not rounded to seconds.
        (tmp_path / "converted.v").write_text("`timescale 1ns / 1ps\n" + converted.stdout)
        execute([simulator, "-g2012", "-s", fixture, "-o", str(output),
                 str(tmp_path / "converted.v")], "compile.log")
        launch = ["vvp", str(output)]
    content = execute([*launch, *(plusargs or [])], "sim.log", 30)
    assert not DEFAULT_FAILURE.search(content), content
    assert "SIM_TEST_PASS" in content, content
    return content


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_apb_async_bridge(tmp_path: Path, simulator: str) -> None:
    run_rtl(tmp_path, simulator, "tiny_apb_async_bridge_tb",
            [ROOT / "rtl/tiny/top/tiny_apb_async_bridge.sv"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("scenario", ["reset", "same_cycle_clear", "same_cycle_write",
                                      "held_read_stability", "held_write_stability", "burst_abort",
                                      "clear_pending", "same_cycle_reset_read", "same_cycle_reset_write"])
def test_tiny_axi4_async_bridge_reset_abort(tmp_path: Path, simulator: str, scenario: str) -> None:
    run_rtl(tmp_path, simulator, "tiny_axi4_async_bridge_tb", [
        COMMON / "cdc/async_reqack.sv",
        COMMON / "cdc/cdc_warm_flush.sv",
        COMMON / "cdc/cdc_fifo.sv",
        COMMON / "utils/spill_register.sv",
        ROOT / "rtl/tiny/top/tiny_axi4_async_bridge.sv",
    ], plusargs=[] if scenario == "reset" else [f"+{scenario}"])


def source_reset_bindings(tmp_path: Path) -> None:
    """Exercise production reset/admission wiring, not a copied test policy."""
    top = (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text()
    topology = read_topology(ROOT / "rtl/tiny/integration/soc_topology.json",
                             ROOT / "rtl/tiny/address_map/memory_map.json")
    generate_bindings(topology, tmp_path / "bindings")
    generated = (tmp_path / "bindings/rtl/tiny_apb_interfaces.svh").read_text()

    def instance(source: str, module: str, name: str) -> str:
        matches = re.findall(rf"\b{module}\s*(?:#\([^;]*?\)\s*)?{name}\s*\([^;]*?\);", source)
        assert len(matches) == 1, (module, name)
        return matches[0]

    blocks = [instance(top, module, name) for module, name in (
        ("tiny_reset_tree", "u_reset_tree"),
        ("tiny_peripheral_control", "u_peripheral_control"),
        ("tiny_axi4_admission", "u_dma_admission"),
        ("tiny_axi4_async_bridge", "u_dma_cdc"),
        *(("cdc_sync", name) for name in ("u_block_pclk", "u_dma_idle_sync",
                                          "u_dma_ready_sync", "u_bus_idle_ref",
                                          "u_periph_idle_sync", "u_gate_feedback",
                                          "u_held_feedback", "u_ready_feedback")),
    )]
    blocks.append(instance(generated, "tiny_peripheral_leaf", "u_dma_lifecycle"))
    for source, lhs in ((top, "s_fabric_rst_n"), (top, "s_clock_safe"),
                        (generated, "s_xpi_rst_n"), (generated, "s_reset_ready[9]")):
        matches = re.findall(rf"\bassign\s+{re.escape(lhs)}\s*=[^;]*;", source)
        assert len(matches) == 1, lhs
        blocks.extend(matches)
    blocks += re.findall(r"\bassign\s+s_leaf_clk\[\d+\]\s*=[^;]*;", generated)
    blocks.append("assign s_leaf_clk[0] = s_exec_clk;")
    (tmp_path / "source_reset_bindings.svh").write_text("\n".join(blocks) + "\n")


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_production_source_reset_contract(tmp_path: Path, simulator: str) -> None:
    source_reset_bindings(tmp_path)
    run_rtl(tmp_path, simulator, "tiny_p7_source_reset_tb", [
        COMMON / "cdc/async_reqack.sv", COMMON / "cdc/cdc_warm_flush.sv",
        COMMON / "cdc/cdc_fifo.sv", COMMON / "utils/spill_register.sv",
        ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
        *[ROOT / "rtl/tiny/top" / name for name in (
            "tiny_reset_tree.sv", "tiny_peripheral_control.sv", "tiny_peripheral_leaf.sv",
            "tiny_axi4_admission.sv", "tiny_axi4_async_bridge.sv")],
    ], defines=[f"-I{tmp_path}", f"-I{tmp_path / 'bindings/rtl'}"])
    launch = [str(tmp_path / "sim")] if simulator == "verilator" else ["vvp", str(tmp_path / "sim")]
    # Compile once per simulator; reuse the binary at every supported domain
    # ratio. These are digital boundary tests, not PDK/frequency qualification.
    for mode in ("xin48", "xin96", "pll192", "pll240", "break_drain"):
        result = subprocess.run([*launch, f"+{mode}"], cwd=ROOT, text=True,
                                capture_output=True, timeout=30)
        content = result.stdout + result.stderr
        (tmp_path / f"{mode}.log").write_text(content)
        if mode == "break_drain":
            # sv2v may lower $fatal to $finish(1), which vvp can return as
            # exit zero. The strict Tiny verdict must still reject the log.
            assert DEFAULT_FAILURE.search(content) and "P7_SOURCE_RESET_UNDRAINED" in content, content
            assert "SIM_TEST_PASS" not in content, content
        else:
            assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
            assert "SIM_TEST_PASS Tiny P7 production source reset" in content, content


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_watchdog_reset_chain(tmp_path: Path, simulator: str) -> None:
    generate_memory_map(ROOT / "rtl/tiny/address_map/memory_map.json", tmp_path / "map", "YES", 128)
    run_rtl(tmp_path, simulator, "tiny_watchdog_reset_tb", [
        COMMON / "clkrst/counter.sv",
        COMMON / "cdc/async_reqack.sv", COMMON / "cdc/cdc_fifo.sv",
        *[ROOT / "rtl/managed/clusterip/wdg/rtl" / name for name in (
            "wdg_if.sv", "wdg_core.sv", "wdg_reg.sv", "apb4_wdg.sv")],
        *[ROOT / "rtl/tiny/top" / name for name in (
            "tiny_clock_reset_subsystem.sv", "tiny_reset_tree.sv",
            "tiny_apb_async_bridge.sv", "tiny_sysctrl.sv")]],
        [f"-I{ROOT / 'rtl/ip/peripheral'}", f"-I{tmp_path / 'map/rtl'}",
         f"-I{ROOT / 'rtl/managed/clusterip/wdg/rtl'}"],
        packages=[ROOT / "rtl/managed/clusterip/wdg/rtl/wdg_pkg.sv"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("module", ["tiny_axi4_admission", "tiny_clock_output"])
def test_tiny_p7_boundaries(tmp_path: Path, simulator: str, module: str) -> None:
    run_rtl(tmp_path, simulator, f"{module}_tb", [ROOT / f"rtl/tiny/top/{module}.sv"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_peripheral_control(tmp_path: Path, simulator: str) -> None:
    run_rtl(tmp_path, simulator, "tiny_peripheral_control_tb",
            [ROOT / "rtl/tiny/top/tiny_peripheral_leaf.sv",
             ROOT / "rtl/tiny/top/tiny_peripheral_control.sv"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_clock_reset_backend_safe24(tmp_path: Path, simulator: str) -> None:
    run_rtl(tmp_path, simulator, "tiny_clock_reset_subsystem_tb",
            [ROOT / "rtl/tiny/top/tiny_clock_reset_subsystem.sv"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("success", [False, True])
def test_tiny_clock_reset_backend_pll(tmp_path: Path, simulator: str, success: bool) -> None:
    run_rtl(tmp_path, simulator, "tiny_clock_reset_pll_tb",
            [ROOT / "rtl/tech/tc_pll.sv", ROOT / "rtl/tiny/top/tiny_clock_reset_subsystem.sv"],
            ["-DPDK_BEHAV", "-DHAVE_PLL", *(["-DTINY_PLL_SUCCESS"] if success else [])],
            [] if success else ["+pll_lock_fail"])


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_tiny_clock_reset_ics55_model(tmp_path: Path, simulator: str) -> None:
    run_rtl(tmp_path, simulator, "tiny_clock_reset_pll_tb",
            [ROOT / "rtl/tech/tc_pll.sv", ROOT / "rtl/tech/tc_pll_ics55_ecos.sv",
             ROOT / "rtl/tiny/top/tiny_clock_reset_subsystem.sv",
             ROOT / ".cache/retrosoc/sources/ics55_ecos_pll/verilog/PLL_TOP.behavioral.v"],
            ["-DPDK_ICS55", "-DRETROSOC_SOC__TINY", "-DHAVE_PLL", "-DTINY_PLL_SUCCESS",
             "-DTINY_PLL_NATIVE"])


def test_tiny_rcu_register_parity() -> None:
    sv = (ROOT / "rtl/tiny/top/tiny_rcu_regs.svh").read_text()
    c = (ROOT / "crt/include/retrosoc/hal/rcu_regs.h").read_text()
    sv_values = {name: int(value, 16) for name, value in
                 re.findall(r"`define APB4_TINY_RCU__(\w+)\s+32'h([0-9a-f]+)", sv)}
    c_values = {name: int(value, 16) for name, value in
                re.findall(r"#define RS_TINY_RCU_(\w+)_OFFSET\s+UINT32_C\(0x([0-9A-F]+)\)", c)}
    assert len(sv_values) == 24
    assert sv_values == c_values
    assert sorted(sv_values.values()) == list(range(0x100, 0x160, 4))


def check_p7_target_capability(top: str, firmware: str) -> None:
    """Bind the acceptance guard to the actual DVP-inclusive SYSCTRL instance."""
    top, firmware = (re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.DOTALL)
                     for text in (top, firmware))
    instances = re.findall(r"\btiny_sysctrl\s*#\(([^;]*?)\)\s*u_sysctrl\s*\(", top)
    if len(instances) != 1:
        raise ValueError("missing or ambiguous production SYSCTRL instance")
    targets = re.findall(r"\.TargetMask\s*\(\s*17'h([0-9a-fA-F_]+)\s*\)", instances[0])
    expected = re.findall(
        r"^\s*#define RS_P7_EXPECTED_TARGET_CAPABILITY\s+UINT32_C\(0x([0-9a-fA-F]+)\)\s*$",
        firmware, re.MULTILINE)
    if len(targets) != 1 or len(expected) != 1:
        raise ValueError("missing or ambiguous target capability definition")
    # Freeze the implemented set independently of both handwritten sources.
    # The HAL's 0x3ffff architecture mask also admits unimplemented targets.
    if int(targets[0].replace("_", ""), 16) != 0x17FFF or int(expected[0], 16) != 0x17FFF:
        raise ValueError("target capability differs from the DVP-inclusive contract")
    main = re.findall(r"\bint\s+main\s*\(void\)\s*\{(.*)", firmware, re.DOTALL)
    guard = (
        r"\bif\s*\(\s*rs_tiny_rcu_get_snapshot\(&snapshot\)\s*!=\s*RS_OK\s*\|\|\s*"
        r"snapshot\.sys_hz\s*!=\s*24000000U\s*\|\|\s*"
        r"snapshot\.target_capability\s*!=\s*RS_P7_EXPECTED_TARGET_CAPABILITY\s*\)\s*"
        r"\{\s*code\s*=\s*1U\s*;"
    )
    if len(main) != 1 or len(re.findall(guard, main[0])) != 1:
        raise ValueError("missing or weakened exact startup capability guard")


def test_tiny_p7_target_capability_parity() -> None:
    check_p7_target_capability((ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text(),
                              (ROOT / "app/apps/ci_smoke/tiny_r2_p7.c").read_text())


@pytest.mark.parametrize(("source", "old", "new"), [
    ("firmware", "UINT32_C(0x00017FFF)", "UINT32_C(0x00003FFF)"),
    ("top", "17'h17fff", "17'h03fff"),
    *[("firmware", "UINT32_C(0x00017FFF)", f"UINT32_C({value})")
      for value in ("0x00007FFF", "0x0000FFFF", "0x00027FFF", "0x0003FFFF")],
    ("firmware", "snapshot.target_capability != RS_P7_EXPECTED_TARGET_CAPABILITY", "false"),
    ("firmware", "snapshot.target_capability != RS_P7_EXPECTED_TARGET_CAPABILITY",
     "(snapshot.target_capability & RS_P7_EXPECTED_TARGET_CAPABILITY) != RS_P7_EXPECTED_TARGET_CAPABILITY"),
    ("firmware", "#define RS_P7_EXPECTED_TARGET_CAPABILITY", "#define RS_P7_UNUSED_CAPABILITY"),
    ("top", ".TargetMask (17'h17fff)", ".UnusedMask (17'h17fff)"),
])
def test_tiny_p7_target_capability_rejects_drift(source: str, old: str, new: str) -> None:
    sources = {"top": (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text(),
               "firmware": (ROOT / "app/apps/ci_smoke/tiny_r2_p7.c").read_text()}
    assert sources[source].count(old) == 1
    sources[source] = sources[source].replace(old, new)
    with pytest.raises(ValueError):
        check_p7_target_capability(**sources)


@pytest.mark.parametrize("source", ["top", "firmware"])
def test_tiny_p7_target_capability_rejects_ambiguous_source(source: str) -> None:
    sources = {"top": (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text(),
               "firmware": (ROOT / "app/apps/ci_smoke/tiny_r2_p7.c").read_text()}
    sources[source] += sources[source]
    with pytest.raises(ValueError):
        check_p7_target_capability(**sources)


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("xin_hz", [24000000, 48000000, 96000000])
def test_tiny_external_sources(tmp_path: Path, simulator: str, xin_hz: int) -> None:
    run_rtl(tmp_path, simulator, "tiny_clock_external_tb",
            [ROOT / "rtl/tiny/top/tiny_clock_reset_subsystem.sv",
             ROOT / "rtl/tiny/top/tiny_reset_tree.sv"],
            [f"-DTINY_TEST_XIN_HZ={xin_hz}"])


def test_aon_reset_uses_normalized_reference() -> None:
    top = (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text()
    assert re.search(r"\.por_clk_i\s*\(s_ref_clk\)", top)


def test_tiny_xpi_cdc_has_split_reset_endpoints() -> None:
    top = (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text()
    assert re.search(r"assign s_target_rst_n\[4\]\s*=\s*s_fabric_rst_n", top)
    bridge = re.search(r"u_xpi_mem_cdc\s*\(.*?\n\s*\);", top, re.DOTALL)
    assert bridge is not None
    assert re.search(r"\.src_rst_n_i\s*\(s_fabric_rst_n\)", bridge.group(0))
    assert re.search(r"\.dst_rst_n_i\s*\(s_xpi_rst_n\)", bridge.group(0))


@pytest.fixture
def p7_netlist(mapped_netlist):  # noqa: F811 -- pytest injects the imported fixture
    modules = mapped_netlist["modules"]
    cells = modules["retrosoc_tiny_asic"]["cells"]

    def boundary(name, kind, **ports):
        modules[kind] = {"ports": {key: {"direction": "output" if key.endswith("_o") else "input",
                                        "bits": [i + 100]} for i, key in enumerate(ports)},
                         "cells": {}}
        cells[name] = {"type": kind, "connections": {key: [value] for key, value in ports.items()}}

    boundary("u_soc.u_clock_backend.u_sys_mux", "safe_clock_mux$sys", clk0_i=2, clk1_i=4, clk_o=20)
    boundary("u_soc.u_clock_backend.u_mem_mux", "safe_clock_mux$mem", clk0_i=20, clk1_i=24, clk_o=21)
    boundary("u_soc.u_clock_backend.u_pclk_mux", "safe_clock_mux$pclk", clk0_i=20, clk1_i=25, clk_o=22)
    boundary("u_soc.u_cpu.u_cpu_gate", "tiny_clock_gate$cpu", clk_i=20, clk_o=23)
    boundary("u_soc.u_crypto_lifecycle", "tiny_peripheral_leaf$crypto", clk_i=22, clk_o=26)
    for name, cell in cells.items():
        if "u_soc.u_sram" in name:
            cell["connections"]["CLK"] = [20]
        if "u_soc.u_crypto.u_storage" in name:
            cell["connections"]["CLK"] = [26]
        if "u_hazard3_cpu_2port" in name:
            cell["connections"]["CK"] = [23]
    cells["pll"]["connections"].update(REFCLK=[2], EN=[30])
    return mapped_netlist


def test_p7_clock_bindings(p7_netlist) -> None:
    binding = inspect_netlist(p7_netlist, "ICS55")
    assert binding["main_macros"] == 32
    assert binding["private_crypto_macros"] == 6
    assert binding["pll_macros"] == 1


@pytest.mark.parametrize("mutation", ["half_rate_sram", "cpu_divider", "crypto_sys",
                                      "pll_bypass", "pll_tied", "fake_safe_source"])
def test_p7_clock_binding_rejects_mismatch(p7_netlist, mutation: str) -> None:
    cells = p7_netlist["modules"]["retrosoc_tiny_asic"]["cells"]
    if mutation == "half_rate_sram":
        cells["u_soc.u_sram.gen_group[0].u_group.gen_bank[0].u_ram.u_mem"]["connections"]["CLK"] = [21]
    elif mutation == "cpu_divider":
        cells["u_soc.u_cpu.u_hazard3_cpu_2port.core.pc_reg"]["connections"]["CK"] = [21]
    elif mutation == "crypto_sys":
        cells["u_soc.u_crypto_lifecycle"]["connections"]["clk_i"] = [20]
    elif mutation == "pll_bypass":
        cells["u_soc.u_clock_backend.u_sys_mux"]["connections"]["clk1_i"] = [2]
    elif mutation == "pll_tied":
        cells["pll"]["connections"]["EN"] = [3]
    else:
        cells["u_soc.u_clock_backend.u_sys_mux"]["connections"]["clk0_i"] = [31]
        cells["pll"]["connections"]["REFCLK"] = [31]
    with pytest.raises(ValueError):
        inspect_netlist(p7_netlist, "ICS55")
