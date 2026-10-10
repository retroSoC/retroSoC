"""HP platform configuration and generated-source boundary tests."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts import build_hp_linux
from scripts.run_hp_sim import MARKERS


ROOT = Path(__file__).resolve().parents[1]


def test_hp_profile_and_locked_generator_contract() -> None:
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    openc906 = lock["sources"]["openc906"]
    assert openc906["url"] == "https://github.com/XUANTIE-RV/openc906.git"
    assert len(openc906["revision"]) == 40
    assert openc906["destination"].startswith(".cache/")
    assert openc906["license"] == "Apache-2.0"

    profile = (ROOT / "configs/ci/ihp130-hp.mk").read_text(encoding="utf-8")
    assert "HAVE_HP" in profile and "YES" in profile
    assert "HP_CONFIG" not in profile
    assert "APP" in profile and "hp_boot" in profile
    assert "LINK_TYPE" in profile and "ld2_all_sram" in profile

    generator = (ROOT / "scripts/generate_openc906.py").read_text(encoding="utf-8")
    for requirement in (
        'GENERATED_MODULE = "openC906"',
        '"C906_RTL_FACTORY/gen_rtl/cpu/rtl/aq_sysio_kid.v"',
        '"C906_RTL_FACTORY/gen_rtl/mmu/rtl/sysmap.h"',
        "C906_asic_rtl.fl",
        "tdt_dmi_top_rtl.fl",
    ):
        assert requirement in generator

    # The Mini LP/HP contract keeps the HP core at hart 1; upstream hardwires
    # mhartid to 0, so the build substitutes a reviewed override file.
    override = (ROOT / "rtl/mini/ip_overrides/aq_sysio_kid.v").read_text(encoding="utf-8")
    assert "assign sysio_core_hartid[2:0] = 3'd1;" in override
    assert "b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f" in override

    # The sysmap override marks the Mini MMIO window (and the core-internal
    # CLINT/PLIC window) strong-order non-cacheable per the C906 user manual.
    sysmap = (ROOT / "rtl/mini/ip_overrides/sysmap.h").read_text(encoding="utf-8")
    assert "`define SYSMAP_BASE_ADDR1  28'h30000" in sysmap
    assert "`define SYSMAP_FLG1        5'b10011" in sysmap

    wrapper = (ROOT / "rtl/mini/top/hp_core_wrapper.sv").read_text(encoding="utf-8")
    assert "HpResetVector = 40'h00_3800_0000" in wrapper
    assert "HpApbBase = 40'h00_0800_0000" in wrapper
    assert "openC906 u_openc906" in wrapper
    assert "tdt_dmi_top u_tdt_dmi_top" in wrapper


def test_makefile_uses_path_resolved_sbt() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    assert "SBT                ?= sbt" in makefile
    assert "/nfs/home/miaoyuchi/sbt/bin/sbt" not in makefile


def test_hp_linux_simulation_uses_explicit_fast_flash_acceptance() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    verilator_makefile = (ROOT / "rtl/mini/mk/verilator.mk").read_text(encoding="utf-8")
    emulator = (ROOT / "rtl/mini/dv/verilator/csrc/main.cpp").read_text(encoding="utf-8")

    assert "HP_LINUX_SIM_TIME       ?= 0" in makefile
    assert "hp-linux-sim: hp-bundle comp" in makefile
    assert "--workload linux --timeout $(HP_LINUX_SIM_TIME)" in makefile
    for marker in (
        "VERILATOR_FAST_FLASH=enabled",
        "retroSoC HP Linux ready",
        "HP_LINUX_READY",
        "SIM_TEST_PASS code=0",
    ):
        assert marker in (*MARKERS["linux"], "SIM_TEST_PASS code=0", "VERILATOR_FAST_FLASH=enabled")
    assert "VERILATOR_SIM_ARGS      ?=" in verilator_makefile
    assert "$(VERILATOR_SIM_ARGS) -t $(SOC_SIM_TIME)" in verilator_makefile
    assert '("fast-flash"' in emulator


def test_hp_address_and_sysctrl_contract() -> None:
    document = json.loads(
        (ROOT / "rtl/mini/address_map/memory_map.json").read_text(encoding="utf-8")
    )
    regions = {region["symbol"]: region for region in document["regions"]}
    # The C906 internal CLINT/PLIC window is decoded inside the core BIU and
    # never reaches the SoC fabric; the map records it as reserved.
    assert "HP_ACLINT" not in regions
    assert "HP_PLIC" not in regions
    assert regions["HP_C906_SYS"]["base"] == "0x08000000"
    assert regions["HP_C906_SYS"]["size"] == "0x08000000"
    assert regions["HP_C906_SYS"]["kind"] == "reserved"
    assert regions["APB4_UART1"]["base"] == "0x10018000"
    assert regions["APB4_HP_MAILBOX"]["base"] == "0x10019000"
    assert regions["APB4_RESOURCE_CTRL"]["base"] == "0x2000A000"

    registers = {register["symbol"]: register["offset"] for register in document["sysctrl_registers"]}
    assert registers["HP_CTRL"] == "0xA4"
    assert registers["HP_STATUS"] == "0xA8"
    assert registers["DEBUG_SELECT"] == "0xAC"


def test_generated_hp_core_rtl_is_not_tracked() -> None:
    tracked = subprocess.run(
        ["git", "ls-files", "*vexiiriscv_std_generated*", "*vexii_riscv_hp_generated*"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert tracked == ""
    tracked = subprocess.run(
        ["git", "ls-files", "*generated/openc906*"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert tracked == ""


def test_c906_boots_smoke_payload_in_focused_tb(tmp_path: Path) -> None:
    """Boot the real HP smoke payload on the hp_core_wrapper integration."""
    verilator = shutil.which("verilator")
    openc906 = ROOT / ".cache/retrosoc/sources/openc906"
    if verilator is None or not (openc906 / "C906_RTL_FACTORY").is_dir():
        return
    try:
        cross = subprocess.run(
            ["python3", str(ROOT / "scripts/hp_tools.py"), "--root", str(ROOT)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return
    if not Path(cross + "gcc").is_file():
        return

    payload_dir = tmp_path / "payload"
    subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/build_hp_smoke.py"),
            "--source",
            str(ROOT / "app/ports/linux/smoke/start.S"),
            "--linker",
            str(ROOT / "app/ports/linux/smoke/linker.ld"),
            "--output",
            str(payload_dir),
            "--cross",
            cross,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = payload_dir / "images/hp_smoke.bin"
    assert payload.is_file()

    generated = tmp_path / "generated"
    subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/generate_openc906.py"),
            "--root",
            str(ROOT),
            "--source",
            str(openc906),
            "--output",
            str(generated),
            "--manifest",
            str(generated / "manifest.json"),
            "--lock",
            str(ROOT / "dependencies/dependencies.lock.json"),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    hex_image = tmp_path / "hp_smoke.hex"
    hex_image.write_text(
        "".join(f"{byte:02x}\n" for byte in payload.read_bytes()), encoding="utf-8"
    )

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    output = tmp_path / "hp_c906_boot_tb"
    ccache_tmp = tmp_path / "ccache"
    ccache_tmp.mkdir()
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "hp_c906_boot_tb",
            "-I" + str(common / "interface"),
            "-I" + str(common / "utils"),
            "-I" + str(common),
            "-I" + str(common / "cdc"),
            "-I" + str(ROOT / "rtl/mini/top"),
            f"+define+HP_SMOKE_HEX=\"{hex_image}\"",
            str(common / "interface/axi4_if.sv"),
            str(common / "interface/axi4_addr_gen.sv"),
            str(common / "utils/register.sv"),
            str(common / "utils/xchecker.sv"),
            str(common / "utils/spill_register.sv"),
            str(common / "utils/bin2gray.sv"),
            str(common / "utils/gray2bin.sv"),
            str(common / "cdc/cdc_sync.sv"),
            str(common / "cdc/cdc_rst_ctrlr.sv"),
            str(common / "cdc/cdc_2phase.sv"),
            str(common / "clkrst/rst_sync.sv"),
            str(common / "clkrst/clk_int_div.sv"),
            str(ROOT / "rtl/ip/util/soc_common_cdc.sv"),
            str(ROOT / "rtl/mini/top/axi4_downsizer_128to64.sv"),
            str(ROOT / "rtl/mini/top/axi4_mmio_demux.sv"),
            str(ROOT / "rtl/mini/top/axi4_downsizer_64to32.sv"),
            str(ROOT / "rtl/mini/top/axi4_address_gate.sv"),
            str(ROOT / "rtl/mini/top/axi4_async_bridge.sv"),
            str(ROOT / "rtl/mini/top/hp_core_wrapper.sv"),
            "-f",
            str(generated / "openc906.fl"),
            str(ROOT / "tests/rtl/hp_c906_boot_tb.sv"),
            "-Mdir",
            str(tmp_path / "obj"),
            "-o",
            str(output),
        ],
        check=True,
        text=True,
        capture_output=True,
        env={**os.environ, "CCACHE_DIR": str(ccache_tmp), "CCACHE_TEMPDIR": str(ccache_tmp)},
    )
    result = subprocess.run([output], check=True, text=True, capture_output=True)
    assert "HP_C906_BOOT_TEST_PASS" in result.stdout


def test_hp_smoke_payload_uses_hart1_platform_abi() -> None:
    source = (ROOT / "app/ports/linux/smoke/start.S").read_text(encoding="utf-8")
    assert "0x10018000" in source
    assert "0x10019000" in source
    assert "0x4c4e5801" in source.lower()
    assert "HP_SMOKE_READY" in source
    assert "0x10012000" in source
    assert "0x2000a000" in source.lower()
    # C906 cache maintenance: custom-0 dcache.cva/dcache.iva (no Zicbom).
    assert ".insn r 0x0b, 0x0, 0x01, x0, a0, x5" in source
    assert ".insn r 0x0b, 0x0, 0x01, x0, a0, x6" in source
    assert source.count(".balign 64") >= 4
    for marker in ("HP_GA2D_START", "HP_GA2D_PASS", "HP_GA2D_FAIL", "HP_GA2D_CACHE"):
        assert marker in source


def test_hp_smoke_p5_npu_payload_has_stack_cache_and_polling_plan() -> None:
    source = (ROOT / "app/ports/linux/smoke/start.S").read_text(encoding="utf-8")
    linker = (ROOT / "app/ports/linux/smoke/linker.ld").read_text(encoding="utf-8")
    acceptance = (ROOT / "app/ports/linux/smoke/npu_acceptance.c").read_text(encoding="utf-8")
    builder = (ROOT / "scripts/build_hp_smoke.py").read_text(encoding="utf-8")

    assert "la      sp, _stack_top" in source
    assert "call    rs_hp_npu_acceptance" in source
    assert "_bss_start" in linker and "_bss_end" in linker and "_stack_top" in linker
    assert "rs_kws_npu_execute" in acceptance
    assert "rs_npu_irq_enable(0U)" in acceptance
    assert "rs_npu_irq_ack(RS_NPU_IRQ_ALL)" in acceptance
    assert '"--extra-source"' in builder and '"--include"' in builder
    assert '"-march=rv64imafdc_zicsr_zifencei"' in builder
    assert '"-mabi=lp64d"' in builder
    assert "require_rv64_elf(elf)" in builder
    assert 'images / "hp_smoke.bin"' in builder
    assert 'images / "fw_jump.bin"' not in builder


def test_hp_apu_profile_and_payload_use_the_rv64_product_contract() -> None:
    profile = (ROOT / "configs/ci/ihp130-apu.mk").read_text(encoding="utf-8")
    builder = (ROOT / "scripts/build_hp_apu.py").read_text(encoding="utf-8")
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")

    assert "HP_CONFIG" not in profile
    assert '"-march=rv64imafdc_zicsr_zifencei"' in builder
    assert '"-mabi=lp64d"' in builder
    assert "require_rv64_elf(elf)" in builder
    assert 'images / "rootfs.cpio"' in builder
    assert "--output $(HP_APU_BUILD_DIR) --cross $(HP_CROSS)" in makefile

    completed = subprocess.run(
        [
            "make",
            "-s",
            "CONFIG=configs/ci/ihp130-apu.mk",
            "BUILD_TIMESTAMP=2026-09-30-18-40",
            "config",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "HP_CONFIG" not in completed.stdout


def test_hp_smoke_simulation_requires_ga2d_result_and_cache_lifecycle_markers() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    target = makefile.split("hp-smoke-sim: hp-smoke-bundle comp", 1)[1].split("\nifeq", 1)[0]

    assert "HP_SMOKE_SIM_TIME       ?= 300" in makefile
    assert "--workload smoke --timeout $(HP_SMOKE_SIM_TIME)" in target

    for marker in (
        "SIM_TEST_PASS code=0",
        "HP_LINUX_READY",
        "HP_GA2D_PASS",
        "HP_GA2D_CACHE_CLEAN",
    ):
        assert marker in (*MARKERS["smoke"], "SIM_TEST_PASS code=0")


def test_npu_p6_linux_transport_does_not_take_the_normal_ready_exit() -> None:
    source = (ROOT / "app/apps/hp_boot/main.c").read_text(encoding="utf-8")
    linux_branch = source.split(
        "if (header.workload == RS_HP_BOOT_WORKLOAD_LINUX) {", 1
    )[1].split("}", 1)[0]

    assert "#if !defined(RS_NPU_P6_ACCEPTANCE)" in linux_branch
    assert "rs_test_finish(RS_TEST_PASSED" in linux_branch


def test_hp_cache_handshake_budget_covers_cbo_and_mailbox_round_trip() -> None:
    source = (ROOT / "rtl/mini/top/retrosoc.sv").read_text(encoding="utf-8")

    assert "HpCacheHandshakeTimeout = 16'hffff" in source
    assert ".timeout_i      (HpCacheHandshakeTimeout)" in source


def test_hp_lifecycle_flush_preserves_unadmitted_lp_requests() -> None:
    source = (ROOT / "rtl/mini/top/soc_data_plane.sv").read_text(encoding="utf-8")
    lp_data_cdc = source.split(") u_lp_data_cdc (", 1)[1].split(");", 1)[0]

    assert ".clear_i     (1'b0)" in lp_data_cdc
    assert "HP lifecycle flush invalidates HP transport" in lp_data_cdc


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
    assert "retrosoc-hp-c906-clint" in platform
    assert "aclint_mswi_cold_init" in platform


def test_hp_linux_effective_config_is_fail_closed(tmp_path: Path) -> None:
    fragment = (ROOT / "app/ports/linux/linux/retrosoc_hp.config").read_text(
        encoding="utf-8"
    )
    for symbol in build_hp_linux.REQUIRED_LINUX_CONFIG:
        assert f"{symbol}=y" in fragment

    config = tmp_path / ".config"
    valid = "".join(f"{symbol}=y\n" for symbol in build_hp_linux.REQUIRED_LINUX_CONFIG)
    config.write_text(valid, encoding="utf-8")
    build_hp_linux.validate_linux_config(config)

    config.write_text(valid.replace("CONFIG_BINFMT_ELF=y", "# CONFIG_BINFMT_ELF is not set"),
                      encoding="utf-8")
    with pytest.raises(RuntimeError, match="CONFIG_BINFMT_ELF=n"):
        build_hp_linux.validate_linux_config(config)

    config.write_text(valid.replace("CONFIG_TTY=y\n", ""), encoding="utf-8")
    with pytest.raises(RuntimeError, match="CONFIG_TTY=missing"):
        build_hp_linux.validate_linux_config(config)


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
    reservation = subprocess.check_output(
        [fdtget, "-t", "x", str(dtb), "/reserved-memory/opensbi@38000000", "reg"], text=True
    ).strip()
    assert reservation == "38000000 80000"
    properties = subprocess.check_output(
        [fdtget, "-p", str(dtb), "/reserved-memory/opensbi@38000000"], text=True
    ).splitlines()
    assert "no-map" in properties
    dts = (ROOT / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8")
    assert '"thead,c906"' in dts
    assert '"thead,c900-plic"' in dts
    assert '"thead,c900-clint"' in dts
