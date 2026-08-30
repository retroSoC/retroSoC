"""SDRAM controller data-integrity regression."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _write_memory_map(generated: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
        ],
        check=True,
    )


def _source_list_text(generated: Path, *, timing_model: bool) -> str:
    lines = [
        "+define+SV_ASSRT_DISABLE",
        f"+incdir+{generated / 'rtl'}",
        f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
        f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
        f"+incdir+{ROOT / 'rtl/ip/memory'}",
    ]
    if timing_model:
        lines.append("+define+SDRAM_TIMING_MODEL")
        lines.append(f"+incdir+{ROOT / 'rtl/managed/third_party/model/sdram'}")
    lines.extend(
        [
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_addr_gen.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv"),
            str(ROOT / "rtl/ip/memory/sdram_pkg.sv"),
            str(ROOT / "rtl/ip/memory/axi4_sdram.sv"),
            str(ROOT / "rtl/ip/memory/sdram_clkgen.sv"),
            str(ROOT / "rtl/ip/memory/sdram_reg.sv"),
            str(ROOT / "rtl/ip/memory/sdram_axi4.sv"),
            str(ROOT / "rtl/ip/memory/sdram_core.sv"),
        ]
    )
    if not timing_model:
        lines.append(str(ROOT / "rtl/mini/dv/verilator/rtl/sdram_verilator_model.sv"))
    lines.append(str(ROOT / "tests/rtl/sdram_data_tb.sv"))
    lines.append("")
    return "\n".join(lines)


def test_sdram_controller_preserves_full_and_masked_writes(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    generated = tmp_path / "generated"
    _write_memory_map(generated)
    source_list = tmp_path / "sdram_data.fl"
    source_list.write_text(_source_list_text(generated, timing_model=False), encoding="utf-8")
    converted = tmp_path / "sdram_data_tb.v"
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
    simulation = tmp_path / "sdram_data_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "sdram_data_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sdram data integrity test passed" in result.stdout


def test_sdram_controller_preserves_data_with_micron_timing_model(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    generated = tmp_path / "generated"
    _write_memory_map(generated)
    source_list = tmp_path / "sdram_timing.fl"
    source_list.write_text(_source_list_text(generated, timing_model=True), encoding="utf-8")
    converted = tmp_path / "sdram_timing_tb.v"
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
    simulation = tmp_path / "sdram_timing_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "sdram_data_tb",
            "-I",
            str(ROOT / "rtl/managed/third_party/model/sdram"),
            "-o",
            str(simulation),
            str(converted),
            str(ROOT / "rtl/managed/third_party/model/sdram/sdr.v"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "sdram data integrity test passed" in result.stdout


def test_sdram_handwritten_register_offsets_match_hal() -> None:
    import re

    rtl_text = (ROOT / "rtl/ip/memory/sdram_define.svh").read_text(encoding="utf-8")
    hal_text = (ROOT / "crt/src/hal/sdram.c").read_text(encoding="utf-8")
    rtl_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"`define\s+APB4_SDRAM__([A-Z0-9_]+)\s+12'h([0-9A-Fa-f]+)",
            rtl_text,
        )
    }
    hal_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+RS_SDRAM_([A-Z0-9_]+)_OFFSET\s+UINT32_C\(0x([0-9A-Fa-f]+)\)",
            hal_text,
        )
    }

    assert hal_offsets
    for name, value in hal_offsets.items():
        assert rtl_offsets[name] == value


def test_sdram_register_macros_live_in_hal_not_soc() -> None:
    soc_text = (ROOT / "crt/include/retrosoc/core/soc.h").read_text(encoding="utf-8")
    header_text = (ROOT / "crt/include/retrosoc/hal/sdram.h").read_text(encoding="utf-8")

    assert "reg_sdram_" not in soc_text
    assert "reg_sdram_" not in header_text


def test_ci_software_covers_sdram_mapped_window() -> None:
    smoke = (ROOT / "app/apps/ci_smoke/main.c").read_text(encoding="utf-8")
    hello = (ROOT / "app/asm/hello.s").read_text(encoding="utf-8")

    assert "rs_ci_smoke_sdram_access" in smoke
    assert "RS_SOC_SDRAM_BASE" in smoke
    assert "RS_SOC_SDRAM_END - RS_CI_SMOKE_SDRAM_SPAN" in smoke
    assert "RS_SOC_SDRAM_BASE" in hello
    assert "WAIT_SDRAM_READY" in hello
