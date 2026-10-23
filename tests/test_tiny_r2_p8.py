"""Pin-level XPI PSRAM transport; no fast NOR or separate RAM controller."""
import subprocess

import pytest

from test_tiny_r2_p7 import COMMON, ROOT, run_rtl
from scripts.check_simulation import DEFAULT_FAILURE


@pytest.fixture(scope="module", params=["iverilog", "verilator"])
def xpi_simulator(request, tmp_path_factory):
    simulator = request.param
    tmp_path = tmp_path_factory.mktemp(f"p8-{simulator}")
    run_rtl(tmp_path, simulator, "tiny_p8_xpi_tb", [
        COMMON / "utils/fifo.sv", COMMON / "interface/axi4_addr_gen.sv",
        *[ROOT / "rtl/ip/storage" / name for name in (
            "xpi_if.sv", "xpi_reg.sv", "xpi_mm.sv", "xpi_indirect.sv",
            "xpi_clkgen.sv", "xpi_core.sv", "apb4_xpi.sv")],
        ROOT / "rtl/model/ESP_PSRAM64H.sv",
    ], defines=[f"-I{ROOT / 'rtl/ip/storage'}", "-DRETROSOC_SOC__TINY"],
        packages=[ROOT / "rtl/ip/storage/xpi_pkg.sv"], plusargs=["+identity"])
    launch = [str(tmp_path / "sim")] if simulator == "verilator" else ["vvp", str(tmp_path / "sim")]
    return launch, tmp_path


@pytest.mark.parametrize("scenario", ["mapped", "boundary", "lanes", "timeout", "held_read",
                                      "short_read", "late_error"])
def test_xpi_psram_pins(xpi_simulator, scenario: str) -> None:
    launch, directory = xpi_simulator
    result = subprocess.run([*launch, f"+{scenario}"], capture_output=True, text=True, timeout=30)
    log = result.stdout + result.stderr
    (directory / f"{scenario}.log").write_text(log)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
    assert "SIM_TEST_PASS Tiny P8 XPI pins" in log, log
