"""Focused standalone USB2 RTL regressions."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/test-usb2"
CONVERTER = ROOT / "rtl/mini/script/convt_sv2v.py"


def test_usb2_drain_stream_has_registered_ready_cut() -> None:
    source = (ROOT / "rtl/ip/usb/apb4_usb2.sv").read_text(encoding="utf-8")

    assert "u_drain_stream_spill" in source
    assert ".ready_o(s_drain_stream_ready_ulpi)" in source
    assert ".src_ready_o(s_drain_fifo_ready_ulpi)" in source
    assert source.count(".BUFFER_DEPTH(8)") == 2
    assert ".BUFFER_DEPTH(32)" not in source


def test_usb2_packet_store_registers_ecc_read_data() -> None:
    source = (ROOT / "rtl/ip/usb/usb2_packet_store.sv").read_text(encoding="utf-8")

    assert "u_read_word_dffer" in source
    assert ".en_i   (s_ram_read_valid)" in source
    assert "assign drain_data_o         = s_read_word_q;" in source
    assert "assign tx_data_o            = s_read_word_q" in source


def _run_iverilog(name: str, top: str, sources: list[str], marker: str) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    BUILD.mkdir(parents=True, exist_ok=True)
    filelist = BUILD / f"{name}.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/utils'}",
                f"+incdir+{ROOT / 'rtl/ip/usb'}",
                *(str(ROOT / source) for source in sources),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    converted = BUILD / f"{name}.v"
    simulation = BUILD / f"{name}.vvp"
    subprocess.run(
        ["python3", str(CONVERTER), "-f", str(filelist), "--output", str(converted)],
        check=True,
    )
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-s",
            top,
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation)], check=True, capture_output=True, text=True
    )
    assert marker in result.stdout


def test_usb2_pid_and_crc() -> None:
    _run_iverilog(
        "pkg",
        "usb2_pkg_tb",
        ["rtl/ip/usb/usb2_pkg.sv", "tests/rtl/usb2_pkg_tb.sv"],
        "USB2 PID and CRC vectors passed",
    )


def test_usb2_descriptor_validation() -> None:
    _run_iverilog(
        "descriptor",
        "usb2_descriptor_tb",
        [
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/usb/usb2_dma_descriptor.sv",
            "tests/rtl/usb2_descriptor_tb.sv",
        ],
        "USB2 descriptor validation passed",
    )


def test_usb2_packet_ram_ecc() -> None:
    _run_iverilog(
        "packet-ram",
        "usb2_packet_ram_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/managed/clusterip/common/rtl/base/ecc_secded.sv",
            "rtl/tech/tc_usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_packet_ram.sv",
            "tests/rtl/usb2_packet_ram_tb.sv",
        ],
        "USB2 packet RAM ECC test passed",
    )


def test_usb2_sie_packets() -> None:
    _run_iverilog(
        "sie",
        "usb2_sie_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/usb/usb2_sie_rx.sv",
            "rtl/ip/usb/usb2_sie_tx.sv",
            "tests/rtl/usb2_sie_tb.sv",
        ],
        "USB2 SIE packet encode/decode passed",
    )


def test_usb2_register_contract() -> None:
    _run_iverilog(
        "register",
        "usb2_reg_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/ip/usb/usb2_define.svh",
            "rtl/ip/usb/usb2_reg.sv",
            "tests/rtl/usb2_reg_tb.sv",
        ],
        "USB2 APB register contract passed",
    )


def test_usb2_descriptor_dma() -> None:
    _run_iverilog(
        "dma",
        "usb2_dma_tb",
        [
            "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/peripheral/dma_axi4_master.sv",
            "rtl/ip/usb/usb2_dma_descriptor.sv",
            "rtl/ip/usb/usb2_dma.sv",
            "tests/rtl/sdio_axi_memory_responder.sv",
            "tests/rtl/usb2_dma_tb.sv",
        ],
        "USB2 descriptor DMA test passed",
    )


def test_usb2_packet_store_paths() -> None:
    _run_iverilog(
        "packet-store",
        "usb2_packet_store_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/managed/clusterip/common/rtl/base/ecc_secded.sv",
            "rtl/tech/tc_usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_packet_store.sv",
            "tests/rtl/usb2_packet_store_tb.sv",
        ],
        "USB2 packet store paths passed",
    )


def test_usb2_transaction_engine_host_out() -> None:
    _run_iverilog(
        "transaction-engine",
        "usb2_transaction_engine_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/managed/clusterip/common/rtl/base/ecc_secded.sv",
            "rtl/tech/tc_usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/usb/usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_packet_store.sv",
            "rtl/ip/usb/usb2_transaction_engine.sv",
            "tests/rtl/usb2_transaction_engine_tb.sv",
        ],
        "USB2 transaction engine host OUT passed",
    )


def test_usb2_link_domain_smoke() -> None:
    _run_iverilog(
        "link-domain",
        "usb2_link_domain_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/managed/clusterip/common/rtl/base/ecc_secded.sv",
            "rtl/tech/tc_usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/usb/usb2_ulpi_if.sv",
            "rtl/ip/usb/usb2_packet_ram.sv",
            "rtl/ip/usb/usb2_packet_store.sv",
            "rtl/ip/usb/usb2_ulpi_link.sv",
            "rtl/ip/usb/usb2_sie_rx.sv",
            "rtl/ip/usb/usb2_sie_tx.sv",
            "rtl/ip/usb/usb2_transaction_engine.sv",
            "rtl/ip/usb/usb2_link_domain.sv",
            "tests/rtl/usb2_link_domain_tb.sv",
        ],
        "USB2 link domain smoke passed",
    )


def test_usb2_scheduler_queue_and_interval() -> None:
    _run_iverilog(
        "scheduler",
        "usb2_scheduler_tb",
        [
            "rtl/managed/clusterip/common/rtl/utils/register.sv",
            "rtl/ip/usb/usb2_pkg.sv",
            "rtl/ip/usb/usb2_scheduler.sv",
            "tests/rtl/usb2_scheduler_tb.sv",
        ],
        "USB2 scheduler queue and interval passed",
    )
