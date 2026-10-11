"""P5 target concurrency, fault accounting and retained-image acceptance."""
from __future__ import annotations

import shutil
import subprocess
import json
from pathlib import Path

import pytest

from scripts.generate_tiny import generate_bindings, generate_filelists, read_topology
from scripts.rtl.filelist import parse_filelists
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from test_tiny_r2_p4 import run
from scripts import tiny_r2_p5 as p5

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
TINY = ROOT / "rtl/tiny/top"


def sources(tmp_path):
    generate_memory_map(ROOT / "rtl/tiny/address_map/memory_map.json", tmp_path / "map", "YES", 128)
    generate_bindings(read_topology(ROOT / "rtl/tiny/integration/soc_topology.json",
                                   ROOT / "rtl/tiny/address_map/memory_map.json"), tmp_path / "bindings")
    files = [COMMON / p for p in ("utils/register.sv", "utils/spill_register.sv",
             "utils/fifo.sv", "stream/round_robin_arbiter.sv", "interface/axi4_if.sv",
             "interface/axi4_addr_gen.sv", "interface/apb4_if.sv", "interface/ahbl_if.sv")]
    files += [TINY / p for p in ("tiny_axi4_target.sv", "tiny_axi4_fabric.sv",
              "tiny_axi42apb4.sv", "tiny_fault_collector.sv", "tiny_sysctrl.sv")]
    files += [ROOT / "rtl/ip/interconnect/axi4_error_slave.sv"]
    includes = [f"-I{p}" for p in (COMMON, COMMON / "interface", tmp_path / "map/rtl",
                 tmp_path / "bindings/rtl", ROOT / "rtl/ip/peripheral", ROOT / "tests/rtl")]
    return files, includes


