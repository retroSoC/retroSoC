"""DVP word-counter boundaries through real pixel capture, CDC and APB."""
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from test_tiny_r2_p7 import COMMON, ROOT, run_rtl


@pytest.fixture(scope="module", params=["iverilog", "verilator"])
def stats_simulator(request, tmp_path_factory):
    backend = request.param
    directory = tmp_path_factory.mktemp(f"dvp-stats-{backend}")
    run_rtl(directory, backend, "dvp_stats_tb", [
        *[COMMON / path for path in (
            "interface/axi4_stream_if.sv", "utils/fifo.sv", "utils/spill_register.sv",
            "utils/edge_det.sv", "cdc/async_reqack.sv", "cdc/cdc_fifo.sv",
            "cdc/cdc_warm_flush.sv")],
        ROOT / "rtl/tech/tc_clk.sv",
        *[ROOT / "rtl/ip/multimedia" / name for name in (
            "dvp_core.sv", "dvp_reg.sv", "axi4s_dvp.sv")],
    ], defines=["-DPDK_BEHAV", f"-I{ROOT / 'rtl/ip/multimedia'}"])
    launch = [str(directory / "sim")] if backend == "verilator" else ["vvp", str(directory / "sim")]
    return launch, directory


@pytest.mark.parametrize("case,words,extra", [
    (1, 65535, []), (2, 65536, ["+pause_host"]),
    (3, 153600, ["+pause_host", "+yuv"]), (4, 65536, []), (5, 32768, []),
])
def test_full_frame_statistics(stats_simulator, case, words, extra):
    launch, directory = stats_simulator
    result = subprocess.run([*launch, f"+case={case}", *extra], cwd=directory,
                            capture_output=True, text=True, timeout=120)
    log = result.stdout + result.stderr
    (directory / f"case-{case}.log").write_text(log)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
    assert f"SIM_TEST_PASS DVP statistics case={case}" in log, log
    assert f"words={words} " in log and "frame=2 width=4 height=2 words=4" in log
