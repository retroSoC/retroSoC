"""Execute the actual shared PSRAM/P8 checks and non-terminating P9 monitor."""

import re
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from test_tiny_r2_p7 import ROOT, run_rtl


@pytest.fixture(scope="module", params=["iverilog", "verilator"])
def observer_simulator(request, tmp_path_factory):
    backend = request.param
    directory = tmp_path_factory.mktemp(f"psram-observer-{backend}")
    run_rtl(directory, backend, "tiny_psram_observers_tb", [],
            defines=[f"-I{ROOT / 'rtl/tiny/dv'}"])
    launch = [str(directory / "sim")] if backend == "verilator" else ["vvp", str(directory / "sim")]
    return launch, directory


@pytest.mark.parametrize("name,args,error", [
    ("p9_population", ["+tiny_psram", "+tiny_p9_camera"], None),
    ("p8_ok", ["+tiny_p8_psram", "+windows", "+write"], None),
    ("p8_missing_windows", ["+tiny_p8_psram", "+short_windows", "+write"],
     "SIM_TEST_FAIL P8 missing mapped transport evidence"),
    ("p8_missing_write", ["+tiny_p8_psram", "+windows"],
     "SIM_TEST_FAIL P8 missing mapped transport evidence"),
    ("absent_ok", ["+tiny_p8_psram", "+p8_absent"], None),
    ("absent_write", ["+tiny_p8_psram", "+p8_absent", "+write"],
     "SIM_TEST_FAIL P8 absent device exposed mapped writes"),
    ("generic_cs", ["+tiny_psram", "+cs_violation"],
     "SIM_TEST_FAIL P8 active CS exceeds 8 us"),
    ("legacy_cs", ["+tiny_p8_psram", "+cs_violation"],
     "SIM_TEST_FAIL P8 active CS exceeds 8 us"),
    ("monitor", ["+tiny_psram", "+tiny_p9_camera", "+tiny_p9_monitor",
                 "+monitor_duration", "+write"], None),
    ("monitor_diag", ["+tiny_p9_camera", "+tiny_p9_monitor", "+tiny_p9_diag"],
     "SIM_TEST_FAIL P9 monitor conflicts"),
    ("monitor_long", ["+tiny_p9_camera", "+tiny_p9_monitor", "+tiny_p9_diag_long"],
     "SIM_TEST_FAIL P9 monitor conflicts"),
    ("monitor_legacy", ["+tiny_p9_camera", "+tiny_p9_monitor", "+tiny_p9_progress"],
     "SIM_TEST_FAIL P9 monitor conflicts"),
    ("monitor_no_camera", ["+tiny_p9_monitor"],
     "SIM_TEST_FAIL P9 monitor requires camera mode"),
    ("monitor_missing_log", ["+tiny_p9_camera", "+tiny_p9_monitor"],
     "SIM_TEST_FAIL P9 monitor requires log path"),
])
def test_observer_modes(observer_simulator, name, args, error):
    launch, directory = observer_simulator
    progress = directory / f"{name}-progress.log"
    log_args = ([f"+tiny_p9_monitor_log={progress}"]
                if "+tiny_p9_monitor" in args and name != "monitor_missing_log" else [])
    result = subprocess.run([*launch, *args, *log_args], cwd=directory, capture_output=True,
                            text=True, timeout=60)
    log = result.stdout + result.stderr
    (directory / f"{name}.log").write_text(log)
    if error:
        assert error in log and DEFAULT_FAILURE.search(log), log
        assert "SIM_TEST_PASS" not in log, log
    else:
        assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
        assert "SIM_TEST_PASS Tiny PSRAM observer fixture" in log, log
        if name == "monitor":
            assert "MONITOR_SURVIVED" in log
            assert "P9_PROGRESS" not in log and "P9_MONITOR_BEGIN" not in log
            assert "P9_PROGRESS ref=5000000" in progress.read_text()


def test_generic_psram_population_binding():
    source = (ROOT / "rtl/tiny/dv/retrosoc_tiny_tb.sv").read_text()
    assert '$test$plusargs("tiny_psram")' in re.sub(r"\s+", "", source)
    assert '"tiny_p8_psram"' in source and '"p8_absent"' in source
    assert ".csn (s_psram_csn)" in source
