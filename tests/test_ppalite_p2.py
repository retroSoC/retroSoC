"""PPALITE-P2 real DVP/route/source integration checks."""
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from test_tiny_r2_p7 import COMMON, ROOT, run_rtl

IP = ROOT / "rtl/ip"
PPA = IP / "ppalite"


@pytest.fixture(scope="module", params=["iverilog", "verilator"])
def route_simulator(request, tmp_path_factory):
    backend = request.param
    directory = tmp_path_factory.mktemp(f"ppalite-route-{backend}")
    sources = [
        *[COMMON / path for path in (
            "interface/axi4_stream_if.sv", "utils/spill_register.sv", "utils/edge_det.sv",
            "cdc/async_reqack.sv", "cdc/cdc_fifo.sv", "cdc/cdc_warm_flush.sv")],
        ROOT / "rtl/tech/tc_clk.sv",
        *[IP / "multimedia" / name for name in ("dvp_core.sv", "dvp_reg.sv", "axi4s_dvp.sv")],
        IP / "util/soc_common_fifo.sv",
        *[PPA / f"{name}.sv" for name in (
            "ppalite_if", "ppalite_fifo", "ppalite_decimator", "ppalite_packer",
            "ppalite_stream_guard", "ppalite_core", "ppalite_reg", "apb4_ppalite")],
        ROOT / "rtl/tiny/top/ppalite_route_ctrl.sv",
        ROOT / "physical/smoke/syn/yosys/apb4_ppalite_route_top.sv",
    ]
    run_rtl(directory, backend, "ppalite_route_tb", sources,
            defines=["-DPDK_BEHAV", f"-I{IP / 'multimedia'}", f"-I{PPA}",
                     f"-I{COMMON / 'utils'}", f"-I{ROOT / 'rtl/tiny/top'}"])
    launch = [str(directory / "sim")] if backend == "verilator" else ["vvp", str(directory / "sim")]
    return launch, directory


@pytest.mark.parametrize("case_id", range(1, 19))
def test_route_and_source(route_simulator, case_id):
    launch, directory = route_simulator
    result = subprocess.run([*launch, f"+case={case_id}"], cwd=directory,
                            capture_output=True, text=True, timeout=120)
    log = result.stdout + result.stderr
    (directory / f"case-{case_id}.log").write_text(log)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
    assert f"SIM_TEST_PASS PPALITE_P2 case={case_id}" in log, log
