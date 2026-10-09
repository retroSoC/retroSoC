"""Directed RTL tests for the GPIO register and pad-control contract."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_gpio_pad_capability_matrix(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    cases = (
        ("gf180", ("PDK_GF180",), (1, 1, 1)),
        ("ics55", ("PDK_ICS55",), (1, 1, 1)),
        ("sky130", ("PDK_SKY130",), (1, 0, 0)),
        ("ihp130", ("PDK_IHP130",), (0, 0, 0)),
        ("s110", ("PDK_S110",), (0, 0, 0)),
        ("gf180_behav", ("PDK_GF180", "PDK_BEHAV"), (0, 0, 0)),
    )
    package = ROOT / "rtl/ip/peripheral/gpio_pad_caps_pkg.sv"
    testbench = ROOT / "tests/rtl/gpio_pad_caps_tb.sv"
    for name, defines, expected in cases:
        simulation = tmp_path / f"gpio_pad_caps_{name}"
        command = [iverilog, "-g2012", "-s", "gpio_pad_caps_tb"]
        command.extend(f"-D{define}" for define in defines)
        command.extend(
            (
                f"-Pgpio_pad_caps_tb.ExpectedInputCmos={expected[0]}",
                f"-Pgpio_pad_caps_tb.ExpectedPullUp={expected[1]}",
                f"-Pgpio_pad_caps_tb.ExpectedPullDown={expected[2]}",
                str(package),
                str(testbench),
                "-o",
                str(simulation),
            )
        )
        subprocess.run(command, check=True)
        result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
        assert "GPIO pad capability matrix test passed" in result.stdout


def test_gpio_register_pad_interrupt_and_filter_contract(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return

    peripheral = ROOT / "rtl/ip/peripheral"
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "gpio.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                "+define+PDK_GF180",
                f"+incdir+{peripheral}",
                f"+incdir+{common}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "clkrst/counter.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "utils/edge_det.sv"),
                str(peripheral / "gpio_if.sv"),
                str(peripheral / "user_gpio_if.sv"),
                str(peripheral / "gpio_core.sv"),
                str(peripheral / "gpio_reg.sv"),
                str(peripheral / "apb4_gpio.sv"),
                str(ROOT / "rtl/tech/gf180_io_sim_cells.v"),
                str(ROOT / "rtl/tech/tc_io.sv"),
                str(ROOT / "tests/rtl/gpio_tb.sv"),
                str(ROOT / "tests/rtl/gpio_unsupported_tb.sv"),
                str(ROOT / "tests/rtl/gpio_pad_integration_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "gpio_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    for top, marker in (
        ("gpio_tb", "GPIO directed test passed"),
        ("gpio_unsupported_tb", "GPIO unsupported capability test passed"),
        ("gpio_pad_integration_tb", "GPIO controller-to-pad integration test passed"),
    ):
        simulation = tmp_path / top
        subprocess.run(
            [iverilog, "-g2012", "-s", top, "-o", str(simulation), str(converted)],
            check=True,
        )
        result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
        assert marker in result.stdout


def test_gpio_pad_wrapper_only_connects_supported_pull_controls() -> None:
    source = (ROOT / "rtl/tech/tc_io.sv").read_text(encoding="utf-8")
    full_pad = source.split("module tc_io_tri_full_pad", 1)[1].split("endmodule", 1)[0]

    gf180 = full_pad.split("`elsif PDK_GF180", 1)[1].split("`elsif PDK_IHP130", 1)[0]
    ics55 = full_pad.split("`elsif PDK_ICS55", 1)[1].split("`endif", 1)[0]
    assert ".pu    (pu)" in gf180 and ".pd    (pd)" in gf180
    assert ".PU (pu)" in ics55 and ".PD (pd)" in ics55

    for marker, end_marker in (
        ("`ifdef PDK_BEHAV", "`elsif PDK_SKY130"),
        ("`elsif PDK_SKY130", "`elsif PDK_GF180"),
        ("`elsif PDK_IHP130", "`elsif PDK_S110"),
        ("`elsif PDK_S110", "`elsif PDK_ICS55"),
    ):
        branch = full_pad.split(marker, 1)[1].split(end_marker, 1)[0]
        assert ".PU" not in branch and ".PD" not in branch
