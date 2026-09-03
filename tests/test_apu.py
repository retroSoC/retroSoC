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
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(multimedia / "apu_stream_router.sv"),
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
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(multimedia / "apu_stream_router.sv"),
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


def test_apu_p2_stream_router(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_stream_router.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_stream_router.sv"),
                str(ROOT / "tests/rtl/apu_stream_router_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_stream_router_tb.v"
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
    simulation = tmp_path / "apu_stream_router_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_stream_router_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 stream router tests passed" in result.stdout


def test_apu_p2_private_dma(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_dma.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_dma.sv"),
                str(ROOT / "tests/rtl/apu_dma_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_dma_tb.v"
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
    simulation = tmp_path / "apu_dma_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_dma_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 DMA tests passed" in result.stdout


def test_apu_p2_ring_scheduler_backend(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_ring_scheduler.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
                str(common / "interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_ring_scheduler.sv"),
                str(ROOT / "tests/rtl/apu_p2_backend.sv"),
                str(ROOT / "tests/rtl/apu_ring_scheduler_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_ring_scheduler_tb.v"
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
    simulation = tmp_path / "apu_ring_scheduler_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_ring_scheduler_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 ring scheduler/backend tests passed" in result.stdout


def test_apu_p2_integrated_dma_ring_backend(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p2_integration.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(common / "utils/xchecker.sv"),
                str(common / "utils/spill_register.sv"),
                str(common / "utils/bin2gray.sv"),
                str(common / "utils/gray2bin.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "cdc/cdc_rst_ctrlr.sv"),
                str(common / "cdc/cdc_2phase.sv"),
                str(common / "clkrst/rst_sync.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(ROOT / "rtl/mini/top/soc_common_cdc.sv"),
                str(ROOT / "rtl/mini/top/axi4_async_bridge.sv"),
                str(ROOT / "rtl/mini/top/axi4_target_guard.sv"),
                str(ROOT / "rtl/mini/top/hp_axi4_mux3.sv"),
                str(ROOT / "tests/rtl/apu_p2_transport_backend.sv"),
                str(ROOT / "tests/rtl/apu_p2_integration_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p2_integration_tb.v"
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
    simulation = tmp_path / "apu_p2_integration_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_p2_integration_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 integrated DMA/ring/backend tests passed" in result.stdout


def test_apu_p2_gateway_a_round_robin_fairness(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "gateway_a_rr.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/mini/top/hp_axi4_mux3.sv"),
                str(ROOT / "tests/rtl/hp_axi4_mux3_rr_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "hp_axi4_mux3_rr_tb.v"
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
    simulation = tmp_path / "hp_axi4_mux3_rr_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "hp_axi4_mux3_rr_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 Gateway A round-robin fairness passed with read/write/mixed retention" in result.stdout
