"""RTL test for the direct RIB-to-APB bridge."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_rib2apb_preserves_apb_and_rib_handshakes(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    sv2v = shutil.which("sv2v")
    vvp = shutil.which("vvp")
    if iverilog is None or sv2v is None or vvp is None:
        return

    memory_map = tmp_path / "memory_map"
    topology = tmp_path / "soc_topology"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(memory_map),
            "--have-sram-if",
            "NO",
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/integration/generate_soc_topology.py"),
            "--map",
            str(ROOT / "rtl/mini/integration/soc_topology.json"),
            "--memory-map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(topology),
        ],
        check=True,
    )

    source_list = tmp_path / "rib2apb.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{memory_map / 'rtl'}",
                f"+incdir+{topology / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_pure_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/mini/top/rib_if.sv"),
                str(ROOT / "rtl/mini/top/rib2apb.sv"),
                str(ROOT / "tests/rtl/rib2apb_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "rib2apb_tb.v"
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
    simulation = tmp_path / "rib2apb_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "rib2apb_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)

    assert "RIB2APB direct bridge test passed" in result.stdout
