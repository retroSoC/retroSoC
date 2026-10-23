"""Tiny R2-P9 DVP topology, HAL binding and executable configuration checks."""

from __future__ import annotations

import json
import re
import subprocess
import shutil
from pathlib import Path

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts.generate_tiny import generate_bindings, read_topology
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from test_tiny_r2_p7 import COMMON, run_rtl

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def test_p9_console_startup_host(tmp_path: Path) -> None:
    compiler = shutil.which("cc")
    assert compiler is not None
    executable = tmp_path / "tiny_p9_startup"
    result = subprocess.run([
        compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-I", str(ROOT / "crt/include"),
        "-I", str(ROOT),
        str(ROOT / "tests/c/test_tiny_p9_startup.c"), "-o", str(executable),
    ], cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr

    result = subprocess.run([str(executable)], cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_p9_topology_and_camera_routes() -> None:
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    memory = json.loads((TINY / "address_map/memory_map.json").read_text())
    regions = {item["symbol"]: item for item in memory["regions"]}
    assert regions["APB4_DVP"]["base"] == "0x1000E000"
    assert topology["fabric"]["target_count"] == 29
    assert topology["fabric"]["decode_error_target"] == 27
    assert topology["fabric"]["protocol_error_target"] == 28
    assert any(item["name"] == "dvp" and item["regions"] == ["APB4_DVP"]
               for item in topology["apb_targets"])
    assert {item["core_bit"] for item in topology["interrupts"] if item["name"] == "dvp"} == {15}
    routes = {item["pin"]: item for item in topology["gpio_alt_functions"]}
    assert [routes[pin]["alt1"]["inputs"][0] for pin in range(12, 20)] == [
        f"u_dvp_if.dat_i[{index}]" for index in range(8)
    ]
    assert routes[20]["alt1"]["inputs"] == ["u_dvp_if.pclk_i"]
    assert routes[21]["alt1"]["inputs"] == ["u_dvp_if.href_i"]
    assert routes[22]["alt1"]["inputs"] == ["u_dvp_if.vsync_i"]
    assert routes[23]["alt1"]["do"] == "s_clkout"
    assert read_topology(TINY / "integration/soc_topology.json",
                         TINY / "address_map/memory_map.json")["dma_request_mask"] == "0x339ff"


def test_p9_generated_and_hal_bindings() -> None:
    generator = (ROOT / "scripts/generate_tiny.py").read_text()
    hal = (ROOT / "crt/src/hal/dvp.c").read_text()
    assert '"dvp": 14' in generator
    assert "RS_SOC_HAS_DVP 1U" in generator
    assert "RS_DVP_DMA_CHANNEL RS_DMA_CHANNEL_DVP" in hal
    assert "RS_SOC_DVP_DMA_BURST_BEATS" in hal
    assert "rs_dvp_capture_pio" in hal
    assert "rs_dma_wait(RS_DVP_DMA_CHANNEL" in hal
    assert "RS_DMA_CHANNEL_BULK" in hal  # Mini compatibility fallback remains explicit.


def test_p9_recovery_irq_uses_generated_external_id(tmp_path):
    generate_bindings(read_topology(TINY / "integration/soc_topology.json",
                                   TINY / "address_map/memory_map.json"), tmp_path)
    header = (tmp_path / "include/retrosoc/generated/irq_metadata.h").read_text()
    assert "RS_SOC_IRQ_DVP UINT32_C(15)" in header
    assert "RS_SOC_EXT_IRQ_DVP UINT32_C(13)" in header
    wrapper = (TINY / "top/tiny_cpu_wrapper.sv").read_text()
    assert ".irq                       (irq_i[ExternalIrqCount+1:2])" in wrapper
    application = (ROOT / "app/apps/ci_smoke/tiny_r2_p9_recovery.c").read_text()
    assert "rs_irq_enable_external(RS_SOC_EXT_IRQ_DVP, rs_p9_recovery_irq)" in application


def test_p9_status_register_parity() -> None:
    sv = (ROOT / "rtl/ip/multimedia/dvp_define.svh").read_text()
    c = (ROOT / "crt/src/hal/dvp.c").read_text()
    for name in ("ENABLE", "ACTIVE", "FIFO_EMPTY", "ERROR"):
        bit = int(re.search(rf"`define APB4_DVP__STATUS_{name}\s+(\d+)", sv)[1])
        mask = int(re.search(rf"#define RS_DVP_STATUS_{name}_MASK\s+UINT32_C\(0x([0-9A-F]+)\)", c)[1], 16)
        assert mask == 1 << bit


def test_p9_acceptance_image_is_explicit() -> None:
    result = subprocess.run(
        ["make", "--no-print-directory", "-n", "CONFIG=configs/ci/ics55-tiny.mk",
         "APP=ci_smoke", "TINY_P9_ACCEPTANCE=YES", "firmware"],
        cwd=ROOT, text=True, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "tiny_r2_p9.c" in result.stdout
    assert "crt/src/hal/dvp.c" in result.stdout


def test_p9_workload_configuration_identity() -> None:
    base = ["make", "--no-print-directory", "CONFIG=configs/ci/ics55-tiny.mk", "SOC=TINY",
            "PDK=ICS55", "APP=ci_smoke", "TINY_P9_ACCEPTANCE=YES", "BUILD_TIMESTAMP=2026-10-16-00-00"]
    def config(extra):
        return subprocess.run([*base, *extra, "config"], cwd=ROOT, text=True,
                              capture_output=True, check=False)
    qvga = config([])
    vga = config(["TINY_P9_WORKLOAD=VGA_YUV422"])
    assert qvga.returncode == 0 and vga.returncode == 0
    def variant(result):
        return dict(line.split(None, 1) for line in result.stdout.splitlines() if line.strip())["VARIANT_ROOT"]
    assert variant(qvga) != variant(vga)
    explicit_default = config(["TINY_P9_WORKLOAD=QVGA_RGB565"])
    assert explicit_default.returncode == 0 and variant(qvga) == variant(explicit_default)
    for extra in (["TINY_P9_WORKLOAD=VGA_YUV422", "TINY_P9_QUICK=YES"],
                  ["TINY_P9_WORKLOAD=VGA_YUV422", "TINY_P9_ACCEPTANCE=NO"],
                  ["TINY_P9_WORKLOAD=TYPO"]):
        assert config(extra).returncode != 0
    build = subprocess.run([*base, "TINY_P9_WORKLOAD=VGA_YUV422", "-n", "firmware"],
                           cwd=ROOT, text=True, capture_output=True, check=False)
    assert build.returncode == 0 and "-DRS_TINY_P9_VGA_YUV422" in build.stdout
    recovery = config(["TINY_P9_WORKLOAD=RECOVERY"])
    assert recovery.returncode == 0 and variant(recovery) not in (variant(qvga), variant(vga))
    build = subprocess.run([*base, "TINY_P9_WORKLOAD=RECOVERY", "-n", "firmware"],
                           cwd=ROOT, text=True, capture_output=True, check=False)
    assert build.returncode == 0 and "tiny_r2_p9_recovery.c" in build.stdout


def test_p9_compact_netlist_register_parity():
    source = (ROOT / "app/asm/tiny_p9_netlist.S").read_text()
    gpio = (ROOT / "crt/src/hal/gpio.c").read_text()
    dvp = (ROOT / "rtl/ip/multimedia/dvp_define.svh").read_text()
    for name, offset in (("ALT_ENABLE", "034"), ("ALT_SELECT", "038"), ("OE_CLEAR", "01C")):
        assert re.search(rf"RS_GPIO_{name}_OFFSET\s+UINT32_C\(0x{offset}\)", gpio)
        assert f"0x{offset.lower()}(s0)" in source
    for name, offset in (("FRAME_COUNT", "024"), ("LINE_COUNT", "028"), ("PIXEL_COUNT", "02c"),
                         ("WORD_COUNT", "030"), ("RXDATA", "004"), ("ERROR_STATUS", "038")):
        assert re.search(rf"APB4_DVP_{name}\s+12'h{offset}", dvp, re.I)
        assert f"0x{offset}(s1)" in source


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_p9_audio_observer_modes(tmp_path, simulator):
    source = (TINY / "dv/tiny_p6_devices.svh").read_text()
    observer = source[source.index("integer s_p6_wire_cases"):source.index("logic        s_p6_busy_previous")]
    for old, new in (("u_dut.u_soc.u_i2s.u_i2s_core.enable_i", "audio_enable"),
                     ("u_dut.u_soc.u_i2s.u_i2s_core.s_bitmode", "audio_wide")):
        assert observer.count(old) == 1
        observer = observer.replace(old, new)
    (tmp_path / "audio_observer.svh").write_text(observer)
    run_rtl(tmp_path, simulator, "tiny_p9_audio_observer_tb", [], defines=[f"-I{tmp_path}"])
    launch = [str(tmp_path / "sim")] if simulator == "verilator" else ["vvp", str(tmp_path / "sim")]
    for extra in (["+tiny_p9_recovery"], ["+corrupt"], ["+tiny_p9_recovery", "+corrupt"]):
        result = subprocess.run([*launch, *extra], capture_output=True, text=True, timeout=30)
        log = result.stdout + result.stderr
        (tmp_path / ("-".join(flag[1:] for flag in extra) + ".log")).write_text(log)
        if "+corrupt" in extra:
            assert "I2S wire ordering/data" in log and DEFAULT_FAILURE.search(log), log
        else:
            assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
            assert "SIM_TEST_PASS audio observer sessions=2" in log


def test_p9_psram_pin_is_configured_before_initialization() -> None:
    source = (ROOT / "app/apps/ci_smoke/tiny_r2_p9.c").read_text()
    startup = (ROOT / "app/apps/ci_smoke/p9_startup.h").read_text()
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    routes = {item["pin"]: item for item in topology["gpio_alt_functions"]}
    pin_setup = "rs_p9_psram_pin_ready(rs_gpio_configure)"
    psram_init = "rs_xpi_psram_initialize"
    assert pin_setup in source
    assert source.index(pin_setup) < source.index(psram_init)
    assert ".mode = RS_GPIO_MODE_ALT0" in startup
    assert routes[29]["alt0"]["do"] == "xpi.nss_o[1]"
    assert routes[29]["alt0"]["oe"] == "1'b1"


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("backend", ["controlled", "xpi"])
def test_p9_dvp_dma_drain(tmp_path: Path, simulator: str, backend: str) -> None:
    # Use the production instance's parameters, including its admission mask.
    # A test-only mask would hide a disconnected DVP request in the product.
    top = (TINY / "top/retrosoc_tiny.sv").read_text()
    parameters = re.findall(r"apb4_dma\s*#\((.*?)\)\s*u_dma\s*\(", top, re.S)
    assert len(parameters) == 1
    (tmp_path / "tiny_p9_dma_parameters.svh").write_text(parameters[0])
    generate_memory_map(TINY / "address_map/memory_map.json", tmp_path / "map", "YES", 128)
    generate_bindings(read_topology(TINY / "integration/soc_topology.json",
                                   TINY / "address_map/memory_map.json"), tmp_path / "bindings")
    bindings = (tmp_path / "bindings/rtl/tiny_apb_interfaces.svh").read_text()
    reset_binding = re.findall(r"assign s_reset_ready\[14\] = [^;]+;", bindings)
    assert len(reset_binding) == 1
    boot_binding = re.findall(r"assign s_boot_release_d\s*=[^;]+;", top)
    assert len(boot_binding) == 1
    (tmp_path / "tiny_p9_reset_binding.svh").write_text(reset_binding[0] + "\n" + boot_binding[0] + "\n")
    xpi_sources = [COMMON / "interface/axi4_addr_gen.sv",
                   *[ROOT / "rtl/ip/storage" / name for name in (
                       "xpi_if.sv", "xpi_reg.sv", "xpi_mm.sv", "xpi_indirect.sv",
                       "xpi_clkgen.sv", "xpi_core.sv", "apb4_xpi.sv")],
                   ROOT / "rtl/model/ESP_PSRAM64H.sv"] if backend == "xpi" else []
    fixture = "tiny_p9_xpi_tb" if backend == "xpi" else "tiny_r2_p9_dma_tb"
    log = run_rtl(tmp_path, simulator, fixture, [
        *xpi_sources,
        *[COMMON / path for path in (
            "interface/axi4_stream_if.sv", "utils/fifo.sv", "utils/spill_register.sv",
            "utils/edge_det.sv", "stream/round_robin_arbiter.sv", "cdc/async_reqack.sv",
            "cdc/cdc_fifo.sv", "cdc/cdc_warm_flush.sv")],
        ROOT / "rtl/tech/tc_clk.sv",
        TINY / "top/tiny_peripheral_control.sv",
        *[ROOT / "rtl/ip/multimedia" / name for name in (
            "dvp_core.sv", "dvp_reg.sv", "axi4s_dvp.sv")],
        *[ROOT / "rtl/ip/peripheral" / name for name in (
            "dma_req_if.sv", "dma_axi4_master.sv", "dma_reg.sv", "dma_core.sv", "apb4_dma.sv")],
    ], defines=["-DPDK_BEHAV", "-DRETROSOC_SOC__TINY", f"-I{ROOT / 'rtl/ip/storage'}",
                f"-I{tmp_path}", f"-I{tmp_path / 'map/rtl'}",
                f"-I{ROOT / 'rtl/ip/peripheral'}", f"-I{ROOT / 'rtl/ip/multimedia'}"],
        packages=[ROOT / "rtl/ip/peripheral/dma_pkg.sv", ROOT / "rtl/ip/storage/xpi_pkg.sv"])
    assert "SIM_TEST_PASS Tiny P9 focused DVP DMA" in log
    if backend == "xpi":
        assert "P9_XPI_READBACK bytes=256 guards=2" in log
        launch = [str(tmp_path / "sim")] if simulator == "verilator" else ["vvp", str(tmp_path / "sim")]
        result = subprocess.run([*launch, "+xpi_protection"], cwd=ROOT, capture_output=True,
                                text=True, timeout=30)
        content = result.stdout + result.stderr
        (tmp_path / "xpi-protection.log").write_text(content)
        assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
        assert "SIM_TEST_PASS Tiny P9 XPI rejection diagnostics guards recovery" in content
        return
    # Reuse the compiled executable for the delayed SLVERR case.
    launch = [str(tmp_path / "sim")] if simulator == "verilator" else ["vvp", str(tmp_path / "sim")]
    result = subprocess.run([*launch, "+write_error"], cwd=ROOT, capture_output=True,
                            text=True, timeout=30)
    content = result.stdout + result.stderr
    (tmp_path / "write-error.log").write_text(content)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
    assert "SIM_TEST_PASS Tiny P9 focused DVP DMA late response error" in content
    result = subprocess.run([*launch, "+lifecycle"], cwd=ROOT, capture_output=True,
                            text=True, timeout=30)
    content = result.stdout + result.stderr
    (tmp_path / "lifecycle.log").write_text(content)
    assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
    assert "SIM_TEST_PASS Tiny P9 clear recovery stopped-low/high" in content
    for scenario in ("row_geometry", "control_pending", "error_pair", "native_reset", "rearm", "abort_order",
                     "abort_active", "abort_applied", "fault_matrix", "crop_repeat", "service_budget"):
        extra = ["+pixel_half_ns=500"] if scenario == "service_budget" else []
        result = subprocess.run([*launch, f"+{scenario}", *extra], cwd=ROOT, capture_output=True,
                                text=True, timeout=30)
        content = result.stdout + result.stderr
        (tmp_path / f"{scenario}.log").write_text(content)
        assert result.returncode == 0 and not DEFAULT_FAILURE.search(content), content
        assert "SIM_TEST_PASS Tiny P9" in content
