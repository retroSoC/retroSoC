"""Tests for the canonical Mini SoC address-map generator."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "rtl/mini/address_map/generate_memory_map.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"


def generate(output_dir: Path, *, ip: str = "NONE", sram: str = "NO") -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(MEMORY_MAP),
            "--output-dir",
            str(output_dir),
            "--have-sram-if",
            sram,
            "--ip",
            ip,
        ],
        check=True,
    )


def test_generated_artifacts_share_the_capacity_baseline(tmp_path: Path) -> None:
    generate(tmp_path, sram="YES")

    rtl = (tmp_path / "rtl/mmap_define.svh").read_text(encoding="utf-8")
    header = (tmp_path / "include/retrosoc/generated/memory_map.h").read_text(encoding="utf-8")
    linker = (tmp_path / "linker/memory_regions.ld").read_text(encoding="utf-8")

    assert "`define SOC_ADDR_PSRAM_END  32'h407FFFFF" in rtl
    assert "`define SOC_ADDR_XPI_END  32'h5FFFFFFF" in rtl
    assert "`define CPU_RESET_ADDR `SOC_CPU_RESET_ADDR" in rtl
    assert "`define SOC_ADDR_IS_RESERVED(addr)" in rtl
    assert "RS_SOC_PSRAM_SIZE UINT32_C(0x00800000)" in header
    assert "RS_SOC_SDRAM_SIZE UINT32_C(0x02000000)" in header
    assert "RS_SOC_SPISD_SIZE UINT32_C(0x40000000)" in header
    assert "RS_SOC_NMI_SDIO_BASE" not in header
    assert "RS_SOC_OPIPSRAM_BASE" not in header
    assert "RS_SOC_HAS_SRAM 1U" in header
    assert "PSRAM (wxa!ri) : ORIGIN = 0x40000000, LENGTH = 0x00800000" in linker


def test_user_ip_is_emitted_only_for_the_matching_profile(tmp_path: Path) -> None:
    none_output = tmp_path / "none"
    mdd_output = tmp_path / "mdd"
    generate(none_output)
    generate(mdd_output, ip="MDD")

    none_rtl = (none_output / "rtl/mmap_define.svh").read_text(encoding="utf-8")
    mdd_header = (mdd_output / "include/retrosoc/generated/memory_map.h").read_text(
        encoding="utf-8"
    )

    assert "SOC_ADDR_APB_USER_IP_BASE" not in none_rtl
    assert "RS_SOC_APB_USER_IP_BASE" in mdd_header


def test_map_validation_rejects_overlaps(tmp_path: Path) -> None:
    document = json.loads(MEMORY_MAP.read_text(encoding="utf-8"))
    document["regions"][1]["base"] = document["regions"][0]["base"]
    invalid_map = tmp_path / "overlap.json"
    invalid_map.write_text(json.dumps(document), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(GENERATOR), "--map", str(invalid_map), "--check"],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "address-map overlap" in result.stderr


def test_bus_fault_responder_handles_reserved_and_unmapped_addresses(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    generate(tmp_path)
    simulation = tmp_path / "bus_fault_tb"
    source_list = tmp_path / "bus_fault.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/nmi_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/native/interconnect/nmi_regslice.sv"),
                str(ROOT / "rtl/mini/top/bus.sv"),
                str(ROOT / "tests/rtl/bus_fault_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "bus_fault_tb.v"
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
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "bus_fault_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "bus fault responder test passed" in result.stdout


def test_sysctrl_fault_registers_record_and_clear_pending(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    generate(tmp_path)
    source_list = tmp_path / "sysctrl_fault.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{tmp_path / 'rtl'}",
                f"+incdir+{ROOT / 'rtl/mini/top'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/nmi_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/native/peripheral/sysctrl.sv"),
                str(ROOT / "tests/rtl/sysctrl_fault_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "sysctrl_fault_tb.v"
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
    simulation = tmp_path / "sysctrl_fault_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "sysctrl_fault_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sysctrl fault registers test passed" in result.stdout


def test_sysctrl_does_not_expose_unused_i2c_or_qspi_select_registers() -> None:
    rtl = (ROOT / "rtl/ip/native/peripheral/sysctrl.sv").read_text(encoding="utf-8")
    header = (ROOT / "crt/include/retrosoc/core/soc.h").read_text(encoding="utf-8")

    for symbol in (
        "NATV_SYSCTRL_I2CSEL",
        "NATV_SYSCTRL_QSPISEL",
        "i2c_sel_o",
        "qspi_sel_o",
        "s_sysctrl_i2csel",
        "s_sysctrl_qspisel",
    ):
        assert symbol not in rtl
    assert "reg_sysctrl_i2csel" not in header
    assert "reg_sysctrl_qspicsel" not in header
