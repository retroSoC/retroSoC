"""Directed verification for the APU-P1 APB4 register shell."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOPOLOGY = ROOT / "rtl/mini/integration/soc_topology.json"
TOPOLOGY_GENERATOR = ROOT / "rtl/mini/integration/generate_soc_topology.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"


def test_apu_p1_apb_register_shell(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_reg.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(multimedia / "apu_reg.sv"),
                str(multimedia / "apb4_apu.sv"),
                str(ROOT / "tests/rtl/apu_reg_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_reg_tb.v"
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
    simulation = tmp_path / "apu_reg_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_reg_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "APU-P1 complete APB register matrix passed" in result.stdout


def test_apu_p1_integrated_irq_ownership_topology(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    peripheral = ROOT / "rtl/ip/peripheral"
    topology_output = tmp_path / "topology"
    subprocess.run(
        [
            sys.executable,
            str(TOPOLOGY_GENERATOR),
            "--map",
            str(TOPOLOGY),
            "--memory-map",
            str(MEMORY_MAP),
            "--output-dir",
            str(topology_output),
        ],
        check=True,
    )

    source_list = tmp_path / "apu_irq_topology.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{topology_output / 'rtl'}",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                str(common / "interface/apb4_if.sv"),
                str(common / "utils/register.sv"),
                str(multimedia / "apu_reg.sv"),
                str(multimedia / "apb4_apu.sv"),
                str(ROOT / "rtl/mini/top/resource_controller.sv"),
                str(peripheral / "apb4_plic.sv"),
                str(ROOT / "tests/rtl/apu_irq_topology_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_irq_topology_tb.v"
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
    simulation = tmp_path / "apu_irq_topology_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_irq_topology_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "APU-P1 integrated IRQ ownership topology passed" in result.stdout
