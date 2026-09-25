"""Tiny product isolation, generated ABI and native bus acceptance."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.generate_tiny import generate_bindings, generate_filelists, read_topology
from scripts.rtl.filelist import parse_filelists
from scripts.rtl.generate_memory_map import generate as generate_memory_map

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, result.stdout + result.stderr
    return result


def test_tiny_sources_and_abi_are_independent(tmp_path: Path) -> None:
    output = tmp_path / "generated"
    filelists = tmp_path / "filelists"
    document = read_topology(TINY / "integration/soc_topology.json",
                             TINY / "address_map/memory_map.json")
    generate_bindings(document, output)
    generate_filelists(filelists, output, ["+define+RETROSOC_SOC__TINY"])
    generate_memory_map(TINY / "address_map/memory_map.json", output / "memory_map", "YES", 128)
    resolved = parse_filelists(filelists / name for name in
                              ("commonip.fl", "clusterip.fl", "core_hazard3.fl", "ip.fl", "top.fl"))
    for source in resolved.files:
        assert "/rtl/mini/" not in str(source)
        assert not any(token in source.name.lower() for token in ("rib", "vexii", "radio"))
    rtl = (output / "memory_map/rtl/mmap_define.svh").read_text()
    sdk = (output / "memory_map/include/retrosoc/generated/memory_map.h").read_text()
    assert "RIB" not in rtl
    assert "SOC_ADDR_SRAM_END  32'h3001FFFF" in rtl
    assert "RS_SOC_SRAM_SIZE UINT32_C(0x00020000)" in sdk
    assert "RS_SOC_PSRAM_BASE" not in sdk
    irq = (output / "include/retrosoc/generated/irq_metadata.h").read_text()
    assert "RS_SOC_EXTERNAL_IRQ_COUNT UINT32_C(30)" in irq
    assert "RS_SOC_EXT_IRQ_UART1 UINT32_C(24)" in irq
    assert "RS_SOC_EXT_IRQ_DMA UINT32_C(18)" in irq
    assert "RS_SOC_EXT_IRQ_NPU" not in irq
    # A consumer of public SDK headers must see Tiny capabilities without
    # reconstructing the firmware build's private preprocessor command line.
    if shutil.which("cc"):
        probe = tmp_path / "consumer.c"
        probe.write_text('#include <retrosoc/hal/dma.h>\n'
                         '_Static_assert(RS_DMA_CHANNEL_COUNT == 4, "wrong product");\n')
        run(["cc", "-std=c11", "-Werror", "-I" + str(ROOT / "crt/include"),
             "-I" + str(output / "memory_map/include"), "-I" + str(output / "include"),
             "-c", str(probe), "-o", str(tmp_path / "consumer.o")])


def test_tiny_topology_rejects_duplicate_irqs_and_missing_routes(tmp_path: Path) -> None:
    source = json.loads((TINY / "integration/soc_topology.json").read_text())
    path = tmp_path / "invalid.json"
    source["interrupts"][1]["core_bit"] = source["interrupts"][0]["core_bit"]
    path.write_text(json.dumps(source))
    with pytest.raises(ValueError, match="duplicate"):
        read_topology(path, TINY / "address_map/memory_map.json")
    source = json.loads((TINY / "integration/soc_topology.json").read_text())
    source["apb_targets"].pop()
    path.write_text(json.dumps(source))
    with pytest.raises(ValueError, match="every APB"):
        read_topology(path, TINY / "address_map/memory_map.json")


@pytest.mark.parametrize("override", ["HAVE_HP=YES", "PDK=GF180", "MINI_MODE=PRODUCT",
                                     "LINK_TYPE=ld2_psram", "APP=hp_boot", "HAVE_PLL=YES"])
def test_tiny_rejects_incompatible_profiles(override: str) -> None:
    result = subprocess.run(
        ["make", "CONFIG=configs/ci/ihp130-tiny.mk", override, "config"],
        cwd=ROOT, text=True, capture_output=True,
    )
    assert result.returncode != 0
    assert "TINY" in result.stderr


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
@pytest.mark.parametrize("block", ["fabric", "sysctrl"])
def test_tiny_protocol_contracts(tmp_path: Path, simulator: str, block: str) -> None:
    if not shutil.which(simulator) or not (COMMON / "interface/axi4_if.sv").exists():
        pytest.skip("locked RTL/tool dependency unavailable")
    generated = tmp_path / "map"
    generate_memory_map(TINY / "address_map/memory_map.json", generated, "YES", 128)
    top = "tiny_axi4_fabric_tb" if block == "fabric" else "tiny_sysctrl_tb"
    sources = [COMMON / "utils/register.sv"]
    if block == "fabric":
        sources += [COMMON / "interface/axi4_if.sv", COMMON / "stream/round_robin_arbiter.sv",
                    ROOT / "rtl/ip/interconnect/axi4_error_slave.sv", TINY / "top/tiny_axi4_fabric.sv"]
    else:
        sources += [COMMON / "interface/apb4_if.sv", TINY / "top/tiny_sysctrl.sv"]
    sources.append(ROOT / "tests/rtl" / f"{top}.sv")
    includes = [f"-I{p}" for p in (COMMON, COMMON / "interface", generated / "rtl",
                                   ROOT / "rtl/ip/peripheral", ROOT / "tests/rtl")]
    output = tmp_path / "sim"
    if simulator == "verilator":
        cache = tmp_path / "cache"
        cache.mkdir()
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal",
             "-DSV_ASSRT_DISABLE", "--top-module", top,
             *includes, *(str(p) for p in sources), "--Mdir", str(tmp_path / "obj"),
             "-o", str(output)],
            env={**os.environ, "CCACHE_DIR": str(cache), "CCACHE_TEMPDIR": str(cache)})
        command = [str(output)]
    else:
        if not shutil.which("sv2v"):
            pytest.skip("sv2v unavailable")
        converted = tmp_path / "converted.v"
        conversion = run(["sv2v", "-DSV_ASSRT_DISABLE", *includes, *(str(p) for p in sources)])
        converted.write_text(conversion.stdout)
        run([simulator, "-g2012", "-s", top, "-o", str(output), str(converted)])
        command = ["vvp", str(output)]
    result = run(command, timeout=60)
    assert ("SIM_TEST_PASS Tiny fabric" if block == "fabric" else "SIM_TEST_PASS Tiny SYSCTRL") in result.stdout
    assert not any(marker in result.stdout for marker in ("SIM_TEST_FAIL", "FATAL", "%Error"))


def test_tiny_product_prose_does_not_restore_legacy_sdk_names(tmp_path: Path) -> None:
    from scripts.check_embedded_c import load_policy, policy_issues

    path = tmp_path / "crt/probe.c"
    path.parent.mkdir()
    policy = load_policy(ROOT)
    path.write_text('/* Tiny product */\nconst char *rs_name = "Tiny MCU";\n')
    assert policy_issues(tmp_path, path, policy) == []
    path.write_text('void tiny_uart_init(void);\n')
    assert any("retired tiny" in issue for issue in policy_issues(tmp_path, path, policy))
    path.write_text('#include <tiny_uart.h>\n')
    assert any("legacy include" in issue for issue in policy_issues(tmp_path, path, policy))


def test_tiny_metrics_use_product_top_and_timestamped_yosys_report(tmp_path: Path) -> None:
    import argparse
    from scripts.metrics import collect

    (tmp_path / "meta").mkdir()
    (tmp_path / "meta/manifest.json").write_text('{"configuration": {"SOC": "TINY"}}')
    report = tmp_path / "syn/yosys/rpt"
    report.mkdir(parents=True)
    (report / "retrosoc_tiny_asic_area.json").write_text(
        '[00001.250000] {"design": {"area": 123.5, "num_cells": 42}}\n')
    output = tmp_path / "meta/metrics.json"
    assert collect(argparse.Namespace(variant_root=tmp_path, synth_root=None, sta_root=None,
                                      recipe="balanced", output=output)) == 0
    data = json.loads(output.read_text())
    assert data["synthesis"]["top_area"] == 123.5
    assert data["synthesis"]["top_cells"] == 42


def test_tiny_regression_does_not_require_mini_sources() -> None:
    import sys

    result = run([sys.executable, str(ROOT / "scripts/regress.py"), "--root", str(ROOT),
                  "--suite", "pr", "--pdk", "IHP130", "--soc", "TINY", "--dry-run"])
    commands = result.stdout.splitlines()
    assert commands
    assert all("CONFIG=configs/ci/ihp130-tiny.mk" in line for line in commands)
    assert any("SYNTH=YOSYS synth" in line for line in commands)
    assert any("netsim-boot" in line for line in commands)
    assert any("STA=OPENSTA sta" in line for line in commands)
