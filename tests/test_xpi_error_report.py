"""Actual shared XPI error metadata and IRQ paths; compile once per backend."""
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from test_tiny_r2_p7 import COMMON, ROOT, run_rtl


@pytest.fixture(scope="module", params=["tiny-iverilog", "tiny-verilator", "mini-verilator"])
def error_simulator(request, tmp_path_factory):
    consumer, simulator = request.param.split("-")
    directory = tmp_path_factory.mktemp(request.param)
    sources = [COMMON / "utils/fifo.sv", COMMON / "interface/axi4_addr_gen.sv",
               *[ROOT / "rtl/ip/storage" / name for name in (
                   "xpi_if.sv", "xpi_reg.sv", "xpi_mm.sv", "xpi_indirect.sv",
                   "xpi_clkgen.sv", "xpi_core.sv", "apb4_xpi.sv")]]
    defines = [f"-I{ROOT / 'rtl/ip/storage'}"]
    if consumer == "tiny":
        defines.append("-DRETROSOC_SOC__TINY")
    else:
        defines.append("-DSIMU_VERILATOR")
        sources += [*[ROOT / "rtl/mini/dv/verilator/rtl" / name for name in (
            "flash_read_byte_binder.sv", "xpi_fast_flash_model.sv", "xpi_core_verilator.sv")],
            ROOT / "tests/rtl/xpi_fast_flash_dpi.cpp", ROOT / "tests/rtl/xpi_error_report_dpi.cpp"]
    run_rtl(directory, simulator, "xpi_error_report_tb", sources, defines=defines,
            packages=[ROOT / "rtl/ip/storage/xpi_pkg.sv"])
    launch = [str(directory / "sim")] if simulator == "verilator" else ["vvp", str(directory / "sim")]
    return launch, directory


@pytest.mark.parametrize("case", range(1, 13))
def test_error_metadata_and_irq(error_simulator, case):
    launch, directory = error_simulator
    result = subprocess.run([*launch, f"+case={case}"], capture_output=True, text=True, timeout=30)
    content = result.stdout + result.stderr
    (directory / f"case-{case}.log").write_text(content)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
    assert f"SIM_TEST_PASS XPI error report case={case}" in content, content
