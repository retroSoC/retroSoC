"""Exercise actual Tiny board drivers/routes through the ICS55 pad wrapper."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

import pytest

from scripts.check_simulation import DEFAULT_FAILURE
from scripts.generate_tiny import generate_bindings, read_topology
from scripts.rtl.generate_pin_map import generate as generate_pads

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def one(pattern: str, source: str) -> str:
    matches = re.findall(pattern, source, re.M | re.S)
    assert len(matches) == 1, (pattern, len(matches))
    return matches[0]


def prepare_wiring(directory: Path) -> None:
    topology = read_topology(TINY / "integration/soc_topology.json",
                             TINY / "address_map/memory_map.json")
    generate_bindings(topology, directory / "bindings", pdk="ICS55", have_pll=True)
    generate_pads(TINY / "pin_map/pin_map.json", directory / "pads", read_while_driving=True)
    board = (TINY / "dv/retrosoc_tiny_tb.sv").read_text()
    p6 = (TINY / "dv/tiny_p6_devices.svh").read_text()
    dvp = (ROOT / "rtl/ip/multimedia/axi4s_dvp.sv").read_text()
    paths = (TINY / "dv/retrosoc_tiny_tb.sv", TINY / "dv/tiny_p6_devices.svh",
             TINY / "integration/soc_topology.json", TINY / "pin_map/pin_map.json",
             ROOT / "rtl/ip/multimedia/axi4s_dvp.sv")
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in paths}
    (directory / "extracted-source-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (directory / "pad_dvp_interface.svh").write_text(
        one(r"(^interface dvp_if\b.*?^endinterface)", dvp) + "\n")
    (directory / "pad_audio_startup.svh").write_text(
        one(r"(^logic\s+s_p6_audio_reference\s*=.*?^end\b)", p6) + "\n")
    audio = [one(r"(^\s*logic s_p9_camera_population\s*=[^;]+;)", board)]
    audio += [one(rf"(^assign s_gpio_{pin}\s*=[^;]+;)", p6) for pin in (17, 15)]
    audio.append(one(r"(^always #[^\n]+s_p6_audio_reference[^;]+;)", p6))
    (directory / "pad_audio_drivers.svh").write_text("\n".join(audio) + "\n")
    camera = [one(rf"(^\s*assign s_gpio_{pin}\s*=[^;]+;)", board) for pin in range(12, 23)]
    (directory / "pad_camera_drivers.svh").write_text("\n".join(camera) + "\n")
    generated = directory / "pads/rtl"
    ports = (generated / "retrosoc_asic_ports.svh").read_text()
    binds = (generated / "retrosoc_asic_verilator_bindings.svh").read_text()
    pads = (generated / "retrosoc_asic_pad_bindings.svh").read_text()
    selected_ports = [one(rf"(inout\s+gpio_{pin}_io_pad)\b", ports) for pin in range(12, 23)]
    selected_binds = [one(rf"(\.gpio_{pin}_io_pad\([^\n]+?\))", binds)
                      for pin in range(12, 23)]
    selected_pads = [one(rf"(^\s*tc_io_tri_full_pad[^\n]*u_gpio_{pin}_io_pad[^;]+;)", pads)
                     for pin in range(12, 23)]
    (directory / "pad_ports.svh").write_text(",\n".join(selected_ports) + "\n")
    (directory / "pad_tb_bindings.svh").write_text(",\n".join(selected_binds) + "\n")
    (directory / "pad_instances.svh").write_text("\n".join(selected_pads) + "\n")
    routes = (directory / "bindings/rtl/tiny_gpio.svh").read_text()
    selected_routes = re.findall(r"^assign u_dvp_if\.[^;]+;", routes, re.M)
    assert len(selected_routes) == 11
    (directory / "pad_dvp_routes.svh").write_text("\n".join(selected_routes) + "\n")


@pytest.fixture(scope="module", params=["iverilog", "verilator"])
def pad_simulator(request, tmp_path_factory):
    backend = request.param
    assert shutil.which(backend)
    directory = tmp_path_factory.mktemp(f"p9-pad-{backend}")
    prepare_wiring(directory)
    model = ROOT / ("rtl/tech/ics55_io_sim_cells.sv" if backend == "verilator" else
                    "physical/pdk/icsprout55-pdk/IP/IO/ICsprout_55LLULP1233_IO_251013/verilog/icsIOA_N55_3P3.v")
    sources = [ROOT / "rtl/ip/peripheral/gpio_if.sv",
               ROOT / "tests/rtl/tiny_p9_pad_isolation_tb.sv", ROOT / "rtl/tech/tc_io.sv",
               model, TINY / "dv/tiny_dvp_camera.sv", ROOT / "rtl/ip/multimedia/dvp_core.sv"]
    flags = ["-DPDK_ICS55", "-Dfunctional", *[f"-I{p}" for p in (
        directory, directory / "bindings/rtl", ROOT / "rtl/ip/peripheral",
        ROOT / "rtl/ip/multimedia")]]
    binary = directory / "sim"
    if backend == "iverilog":
        command = [backend, "-g2012", "-s", "tiny_p9_pad_isolation_tb", *flags,
                   *map(str, sources), "-o", str(binary)]
        launch = ["vvp", str(binary)]
    else:
        command = [backend, "--binary", "--timing", "--assert", "--timescale", "1ns/1ps",
                   "-Wno-fatal", "--top-module", "tiny_p9_pad_isolation_tb", *flags,
                   *map(str, sources), "--Mdir", str(directory / "obj"), "-o", str(binary)]
        launch = [str(binary)]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=120,
                            env={**os.environ, "CCACHE_DISABLE": "1"})
    (directory / "compile.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    return launch, directory


@pytest.mark.parametrize("scenario,args", [
    ("audio", []),
    ("sweep", ["+tiny_p9_camera", "+sweep"]),
    ("capture", ["+tiny_p9_camera", "+tiny_p9_small", "+capture"]),
    ("legacy_conflict", ["+tiny_p9_camera", "+sweep", "+legacy_conflict"]),
    ("legacy_clock_capture", ["+tiny_p9_camera", "+tiny_p9_small", "+capture", "+legacy_clock"]),
])
def test_camera_audio_pad_isolation(pad_simulator, scenario, args):
    launch, directory = pad_simulator
    result = subprocess.run([*launch, *args], cwd=directory, capture_output=True,
                            text=True, timeout=60)
    log = result.stdout + result.stderr
    (directory / f"{scenario}.log").write_text(log)
    if scenario in ("legacy_conflict", "legacy_clock_capture"):
        error = ("SIM_TEST_FAIL P9 pad mismatch" if scenario == "legacy_conflict" else
                 "SIM_TEST_FAIL P9 DVP word=0")
        assert error in log and DEFAULT_FAILURE.search(log), log
        assert "SIM_TEST_PASS" not in log, log
    else:
        assert result.returncode == 0 and not DEFAULT_FAILURE.search(log), log
        assert "SIM_TEST_PASS Tiny" in log, log
        if scenario == "capture":
            assert "P9_PAD_FIRST_WORD value=02030001" in log, log
            assert "pad capture words=64" in log, log
