"""Tests for the canonical Mini SoC pin-map generator."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "rtl/mini/pin_map/generate_pin_map.py"
PIN_MAP = ROOT / "rtl/mini/pin_map/pin_map.json"
FPGA_TOP = ROOT / "fpga/mini/retrosoc_top.sv"
FPGA_XDC = ROOT / "fpga/mini/starrysky_v2.xdc"


def generate(output_dir: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(PIN_MAP),
            "--output-dir",
            str(output_dir),
        ],
        check=True,
    )


def validate(map_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(GENERATOR), "--map", str(map_path), "--check"],
        text=True,
        capture_output=True,
    )


def test_pin_map_generates_asic_and_platform_bindings(tmp_path: Path) -> None:
    generate(tmp_path)

    ports = (tmp_path / "rtl/retrosoc_asic_ports.svh").read_text(encoding="utf-8")
    pads = (tmp_path / "rtl/retrosoc_asic_pad_bindings.svh").read_text(encoding="utf-8")
    fpga = (tmp_path / "rtl/retrosoc_asic_fpga_mini_bindings.svh").read_text(
        encoding="utf-8"
    )
    testbench = (tmp_path / "rtl/retrosoc_asic_tb_bindings.svh").read_text(
        encoding="utf-8"
    )

    assert "inout extclk_i_pad," in ports
    assert "input xi_i_pad," in ports
    assert "inout sdram_dq15_io_pad" in ports
    assert "u_gpio_31_io_pad" in pads
    assert "u_sdram_dq15_io_pad" in pads
    assert ".gpio_30_io_pad(gpio_io30)" in fpga
    assert ".gpio_15_io_pad()" in fpga
    assert ".gpio_24_io_pad(s_psram_dat1)" in testbench
    assert testbench.count(".gpio_24_io_pad(") == 1
    assert "user_gpio_" not in ports
    assert "user_gpio_" not in pads
    assert "user_gpio_" not in testbench


def test_pin_map_rejects_duplicate_pads(tmp_path: Path) -> None:
    document = json.loads(PIN_MAP.read_text(encoding="utf-8"))
    document["pads"][0]["ports"].append(
        {"name": "extclk_i_pad", "signal": "s_duplicate_clock"}
    )
    invalid_map = tmp_path / "duplicate.json"
    invalid_map.write_text(json.dumps(document), encoding="utf-8")

    result = validate(invalid_map)

    assert result.returncode != 0
    assert "pad names must be unique" in result.stderr


def test_pin_map_rejects_non_object_port_entry(tmp_path: Path) -> None:
    document = json.loads(PIN_MAP.read_text(encoding="utf-8"))
    document["pads"][0]["ports"].append("extclk_i_pad")
    invalid_map = tmp_path / "invalid-port.json"
    invalid_map.write_text(json.dumps(document), encoding="utf-8")

    result = validate(invalid_map)

    assert result.returncode != 0
    assert "ports entries must be objects" in result.stderr


def test_pin_map_rejects_unknown_profile_pad(tmp_path: Path) -> None:
    document = json.loads(PIN_MAP.read_text(encoding="utf-8"))
    document["profiles"]["tb"]["bindings"]["unknown_pad"] = "s_unknown"
    invalid_map = tmp_path / "unknown.json"
    invalid_map.write_text(json.dumps(document), encoding="utf-8")

    result = validate(invalid_map)

    assert result.returncode != 0
    assert "unknown pad" in result.stderr


def test_fpga_constraints_reference_declared_top_ports() -> None:
    top_ports = set(re.findall(r"^\s*(?:input|output|inout)\s+([A-Za-z_][A-Za-z0-9_]*)", FPGA_TOP.read_text(encoding="utf-8"), re.MULTILINE))
    xdc_ports = set(re.findall(r"\[get_ports\s+([A-Za-z_][A-Za-z0-9_]*)\]", FPGA_XDC.read_text(encoding="utf-8")))

    assert xdc_ports
    assert xdc_ports <= top_ports


def test_apb4_interface_bridge(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return
    source_list = tmp_path / "apb4_if_bridge.fl"
    source_list.write_text(
        "\n".join(
            [
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_pure_if.sv"),
                str(ROOT / "rtl/mini/top/apb4_if_bridge.sv"),
                str(ROOT / "tests/rtl/apb4_if_bridge_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apb4_if_bridge_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "apb4_if_bridge_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apb4_if_bridge_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "apb4 interface bridge test passed" in result.stdout
