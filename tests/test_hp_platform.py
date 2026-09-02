"""HP platform configuration and generated-source boundary tests."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_hp_profile_and_locked_generator_contract() -> None:
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    vexii = lock["sources"]["vexiiriscv"]
    assert vexii["revision"] == "ef7da4134ff11ec6a681d0632123b232b853b046"
    assert vexii["recursive"] is True
    assert vexii["destination"].startswith(".cache/")

    profile = (ROOT / "configs/ci/ihp130-hp.mk").read_text(encoding="utf-8")
    assert "HAVE_HP" in profile and "YES" in profile
    assert "rv32imafdc_zicbom_max" in profile
    assert "APP" in profile and "hp_boot" in profile
    assert "LINK_TYPE" in profile and "ld2_all_sram" in profile

    generator = (ROOT / "scripts/vexiiriscv/GenerateRetroSocHp.scala").read_text(
        encoding="utf-8"
    )
    for requirement in (
        'param.addISA("m", "a", "f", "d", "c", "s", "u", "zicbom", "zicntr", "zihpm")',
        "param.decoders = 2",
        "param.lanes = 2",
        "param.fetchL1Ways = 4",
        "param.lsuL1Ways = 4",
        "param.resetVector = 0x38000000L",
        "param.plugins(hartId = 1)",
    ):
        assert requirement in generator


def test_makefile_uses_path_resolved_sbt() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    assert "SBT                ?= sbt" in makefile
    assert "/nfs/home/miaoyuchi/sbt/bin/sbt" not in makefile


def test_hp_linux_simulation_uses_explicit_fast_flash_acceptance() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    verilator_makefile = (ROOT / "rtl/mini/mk/verilator.mk").read_text(encoding="utf-8")
    emulator = (ROOT / "rtl/mini/dv/verilator/csrc/main.cpp").read_text(encoding="utf-8")

    assert "HP_LINUX_SIM_TIME       ?= 7200" in makefile
    assert "hp-linux-sim: hp-bundle comp" in makefile
    assert "VERILATOR_SIM_ARGS=--fast-flash sim" in makefile
    for marker in (
        "VERILATOR_FAST_FLASH=enabled",
        "retroSoC HP Linux ready",
        "HP_LINUX_READY",
        "SIM_TEST_PASS code=0",
    ):
        assert f"--require '{marker}'" in makefile
    assert "VERILATOR_SIM_ARGS      ?=" in verilator_makefile
    assert "$(VERILATOR_SIM_ARGS) -t $(SOC_SIM_TIME)" in verilator_makefile
    assert '("fast-flash"' in emulator


def test_hp_address_and_sysctrl_contract() -> None:
    document = json.loads(
        (ROOT / "rtl/mini/address_map/memory_map.json").read_text(encoding="utf-8")
    )
    regions = {region["symbol"]: region for region in document["regions"]}
    assert regions["HP_ACLINT"]["base"] == "0x02000000"
    assert regions["HP_PLIC"]["base"] == "0x0C000000"
    assert regions["APB4_UART1"]["base"] == "0x10018000"
    assert regions["APB4_HP_MAILBOX"]["base"] == "0x10019000"
    assert regions["APB4_RESOURCE_CTRL"]["base"] == "0x2000A000"

    registers = {register["symbol"]: register["offset"] for register in document["sysctrl_registers"]}
    assert registers["HP_CTRL"] == "0xA4"
    assert registers["HP_STATUS"] == "0xA8"
    assert registers["DEBUG_SELECT"] == "0xAC"


def test_generated_vexii_rtl_is_not_tracked() -> None:
    tracked = subprocess.run(
        ["git", "ls-files", "*vexii_riscv_hp_generated*"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert tracked == ""


def test_hp_smoke_payload_uses_hart1_platform_abi() -> None:
    source = (ROOT / "app/ports/linux/smoke/start.S").read_text(encoding="utf-8")
    assert "0x10018000" in source
    assert "0x10019000" in source
    assert "0x4c4e5801" in source.lower()
    assert "HP_SMOKE_READY" in source


def test_linux_build_uses_external_opensbi_platform_and_actual_initrd_end() -> None:
    build = (ROOT / "scripts/build_hp_linux.py").read_text(encoding="utf-8")
    assert '"tinyconfig"' in build
    assert 'environment.pop("MAKEOVERRIDES", None)' in build
    assert '"PLATFORM=retrosoc_hp"' in build
    assert 'f"PLATFORM_DIR={external / \'opensbi\'}"' in build
    assert '"fdtput"' in build
    assert '"linux,initrd-end"' in build

    platform = (
        ROOT / "app/ports/linux/opensbi/retrosoc_hp/platform.c"
    ).read_text(encoding="utf-8")
    assert "s_hart_index_to_id[] = {1U}" in platform
    assert "RETROSOC_HP_UART_BASE" in platform
    assert "aclint_mtimer_cold_init" in platform


def test_hp_linux_device_tree_compiles_and_can_patch_initrd_end(tmp_path: Path) -> None:
    dtc = shutil.which("dtc")
    fdtput = shutil.which("fdtput")
    fdtget = shutil.which("fdtget")
    if dtc is None or fdtput is None or fdtget is None:
        return
    dtb = tmp_path / "retrosoc_hp.dtb"
    subprocess.run(
        [
            dtc,
            "-I",
            "dts",
            "-O",
            "dtb",
            "-o",
            str(dtb),
            str(ROOT / "app/ports/linux/linux/retrosoc_hp.dts"),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [fdtput, "-t", "x", str(dtb), "/chosen", "linux,initrd-end", "0x39123456"],
        check=True,
    )
    initrd_end = subprocess.check_output(
        [fdtget, "-t", "x", str(dtb), "/chosen", "linux,initrd-end"], text=True
    ).strip()
    hart_id = subprocess.check_output(
        [fdtget, "-t", "x", str(dtb), "/cpus/cpu@1", "reg"], text=True
    ).strip()
    assert initrd_end == "39123456"
    assert hart_id == "1"
    dts = (ROOT / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8")
    assert '"zicbom"' in dts
    assert "riscv,cbom-block-size = <64>;" in dts
