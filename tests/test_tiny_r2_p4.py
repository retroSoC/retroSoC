"""Tiny dual-port local-memory protocol and source-bound replay acceptance."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from scripts import tiny_r2_p4 as p4

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
TINY = ROOT / "rtl/tiny/top"


def run(command, directory, label, timeout=180):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout,
                            env={**os.environ, "CCACHE_DISABLE": "1"})
    (directory / f"{label}.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout[-12000:]
    if label != "sv2v":  # Converted source contains literal assertion/error strings.
        assert not DEFAULT_FAILURE.search(result.stdout), result.stdout[-12000:]
    return result.stdout


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("pdk", ["BEHAV", "ICS55", "IHP130"])
def test_four_group_local_memory(tmp_path, simulator, pdk):
    for tool in (simulator, "sv2v", "vvp"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    generate_memory_map(ROOT / "rtl/tiny/address_map/memory_map.json", tmp_path / "map", "YES", 128)
    sources = [COMMON / p for p in (
        "utils/register.sv", "utils/fifo.sv", "stream/round_robin_arbiter.sv", "interface/axi4_if.sv",
        "interface/axi4_addr_gen.sv", "interface/apb4_if.sv", "interface/ahbl_if.sv")]
    sources += [TINY / p for p in (
        "tiny_sram_port_if.sv", "tiny_sram_group.sv", "tiny_sram_axi4.sv",
        "tiny_sram.sv", "tiny_cpu_mem.sv")]
    sources += [ROOT / p for p in (
        "rtl/tech/tc_sram.sv", "rtl/ip/memory/onchip_ram_reg.sv",
        "rtl/ip/interconnect/ahbl2axi4.sv", "rtl/ip/interconnect/axi4_error_slave.sv",
        "tests/rtl/tiny_r2_p4_memory_tb.sv")]
    defines = ["-DSV_ASSRT_DISABLE", f"-DPDK_{pdk}", "-DHAVE_SRAM_MACRO"]
    vendor = []
    if pdk == "IHP130":
        base = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog"
        vendor = [base / "RM_IHPSG13_1P_core_behavioral_bm_bist.v",
                  base / "RM_IHPSG13_1P_1024x32_c2_bm_bist.v"]
        defines += ["-DFUNCTIONAL", "-DSYNTHESIS"]
    elif pdk == "ICS55":
        vendor = [ROOT / ".cache/retrosoc/pdk/ics55/sram/ics55_ecos_sram_1024x32_m8/verilog/ics55_ecos_sram_1024x32_m8_core.v"]
    assert all(p.is_file() for p in vendor), "locked SRAM models unavailable"
    includes = [f"-I{p}" for p in (COMMON, COMMON / "interface", tmp_path / "map/rtl",
                                   ROOT / "rtl/ip/memory")]
    top = "tiny_r2_p4_memory_tb"
    output = tmp_path / "sim"
    if simulator == "verilator":
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "3",
             "-DHAVE_SVA", "--top-module", top, *defines, *includes,
             *(str(p) for p in sources + vendor), "--Mdir", str(tmp_path / "obj"), "-o", str(output)],
            tmp_path, "compile")
        launch = [str(output)]
    else:
        # Keep vendor models outside sv2v, as in the executable Tiny flow.
        converted = run(["sv2v", *defines, *includes, *(str(p) for p in sources)], tmp_path, "sv2v")
        (tmp_path / "converted.v").write_text(converted)
        run([simulator, "-g2012", "-gno-specify", "-s", top,
             *defines, "-o", str(output), str(tmp_path / "converted.v"), *(str(p) for p in vendor)],
            tmp_path, "compile")
        launch = ["vvp", str(output)]
    content = run(launch, tmp_path, "sim")
    assert "SIM_TEST_PASS Tiny P4 memory" in content
    assert "P4_STREAM read_gap_max=1 write_gap_max=1 beats=16" in content
    assert "P4_BUFFER backpressure errors reset conservation PASS" in content


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_actual_dual_port_cpu_debug_and_reset(tmp_path, simulator):
    for tool in (simulator, "sv2v", "vvp", "riscv32-unknown-elf-gcc", "riscv32-unknown-elf-objcopy"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    generate_memory_map(ROOT / "rtl/tiny/address_map/memory_map.json", tmp_path / "map", "YES", 128)
    run(["riscv32-unknown-elf-gcc", "-march=rv32imc_zicsr_zifencei", "-mabi=ilp32",
         "-nostdlib", "-Wl,--build-id=none", "-T", str(ROOT / "tests/rtl/tiny_r2_p4_cpu.ld"),
         str(ROOT / "tests/rtl/tiny_r2_p4_cpu.S"), "-o", str(tmp_path / "cpu.elf")], tmp_path, "firmware")
    run(["riscv32-unknown-elf-objcopy", "-O", "verilog", str(tmp_path / "cpu.elf"),
         str(tmp_path / "cpu.hex")], tmp_path, "objcopy")
    sources = [COMMON / p for p in (
        "utils/register.sv", "utils/fifo.sv", "stream/round_robin_arbiter.sv", "interface/axi4_if.sv",
        "interface/axi4_addr_gen.sv", "interface/apb4_if.sv", "interface/ahbl_if.sv",
        "clkrst/rst_sync.sv", "cdc/cdc_sync.sv")]
    sources += [ROOT / "rtl/managed/hazard3/hdl" / line.removeprefix("/hazard3/")
                for line in (ROOT / "rtl/tiny/filelist/core_hazard3.fl").read_text().splitlines()
                if line.startswith("/hazard3/")]
    sources += [TINY / p for p in (
        "tiny_sram_port_if.sv", "tiny_sram_group.sv", "tiny_sram_axi4.sv",
        "tiny_sram.sv", "tiny_cpu_mem.sv", "tiny_cpu_wrapper.sv")]
    sources += [ROOT / p for p in (
        "rtl/tech/tc_sram.sv", "rtl/tech/tc_clk.sv", "rtl/ip/memory/onchip_ram_reg.sv",
        "rtl/ip/interconnect/ahbl2axi4.sv", "rtl/ip/core/mgmt_debug_wrapper.sv",
        "rtl/ip/core/mgmt_debug_reset.sv", "tests/rtl/tiny_r2_p4_cpu_tb.sv")]
    includes = [f"-I{p}" for p in (COMMON, COMMON / "interface", tmp_path / "map/rtl",
                                   ROOT / "rtl/ip/memory", ROOT / "rtl/managed/hazard3/hdl",
                                   ROOT / "rtl/tiny/dv")]
    defines = ["-DSV_ASSRT_DISABLE", "-DPDK_BEHAV", "-DSOC_JTAG_IDCODE=32'hDEADBEEF"]
    output = tmp_path / "sim"
    top = "tiny_r2_p4_cpu_tb"
    if simulator == "verilator":
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "3",
             "-DHAVE_SVA", "--top-module", top, *defines, *includes,
             *(str(p) for p in sources), "--Mdir", str(tmp_path / "obj"), "-o", str(output)],
            tmp_path, "compile")
        launch = [str(output)]
    else:
        converted = run(["sv2v", *defines, *includes, *(str(p) for p in sources)], tmp_path, "sv2v")
        (tmp_path / "converted.v").write_text(converted)
        run([simulator, "-g2012", "-s", top, "-o", str(output), str(tmp_path / "converted.v")],
            tmp_path, "compile")
        launch = ["vvp", str(output)]
    content = run([*launch, f"+firmware={tmp_path / 'cpu.hex'}"], tmp_path, "sim")
    assert "SIM_TEST_PASS Tiny P4 CPU" in content


def test_group_control_induction(tmp_path):
    for tool in ("sv2v", "yosys"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    sources = [COMMON / "utils/register.sv", COMMON / "utils/fifo.sv",
               COMMON / "stream/round_robin_arbiter.sv",
               TINY / "tiny_sram_port_if.sv", TINY / "tiny_sram_group.sv",
               ROOT / "tests/rtl/tiny_r2_p4_formal.sv"]
    converted = run(["sv2v", "-DFORMAL", "-DSV_ASSRT_DISABLE", f"-I{COMMON}",
                     *(str(p) for p in sources)], tmp_path, "sv2v")
    (tmp_path / "formal.v").write_text(converted)
    script = (f"read_verilog -formal {tmp_path / 'formal.v'}; "
              "prep -top tiny_r2_p4_formal -flatten; memory_map; async2sync; dffunmap; opt; "
              "sat -seq 12 -tempinduct -prove-asserts -verify -set-init-zero")
    content = run(["yosys", "-p", script], tmp_path, "formal", timeout=180)
    assert "Induction step proven: SUCCESS!" in content


def p4_log():
    from test_tiny_r2_p3 import sample_log
    lines = [sample_log()]
    for window in range(1, 9):
        for port in range(2):
            lines.append(f"R2_P4_LOCAL window={window} port={port} accepted=3 completed=3 "
                         "latency_max=3 admission_wait=0")
        for group in range(4):
            lines.append(f"R2_P4_BANK window={window} group={group} issues_i=2 issues_d=1 "
                         "issues_external=0 conflicts=0 wait_i=0 wait_d=0 wait_external=0")
    return "\n".join(lines)


def test_p4_acceptance_retains_local_and_external_accounting():
    samples = p4.parse_log(p4_log(), {"status": "passed", "exit_code": 0})
    assert len(samples["local"]) == 16 and len(samples["banks"]) == 32
    assert samples["cases"][2]["checksum"] == 0xc4a58dc5


@pytest.mark.parametrize("mutation", ["exit", "marker", "missing", "duplicate", "accounting"])
def test_p4_rejects_incomplete_or_failed_evidence(mutation):
    text = p4_log()
    flow = {"status": "passed", "exit_code": 0}
    if mutation == "exit":
        flow["exit_code"] = 124
    elif mutation == "marker":
        text += "\nSIM_TEST_TIMEOUT"
    elif mutation == "missing":
        text = "\n".join(line for line in text.splitlines() if not line.startswith("R2_P4_BANK window=8"))
    elif mutation == "duplicate":
        text += "\n" + next(line for line in text.splitlines() if line.startswith("R2_P4_LOCAL"))
    else:
        text = text.replace("accepted=3 completed=3", "accepted=3 completed=4")
    with pytest.raises(ValueError):
        p4.parse_log(text, flow)


@pytest.mark.parametrize("key", p4.HARDWARE_KEYS)
def test_p4_rejects_mismatched_hardware(key):
    values = dict.fromkeys(p4.HARDWARE_KEYS, "same")
    with pytest.raises(ValueError):
        p4.compatible_hardware({"configuration": values}, {"configuration": values | {key: "other"}})


def test_p4_preserves_independent_image_compiler_identity():
    hardware = dict.fromkeys(p4.HARDWARE_KEYS, "same")
    p4.compatible_hardware({"configuration": hardware | {"SW_OPT": "O2"}},
                           {"configuration": hardware | {"SW_OPT": "APP"}})