def simulate(tmp_path, simulator, top, files, includes, arguments=()):
    for tool in (simulator, "sv2v", "vvp"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    binary = tmp_path / "sim"
    if simulator == "verilator":
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "3",
             "-DHAVE_SVA", "-DSV_ASSRT_DISABLE", "--top-module", top, *includes,
             *(str(p) for p in files), "--Mdir", str(tmp_path / "obj"), "-o", str(binary)],
            tmp_path, "compile", timeout=300)
        launch = [str(binary)]
    else:
        # Conversion warnings are diagnostics, never Verilog source text.
        converted = subprocess.run(["sv2v", "-DSV_ASSRT_DISABLE", *includes,
                                    *(str(p) for p in files)], text=True,
                                   capture_output=True, timeout=300)
        (tmp_path / "sv2v.log").write_text(converted.stderr)
        assert converted.returncode == 0, converted.stderr
        (tmp_path / "converted.v").write_text(converted.stdout)
        run([simulator, "-g2012", "-s", top, "-o", str(binary), str(tmp_path / "converted.v")],
            tmp_path, "compile")
        launch = ["vvp", str(binary)]
    log = run([*launch, *arguments], tmp_path, "sim", timeout=180)
    assert "SIM_TEST_PASS Tiny P5" in log
    return log


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_concurrent_fabric(tmp_path, simulator):
    files, includes = sources(tmp_path)
    files.append(ROOT / "tests/rtl/tiny_r2_p5_fabric_tb.sv")
    log = simulate(tmp_path, simulator, "tiny_r2_p5_fabric_tb", files, includes)
    assert "random_reads=96 concurrent_faults=2" in log


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_target_reset_isolation(tmp_path, simulator):
    files, includes = sources(tmp_path)
    files.append(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv")
    files.append(ROOT / "tests/rtl/tiny_r2_p5_reset_tb.sv")
    log = simulate(tmp_path, simulator, "tiny_r2_p5_reset_tb", files, includes)
    assert "SIM_TEST_PASS Tiny P5 target reset isolation" in log
    assert "P5_RESET cases=28 production_dma=3 burst_beats=16 held_RB=1 first_fault=1" in log


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_real_cpu_dma_progress_and_abort(tmp_path, simulator):
    sources(tmp_path)
    firmware = tmp_path / "cpu.elf"
    run(["riscv32-unknown-elf-gcc", "-march=rv32imc_zicsr_zifencei", "-mabi=ilp32",
         "-nostdlib", "-Wl,--build-id=none", "-T", str(ROOT / "tests/rtl/tiny_r2_p4_cpu.ld"),
         str(ROOT / "tests/rtl/tiny_r2_p5_cpu.S"), "-o", str(firmware)], tmp_path, "firmware")
    run(["riscv32-unknown-elf-objcopy", "-O", "verilog", str(firmware), str(tmp_path / "cpu.hex")],
        tmp_path, "objcopy")
    generate_filelists(tmp_path / "filelists", tmp_path / "bindings", [])
    resolved = parse_filelists(tmp_path / "filelists" / name for name in (
        "inc.fl", "commonip.fl", "clusterip.fl", "core_hazard3.fl", "ip.fl", "tech.fl", "top.fl"))
    # Only the XPI boundary is substituted; the production CPU/DMA/SoC stay real.
    files = [p for p in resolved.files if p.name not in ("apb4_xpi.sv", "retrosoc_tiny_asic.sv")]
    files.append(ROOT / "tests/rtl/tiny_r2_p5_system_tb.sv")
    run(["python3", str(ROOT / "rtl/managed/clusterip/archinfo/scripts/generate_metadata.py"),
         "--repo-root", str(ROOT), "--lock", str(ROOT / "dependencies/dependencies.lock.json"),
         "--config-digest", "000000000000", "--output-sv", str(tmp_path / "archinfo_integration_metadata.svh"),
         "--output-c", str(tmp_path / "archinfo_integration_metadata.h")], tmp_path, "metadata")
    includes = [f"-I{p}" for p in (*resolved.incdirs, tmp_path, tmp_path / "map/rtl",
                                   tmp_path / "bindings/rtl", ROOT / "rtl/tiny/dv")]
    includes += ["-DPDK_BEHAV", "-DRETROSOC_SOC__TINY", "-DSOC_JTAG_IDCODE=32'hDEADBEEF"]
    log = simulate(tmp_path, simulator, "tiny_r2_p5_system_tb", files, includes,
                   [f"+firmware={tmp_path / 'cpu.hex'}"])
    assert "hart_reset=1 abort_drained=1" in log


@pytest.mark.parametrize("kind", ["fabric", "fabric_reset", "fault"])
def test_protocol_proofs(tmp_path, kind):
    for tool in ("sv2v", "yosys"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    files, includes = sources(tmp_path)
    top = f"tiny_r2_p5_{'fabric' if kind == 'fabric_reset' else kind}_formal"
    files.append(ROOT / f"tests/rtl/{top}.sv")
    reset_define = ["-DTINY_P5_RESET_FORMAL"] if kind == "fabric_reset" else []
    converted = subprocess.run(["sv2v", "-DFORMAL", "-DSV_ASSRT_DISABLE", *reset_define, *includes,
                                *(str(p) for p in files)], text=True, capture_output=True, timeout=180)
    (tmp_path / "sv2v.log").write_text(converted.stderr)
    assert converted.returncode == 0, converted.stderr
    (tmp_path / "formal.v").write_text(converted.stdout)
    proof = "sat -prove-asserts -verify" if kind == "fault" else (
        "sat -seq 12 -tempinduct -prove-asserts -verify -set-init-zero")
    script = (f"read_verilog -formal {tmp_path / 'formal.v'}; prep -top {top} -flatten; "
              f"memory_map; async2sync; dffunmap; opt; {proof}")
    log = run(["yosys", "-p", script], tmp_path, "formal", timeout=300)
    assert "SUCCESS!" in log


def p5_log():
    from test_tiny_r2_p4 import p4_log
    return p4_log() + "\n" + "\n".join(
        f"R2_P5_FABRIC window={window} active_targets_max=3 "
        "dma_rw_overlap_cycles=5 dma_rw_beat_overlap_cycles=2" for window in range(1, 9))


def test_p5_records_keep_old_image_measurements_separate():
    samples = p5.parse_log(p5_log(), {"status": "passed", "exit_code": 0})
    assert len(samples["fabric"]) == 8
    assert len(samples["local"]) == 16
    assert p5.PHASE == "TINY-R2-P5" and p5.previous.PHASE == "TINY-R2-P4"


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "negative", "overflow", "overlap", "serialized", "failure"])
def test_p5_rejects_invalid_concurrency_evidence(mutation):
    content = p5_log()
    if mutation == "missing":
        content = "\n".join(line for line in content.splitlines() if not line.startswith("R2_P5_FABRIC window=8"))
    elif mutation == "duplicate":
        content += "\n" + content.splitlines()[-1]
    elif mutation == "negative":
        content = content.replace("active_targets_max=3", "active_targets_max=-1")
    elif mutation == "overflow":
        content = content.replace("active_targets_max=3", "active_targets_max=24")
    elif mutation == "overlap":
        content = content.replace("dma_rw_beat_overlap_cycles=2", "dma_rw_beat_overlap_cycles=6")
    elif mutation == "serialized":
        content = content.replace("active_targets_max=3", "active_targets_max=1")
    else:
        content += "\nSIM_TEST_FAIL"
    with pytest.raises(ValueError):
        p5.parse_log(content, {"status": "passed", "exit_code": 0})


@pytest.mark.parametrize("mutation", ["none", "phase", "source", "cycles", "image", "local"])
def test_p5_reference_is_bound_to_p4_execution(tmp_path, monkeypatch, mutation):
    case = {"name": "flat", "image": {"path": "immutable"},
            "samples": {"cases": [{"name": "dma16", "cycles": 17897, "instructions": 10}],
                        "local": [], "banks": []}}
    report = {"phase": "TINY-R2-P4", "status": "measurement_complete", "source_digest": "original",
              "executions": {"verilator": {}}, "comparisons": [
                  {"name": "flat", "image": {"path": "immutable"}, "local": [], "banks": [],
                   "workloads": [{"name": "dma16", "candidate_cycles": 17897, "candidate_instructions": 10}]}]}
    monkeypatch.setattr(p5.previous, "validate_replay", lambda *args: {
        "source_digest": "original", "cases": [case]})
    monkeypatch.setattr(p5.b, "check_artifact", lambda artifact: tmp_path / "record.json")
    if mutation == "phase":
        report["phase"] = "TINY-R2-P5"
    elif mutation == "source":
        report["source_digest"] = "other"
    elif mutation == "cycles":
        report["comparisons"][0]["workloads"][0]["candidate_cycles"] = 1
    elif mutation == "image":
        report["comparisons"][0]["image"]["path"] = "different"
    elif mutation == "local":
        report["comparisons"][0]["local"] = [{}]
    path = tmp_path / "report.json"
    path.write_text(json.dumps(report))
    if mutation == "none":
        assert p5.reference_cases(path, ["flat"]) == [case]
    else:
        with pytest.raises(ValueError):
            p5.reference_cases(path, ["flat"])
