"""Tiny reset distribution and early timing-feasibility contracts."""

from __future__ import annotations

import os
import json
from pathlib import Path
import shutil
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts import tiny_r2_feasibility as feasibility

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"


def run(command: list[str], log: Path, **kwargs) -> str:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)
    log.write_text(result.stdout)
    assert result.returncode == 0, result.stdout
    assert not DEFAULT_FAILURE.search(result.stdout), result.stdout
    return result.stdout


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
@pytest.mark.parametrize("fixture,marker", [
    ("tiny_r2_reset_tb", "SIM_TEST_PASS Tiny R2 reset"),
    ("tiny_r2_fifo_reset_tb", "SIM_TEST_PASS Tiny R2 FIFO reset"),
])
def test_reset_and_fifo_contracts(tmp_path: Path, simulator: str, fixture: str, marker: str) -> None:
    assert shutil.which(simulator), f"required simulator unavailable: {simulator}"
    sources = [COMMON / "utils/register.sv", COMMON / "clkrst/rst_sync.sv",
               COMMON / "utils/fifo.sv", ROOT / "rtl/tiny/top/tiny_reset_tree.sv",
               ROOT / "rtl/ip/core/mgmt_debug_reset.sv", ROOT / f"tests/rtl/{fixture}.sv"]
    includes = [f"-I{COMMON}", "-DSV_ASSRT_DISABLE"]
    output = tmp_path / "sim"
    if simulator == "iverilog":
        assert shutil.which("vvp"), "required Icarus runtime unavailable"
        command = [simulator, "-g2012", "-s", fixture, *includes,
                   *(str(p) for p in sources), "-o", str(output)]
        launch = ["vvp", str(output)]
    else:
        command = [simulator, "--binary", "--timing", "--assert", "-Wno-fatal",
                   "--top-module", fixture, *includes, *(str(p) for p in sources),
                   "--Mdir", str(tmp_path / "obj"), "-o", str(output)]
        launch = [str(output)]
    run(command, tmp_path / "compile.log", env={**os.environ, "CCACHE_DISABLE": "1"}, timeout=120)
    content = run(launch, tmp_path / "sim.log", timeout=30)
    assert marker in content
    assert "SIM_TEST_FAIL" not in content and "SIM_TEST_TIMEOUT" not in content


def test_reset_inventory_has_one_clock_and_all_existing_targets() -> None:
    topology = json.loads((ROOT / "rtl/tiny/integration/soc_topology.json").read_text())
    inventory = json.loads((ROOT / "rtl/tiny/integration/clock_reset_domains.json").read_text())
    reset = inventory["reset_distribution"]
    assert reset["release_edges"] == 5
    assert reset["leaf_names"] == ["fabric", *(target["name"] for target in topology["apb_targets"])]
    assert len(reset["leaf_names"]) == 17
    assert {domain["name"] for domain in inventory["domains"]} == {"system", "jtag"}
    assert reset["clock_domain"] == "system" and reset["main_sram_payload_reset"] == "none"


SDC = ("create_clock -name clk_system -period 41.666666667 $clk_system_pin\n"
       "create_clock -name clk_jtag -period 100 $clk_jtag_port\n"
       "set_false_path -from [all_inputs]\nset_clock_uncertainty -setup 0.2 [all_clocks]\n")


@pytest.mark.parametrize("mhz", [24, 96, 192, 240])
def test_analysis_only_changes_the_system_period(mhz: int) -> None:
    output = feasibility.candidate_sdc(SDC, mhz)
    assert output.splitlines()[1:] == SDC.splitlines()[1:]
    assert float(output.splitlines()[0].split()[4]) == pytest.approx(1000 / mhz)
    if mhz == 24:
        assert output == SDC


@pytest.mark.parametrize("sdc,mhz", [(SDC, 48), (SDC + SDC, 96),
                                      (SDC.replace("clk_system", "clk_other"), 96),
                                      (SDC.replace("41.666666667", "5"), 96)])
def test_feasibility_rejects_wrong_source_clock_or_rate(sdc: str, mhz: int) -> None:
    with pytest.raises(ValueError):
        feasibility.candidate_sdc(sdc, mhz)


@pytest.mark.parametrize("content", ["wns_max=wns max -1.0\n", "", "wns_min=0\nwns_max=nan\ntns_min=0\ntns_max=0\n"])
def test_incomplete_or_invalid_metrics_cannot_pass(tmp_path: Path, content: str) -> None:
    report = tmp_path / "metrics.rpt"
    report.write_text(content)
    with pytest.raises(ValueError):
        feasibility.timing_metrics(report)


@pytest.mark.parametrize("mutation", ["none", "missing", "merged"])
def test_reset_loads_require_seventeen_independent_leaves(tmp_path: Path, mutation: str) -> None:
    report = tmp_path / "loads.tsv"
    lines = ["name\tdrivers\tdirect_loads\tstructural_endpoints", "system\troot/Q\t85\t1000"]
    lines += [f"leaf-{i}\tleaf{i}/Q\t10\t20" for i in range(17)]
    if mutation == "missing":
        lines.pop()
    if mutation == "merged":
        lines[-1] = "leaf-16\tleaf0/Q\t10\t20"
    report.write_text("\n".join(lines))
    if mutation == "none":
        assert len(feasibility.reset_loads(report, True)) == 18
    else:
        with pytest.raises(ValueError):
            feasibility.reset_loads(report, True)


@pytest.mark.parametrize("content,expected", [("  -1.25 slack (VIOLATED)\n", -1.25),
                                             ("  0.50 slack (MET)\n", 0.5),
                                             ("No paths found.\n", None)])
def test_sys_data_slack_is_separate_from_aggregate_recovery(tmp_path, content, expected) -> None:
    path = tmp_path / "sys-setup.rpt"
    path.write_text(content)
    if expected is None:
        with pytest.raises(ValueError, match="missing constrained"):
            feasibility.path_slack(path)
    else:
        assert feasibility.path_slack(path) == expected
