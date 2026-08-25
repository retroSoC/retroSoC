from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import re
import signal
import subprocess
import sys
import tarfile
import time
from pathlib import Path
from types import SimpleNamespace
from zipfile import ZipFile

import pytest


ROOT = Path(__file__).resolve().parents[1]
FILELIST_SCRIPT_DIR = ROOT / "rtl/mini/script"
FORMAL_SCRIPT_DIR = ROOT / "rtl/mini/formal"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(FILELIST_SCRIPT_DIR))
sys.path.insert(0, str(FORMAL_SCRIPT_DIR))

from filelist import atomic_write, parse_filelists, write_filelist  # noqa: E402
from generate_filelist import generate_all  # noqa: E402
from generate_formal_filelist import generate as generate_formal_filelist  # noqa: E402
from generate_sby_config import render as render_sby_config  # noqa: E402
from scripts.bitwuzla_smt2 import translate_arguments  # noqa: E402
from scripts.analyze_warnings import normalize  # noqa: E402
from scripts.check_c_warnings import self_owned_warnings  # noqa: E402
from scripts.check_format import format_files  # noqa: E402
from scripts.dependency_lock import LockError, load_lock, validate_flake_lock  # noqa: E402
from scripts.development_environment import (  # noqa: E402
    DEFAULT_TOOLS,
    render_activation,
    stamp_data,
)
from scripts.generate_mpw import render_active_manifest, validate_extension_bindings  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.package import make_sbom  # noqa: E402
from scripts.prepare_mpw import patch_serv  # noqa: E402
from scripts import regress  # noqa: E402
from scripts import run_flow  # noqa: E402
from scripts.regress import (  # noqa: E402
    CI_SMOKE_APP_VALUE,
    NIGHTLY_COMMANDS,
    NIGHTLY_EXTRA_COMMANDS,
    PDK_PR_PROFILES,
    PR_COMMANDS,
    RTL_LINT_VALUES,
    SMOKE_COMMANDS,
    pdk_pr_commands,
    regression_environment,
    select_regression,
)
from scripts import setup_helpers  # noqa: E402
from scripts.setup_helpers import download_file, ensure_git_repo  # noqa: E402


def run(*command: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd or ROOT,
        text=True,
        capture_output=True,
        check=True,
    )


def test_atomic_write_preserves_unchanged_mtime(tmp_path: Path) -> None:
    output = tmp_path / "output.fl"
    assert atomic_write(output, "same\n") is True
    first_mtime = output.stat().st_mtime_ns
    assert atomic_write(output, "same\n") is False
    assert output.stat().st_mtime_ns == first_mtime


def test_nested_filelist_and_space_path_round_trip(tmp_path: Path) -> None:
    include_dir = tmp_path / "include files"
    include_dir.mkdir()
    source = tmp_path / "source file.sv"
    library = tmp_path / "library file.v"
    source.write_text("module source_file; endmodule\n", encoding="utf-8")
    library.write_text("module library_file; endmodule\n", encoding="utf-8")

    nested = tmp_path / "nested.fl"
    nested.write_text(
        f'"{source}"\n-v "{library}"\n',
        encoding="utf-8",
    )
    top = tmp_path / "top.fl"
    top.write_text(
        f'+define+TEST=1\n"+incdir+{include_dir}"\n-f "{nested}"\n',
        encoding="utf-8",
    )

    parsed = parse_filelists([top])
    assert parsed.defines == ["+define+TEST=1"]
    assert parsed.incdirs == [include_dir.resolve()]
    assert parsed.files == [source.resolve()]
    assert parsed.library_files == [library.resolve()]

    output = tmp_path / "round trip.fl"
    write_filelist(output, parsed)
    assert parse_filelists([output]) == parsed


def test_generate_all_is_stable_and_expands_paths(tmp_path: Path) -> None:
    defines = ["+define+PDK_IHP130"]
    generated_include = tmp_path / "archinfo metadata"
    generated = generate_all(tmp_path, defines, [generated_include])
    mtimes = {path: path.stat().st_mtime_ns for path in generated}
    generate_all(tmp_path, defines, [generated_include])
    assert {path: path.stat().st_mtime_ns for path in generated} == mtimes
    assert (tmp_path / "def.fl").read_text(encoding="utf-8") == (
        f"+incdir+{generated_include.resolve()} " + " ".join(defines) + "\n"
    )
    cluster = (tmp_path / "clusterip.fl").read_text(encoding="utf-8")
    hazard3 = (tmp_path / "core_hazard3.fl").read_text(encoding="utf-8")
    ihp130 = (tmp_path / "pdk_ihp130.fl").read_text(encoding="utf-8")
    assert str(ROOT / "rtl/managed/clusterip") in cluster
    assert str(ROOT / "rtl/managed/hazard3/hdl") in hazard3
    assert str(ROOT / "physical/pdk/IHP-Open-PDK") in ihp130
    assert "rtl/managed/mpw/core/username3" not in hazard3
    assert (tmp_path / "core_hazard3.fl").is_file()
    assert not (tmp_path / "core_picorv32.fl").exists()
    assert {
        "pdk_gf180.fl",
        "pdk_ics55.fl",
        "pdk_ics55_verilator.fl",
        "pdk_ics55_yosys.fl",
        "pdk_ihp130.fl",
        "pdk_sky130.fl",
    }.issubset({path.name for path in generated})


def test_filelist_round_trips_verilog_define_values(tmp_path: Path) -> None:
    generate_all(tmp_path, ["+define+SOC_JTAG_IDCODE=32'hDEADBEEF"])

    assert (tmp_path / "def.fl").read_text(encoding="utf-8") == (
        "+define+SOC_JTAG_IDCODE=32'hDEADBEEF\n"
    )
    parsed = parse_filelists([tmp_path / "def.fl"])
    output = tmp_path / "round-trip.fl"
    write_filelist(output, parsed)
    assert output.read_text(encoding="utf-8") == ("+define+SOC_JTAG_IDCODE=32'hDEADBEEF\n")
    assert parse_filelists([output]) == parsed


def test_source_export_uses_the_fixed_hazard3_management_core(tmp_path: Path) -> None:
    module_path = ROOT / "physical/smoke/syn/tools/export_soc_sources.py"
    spec = importlib.util.spec_from_file_location("retrosoc_source_export", module_path)
    assert spec is not None and spec.loader is not None
    source_export = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source_export)

    dynamic_core = tmp_path / "core.fl"
    dynamic_ip = tmp_path / "ip.fl"
    dynamic_core.write_text("", encoding="utf-8")
    dynamic_ip.write_text("", encoding="utf-8")

    arguments = SimpleNamespace(
        pdk="IHP130",
        simu="IVERILOG",
        have_pll=False,
        have_sram_if=False,
        have_sram_macro=False,
        have_sva=False,
        jtag_idcode="DEADBEEF",
        dynamic_core_filelist=dynamic_core,
        dynamic_ip_filelist=dynamic_ip,
    )
    generated_dir = tmp_path / "hazard3"
    user_extensions_dir = generated_dir / "user_extensions"
    source_export.generate_all(generated_dir, source_export.build_defines(arguments))
    source_export.generate_user_extensions(
        ROOT / "rtl/mini/integration/user_extensions.json", user_extensions_dir
    )
    filelist = source_export.configured_filelist(
        arguments, generated_dir, user_extensions_dir, require_files=False
    )

    assert "+define+SOC_JTAG_IDCODE=-559038737" in filelist.defines
    assert "+define+SOC_EXT_CLK_HZ=72000000" in filelist.defines
    assert "+define+SOC_AUD_CLK_HZ=18432000" in filelist.defines
    assert "+define+SOC_CLINT_TIMEBASE_HZ=1000000" in filelist.defines
    assert not any(item.startswith("+define+CORE_") for item in filelist.defines)
    assert "+define+HAVE_DEBUG" not in filelist.defines
    assert any(path.name == "hazard3_cpu_1port.v" for path in filelist.files)


def test_librelane_source_export_inlines_hazard3_update_helper() -> None:
    module_path = ROOT / "physical/smoke/syn/tools/export_soc_sources.py"
    spec = importlib.util.spec_from_file_location("retrosoc_librelane_export", module_path)
    assert spec is not None and spec.loader is not None
    source_export = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source_export)

    source = """function [XLEN-1:0] update_nonconst;
    input [XLEN-1:0] prev;
    input [XLEN-1:0] nonconst;
begin
    update_nonconst = (wdata_update & nonconst) | (prev & ~nonconst);
end
endfunction
mtvec_reg <= update_nonconst(mtvec_reg, MTVEC_WMASK);
mie <= update_nonconst(mie, MIE_WMASK);
"""
    sanitized = source_export.sanitize_librelane_source(source)

    assert "update_nonconst" not in sanitized
    assert "mtvec_reg <= ((wdata_update & MTVEC_WMASK) | (mtvec_reg & ~MTVEC_WMASK));" in sanitized
    assert "mie <= ((wdata_update & MIE_WMASK) | (mie & ~MIE_WMASK));" in sanitized


def test_package_forwards_manifest_jtag_idcode() -> None:
    package_source = (ROOT / "scripts/package.py").read_text(encoding="utf-8")

    assert '"--jtag-idcode"' in package_source
    assert 'config.get("JTAG_IDCODE", "DEADBEEF")' in package_source
    assert '"--core"' not in package_source
    for option in (
        "--ext-clk-hz",
        "--aud-clk-hz",
        "--clint-timebase-hz",
        "--memory-map-filelist",
        "--soc-topology-filelist",
        "--user-extensions-filelist",
        "--pin-map-filelist",
        "--archinfo-incdir",
        "--metadata-file",
    ):
        assert f'"{option}"' in package_source
    assert "generate_timing_contract.py" in package_source
    assert "commercial_timing_contract.tcl" in package_source


def test_source_export_writes_tar_without_staging_rtl_tree(tmp_path: Path) -> None:
    module_path = ROOT / "physical/smoke/syn/tools/export_soc_sources.py"
    spec = importlib.util.spec_from_file_location("retrosoc_tar_export", module_path)
    assert spec is not None and spec.loader is not None
    source_export = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source_export)

    source = ROOT / "rtl/mini/top/retrosoc_asic.sv"
    filelist = parse_filelists([], require_files=False)
    filelist.files.append(source)
    contract = tmp_path / "commercial_timing_contract.tcl"
    contract.write_text("set flow::contract 1\n", encoding="utf-8")
    archive = source_export.write_tar(
        filelist,
        tmp_path,
        "MINI",
        {Path("contracts/commercial_timing_contract.tcl"): contract},
    )

    assert not (tmp_path / "rtl").exists()
    with tarfile.open(archive) as bundle:
        names = bundle.getnames()
        assert "rtl/mini/top/retrosoc_asic.sv" in names
        assert bundle.extractfile("rtl/filelist.fl").read().decode() == (
            "mini/top/retrosoc_asic.sv\n"
        )
        assert "rtl/contracts/commercial_timing_contract.tcl" in names
        assert "contracts/commercial_timing_contract.tcl" not in (
            bundle.extractfile("rtl/filelist.fl").read().decode()
        )


def test_source_export_bundles_generated_include(tmp_path: Path) -> None:
    module_path = ROOT / "physical/smoke/syn/tools/export_soc_sources.py"
    spec = importlib.util.spec_from_file_location("retrosoc_include_export", module_path)
    assert spec is not None and spec.loader is not None
    source_export = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source_export)

    include_dir = tmp_path / "generated/archinfo"
    include_dir.mkdir(parents=True)
    header = include_dir / "archinfo_integration_metadata.svh"
    header.write_text("`define ARCHINFO_TEST 1\n", encoding="utf-8")
    source = tmp_path / "design.sv"
    source.write_text(
        '`include "archinfo_integration_metadata.svh"\nmodule design; endmodule\n',
        encoding="utf-8",
    )
    filelist = parse_filelists([], require_files=False)
    filelist.incdirs.append(include_dir)
    filelist.files.append(source)

    archive = source_export.write_tar(filelist, tmp_path / "output", "MINI")

    with tarfile.open(archive) as bundle:
        names = bundle.getnames()
        assert f"rtl/{source_export.bundle_relative(header)}" in names
        filelist_text = bundle.extractfile("rtl/filelist.fl").read().decode()
        assert f"+incdir+{source_export.bundle_relative(include_dir)}" in filelist_text


def test_formal_filelists_are_scoped_to_the_protocol_duts(tmp_path: Path) -> None:
    memory_map = tmp_path / "memory_map"
    topology = tmp_path / "soc_topology"
    user_extensions = tmp_path / "user_extensions"
    (memory_map / "rtl").mkdir(parents=True)
    (topology / "rtl").mkdir(parents=True)
    (user_extensions / "rtl").mkdir(parents=True)

    bus_filelist = tmp_path / "bus.fl"
    rib_adapter_filelist = tmp_path / "rib_adapter.fl"
    rib2apb_filelist = tmp_path / "rib2apb.fl"
    sysctrl_filelist = tmp_path / "sysctrl.fl"
    pll_rcu_filelist = tmp_path / "pll_rcu.fl"
    gpio_filelist = tmp_path / "gpio.fl"
    ws2812_filelist = tmp_path / "ws2812.fl"
    i2c_filelist = tmp_path / "i2c.fl"
    clint_filelist = tmp_path / "clint.fl"
    opipsram_filelist = tmp_path / "opipsram.fl"
    assert generate_formal_filelist("bus", bus_filelist, memory_map, topology, user_extensions)
    assert generate_formal_filelist(
        "rib_adapter", rib_adapter_filelist, memory_map, topology, user_extensions
    )
    assert generate_formal_filelist(
        "rib2apb", rib2apb_filelist, memory_map, topology, user_extensions
    )
    assert generate_formal_filelist(
        "sysctrl", sysctrl_filelist, memory_map, topology, user_extensions
    )
    assert generate_formal_filelist(
        "pll_rcu", pll_rcu_filelist, memory_map, topology, user_extensions
    )
    assert generate_formal_filelist("gpio", gpio_filelist, memory_map, topology, user_extensions)
    assert generate_formal_filelist(
        "ws2812", ws2812_filelist, memory_map, topology, user_extensions
    )
    assert generate_formal_filelist("i2c", i2c_filelist, memory_map, topology, user_extensions)
    assert generate_formal_filelist("clint", clint_filelist, memory_map, topology, user_extensions)
    assert generate_formal_filelist(
        "opipsram", opipsram_filelist, memory_map, topology, user_extensions
    )

    bus = parse_filelists([bus_filelist], require_files=False)
    rib_adapter = parse_filelists([rib_adapter_filelist], require_files=False)
    rib2apb = parse_filelists([rib2apb_filelist], require_files=False)
    sysctrl = parse_filelists([sysctrl_filelist], require_files=False)
    pll_rcu = parse_filelists([pll_rcu_filelist], require_files=False)
    gpio = parse_filelists([gpio_filelist], require_files=False)
    ws2812 = parse_filelists([ws2812_filelist], require_files=False)
    i2c = parse_filelists([i2c_filelist], require_files=False)
    clint = parse_filelists([clint_filelist], require_files=False)
    opipsram = parse_filelists([opipsram_filelist], require_files=False)
    assert "+define+SV_ASSRT_DISABLE" in bus.defines
    assert "+define+PDK_BEHAV" in opipsram.defines
    assert "+define+SV_ASSRT_DISABLE" not in opipsram.defines
    assert ROOT / "rtl/mini/top/rib_bus.sv" in bus.files
    assert ROOT / "rtl/mini/top/rib_if.sv" in bus.files
    assert ROOT / "rtl/mini/top/ribp2rib.sv" in bus.files
    assert ROOT / "rtl/mini/top/rib_error_slave.sv" in bus.files
    assert ROOT / "rtl/mini/formal/bus_formal.sv" in bus.files
    assert ROOT / "rtl/mini/top/rib2ribp.sv" in rib_adapter.files
    assert ROOT / "rtl/mini/formal/rib_adapter_formal.sv" in rib_adapter.files
    assert ROOT / "rtl/mini/top/rib2apb.sv" in rib2apb.files
    assert ROOT / "rtl/mini/formal/rib2apb_formal.sv" in rib2apb.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_pure_if.sv" in rib2apb.files
    assert ROOT / "rtl/ip/peripheral/sysctrl_if.sv" in sysctrl.files
    assert ROOT / "rtl/ip/peripheral/sysctrl_define.svh" in sysctrl.files
    assert ROOT / "rtl/ip/peripheral/sysctrl_reg.sv" in sysctrl.files
    assert ROOT / "rtl/ip/peripheral/sysctrl_core.sv" in sysctrl.files
    assert ROOT / "rtl/ip/peripheral/apb4_sysctrl.sv" in sysctrl.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv" in sysctrl.files
    assert ROOT / "rtl/mini/formal/sysctrl_formal.sv" in sysctrl.files
    assert ROOT / "rtl/mini/top/rcu.sv" in pll_rcu.files
    assert ROOT / "rtl/mini/top/pll_rcu_controller.sv" in pll_rcu.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv" in pll_rcu.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv" in pll_rcu.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv" in gpio.files
    assert ROOT / "rtl/ip/peripheral/gpio_core.sv" in gpio.files
    assert ROOT / "rtl/ip/peripheral/gpio_reg.sv" in gpio.files
    assert ROOT / "rtl/ip/peripheral/apb4_gpio.sv" in gpio.files
    assert ROOT / "rtl/ip/peripheral/user_gpio_if.sv" in gpio.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv" in gpio.files
    assert ROOT / "rtl/mini/formal/gpio_formal.sv" in gpio.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv" in ws2812.files
    assert ROOT / "rtl/ip/serial/apb4_ws2812.sv" in ws2812.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv" in ws2812.files
    assert ROOT / "rtl/mini/formal/ws2812_formal.sv" in ws2812.files
    assert ROOT / "rtl/ip/serial/apb4_i2c.sv" in i2c.files
    assert ROOT / "rtl/ip/serial/i2c_filter.sv" in i2c.files
    assert ROOT / "rtl/mini/formal/i2c_formal.sv" in i2c.files
    assert ROOT / "rtl/ip/peripheral/apb4_clint.sv" in clint.files
    assert ROOT / "rtl/mini/formal/clint_formal.sv" in clint.files
    assert ROOT / "rtl/ip/memory/opipsram_axi4.sv" in opipsram.files
    assert ROOT / "rtl/ip/memory/opipsram_core.sv" in opipsram.files
    assert ROOT / "rtl/ip/memory/opipsram_reg.sv" in opipsram.files
    assert ROOT / "rtl/ip/memory/opipsram_protocol.sv" in opipsram.files
    assert ROOT / "rtl/ip/memory/opipsram_phy.sv" in opipsram.files
    assert ROOT / "rtl/ip/memory/opipsram_trx.sv" in opipsram.files
    assert ROOT / "rtl/ip/util/async_fifo.sv" in opipsram.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/utils/gray2bin.sv" in opipsram.files
    assert ROOT / "rtl/managed/clusterip/common/rtl/utils/xchecker.sv" in opipsram.files
    assert ROOT / "rtl/tech/tc_clk.sv" in opipsram.files
    assert ROOT / "rtl/tech/tc_opipsram_delay.sv" in opipsram.files
    assert ROOT / "rtl/mini/formal/opipsram_formal.sv" in opipsram.files


def test_sysctrl_formal_properties_use_exported_user_core_shape() -> None:
    design = (ROOT / "rtl/mini/formal/sysctrl_formal.sv").read_text(encoding="utf-8")
    properties = (ROOT / "rtl/mini/formal/sysctrl_formal_props.sv").read_text(encoding="utf-8")

    assert "user_reset_mask" in design
    assert "user_core_count" in design
    assert "`USER_CORE_COUNT" not in properties
    assert "rib_wdata[4:0] < user_core_count" in properties
    assert "user_reset == user_reset_mask" in properties
    assert "SYSCTRL_TEST_STATUS_OFFSET" in properties
    assert "test_done" in design


def test_sby_config_uses_prove_and_cover_with_bitwuzla(tmp_path: Path) -> None:
    design = tmp_path / "design.v"
    properties = tmp_path / "properties.v"
    prove_config = render_sby_config("bus_formal", design, properties, "bitwuzla", "prove", 20)
    cover_config = render_sby_config("bus_formal", design, properties, "bitwuzla", "cover", 20)
    compact_cover_config = render_sby_config(
        "i2c_formal", design, properties, "bitwuzla", "cover", 80, vcd=False
    )

    assert "mode prove" in prove_config
    assert "mode cover" in cover_config
    assert "depth 20" in prove_config
    assert "smtbmc --presat --nounroll bitwuzla" in prove_config
    assert f"design.v {design.resolve()}" in prove_config
    assert f"properties.v {properties.resolve()}" in prove_config
    assert "vcd off" not in cover_config
    assert "vcd off" in compact_cover_config


def test_bitwuzla_wrapper_translates_yosys_legacy_arguments() -> None:
    assert translate_arguments(["--smt2", "-i", "--seed=1"]) == ["--lang", "smt2", "--seed=1"]


def test_fatfs_release_script_uses_the_locked_archive_contract() -> None:
    script = ROOT / "scripts/publish_fatfs_artifact.sh"
    content = script.read_text(encoding="utf-8")

    assert script.stat().st_mode & 0o111
    assert 'readonly RELEASE_TAG="fatfs-r0.16"' in content
    assert 'readonly ASSET_NAME="fatfs-r0.16.zip"' in content
    assert "99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e" in content
    assert 'gh release download "$RELEASE_TAG"' in content


def test_formal_result_summary_requires_every_passing_step(tmp_path: Path) -> None:
    proofs = ("bus", "rib2apb", "sysctrl", "pll_rcu", "gpio", "ws2812")
    for proof in proofs:
        directory = tmp_path / proof
        directory.mkdir()
        for step in ("sv2v", "prove", "cover"):
            (directory / f"result-{step}.json").write_text(
                json.dumps({"status": "passed", "tool": f"formal-{step}"}),
                encoding="utf-8",
            )
        for step in ("prove", "cover"):
            (directory / step).mkdir()
            (directory / step / "status").write_text("PASS 0 1\n", encoding="utf-8")

    output = tmp_path / "formal.json"
    run(
        sys.executable,
        str(ROOT / "rtl/mini/formal/formal_results.py"),
        "--output",
        str(output),
        "--proof",
        f"bus={tmp_path / 'bus'}",
        "--proof",
        f"rib2apb={tmp_path / 'rib2apb'}",
        "--proof",
        f"sysctrl={tmp_path / 'sysctrl'}",
        "--proof",
        f"pll_rcu={tmp_path / 'pll_rcu'}",
        "--proof",
        f"gpio={tmp_path / 'gpio'}",
        "--proof",
        f"ws2812={tmp_path / 'ws2812'}",
    )
    result = json.loads(output.read_text(encoding="utf-8"))
    assert result["status"] == "passed"
    assert set(result["proofs"]) == set(proofs)


def test_mpw_generator_uses_only_the_native_v2_contract() -> None:
    source = (ROOT / "scripts/generate_mpw.py").read_text(encoding="utf-8")

    assert "migrate_user_" not in source
    assert "prepare_legacy_mpw_workspace" not in source
    assert '"mpwgen"' in source
    assert '"generate"' in source


def test_serv_setup_patch_is_idempotent(tmp_path: Path) -> None:
    state = tmp_path / "serv_state.v"
    state.write_text(
        "module serv_state;\n"
        "   wire misalign_trap_sync;\n"
        "   assign use_trap = !trap_pending;\n"
        "   wire trap_pending = WITH_CSR & trap_condition;\n"
        "endmodule\n",
        encoding="utf-8",
    )

    patch_serv(tmp_path)
    first = state.read_text(encoding="utf-8")
    patch_serv(tmp_path)

    assert state.read_text(encoding="utf-8") == first
    assert first.index("wire trap_pending;") < first.index("!trap_pending")
    assert "assign trap_pending = WITH_CSR & trap_condition;" in first


def test_serv_setup_patch_rejects_unknown_source(tmp_path: Path) -> None:
    state = tmp_path / "serv_state.v"
    state.write_text("module serv_state; endmodule\n", encoding="utf-8")

    with pytest.raises(RuntimeError, match="patch markers missing"):
        patch_serv(tmp_path)


def test_mpw_active_manifest_uses_self_owned_design_selection(tmp_path: Path) -> None:
    manifest = tmp_path / "mpw.toml"
    manifest.write_text(
        """schema_version = 2
[generator]
api_version = "retrosoc-mpw-v2"
[[design]]
kind = "core"
id = "slow_core"
slot = 0
enabled = false
source_dir = "core/slow"
top = "user_core_design"
filelist = "usercore.fl"
reset = "sync"
name = "Slow"
isa = "rv32i"
maintainer = "owner"
repo = "https://example.com/slow"
[[design]]
kind = "core"
id = "selected_core"
slot = 5
source_dir = "core/selected"
top = "user_core_design"
filelist = "usercore.fl"
reset = "async"
name = "Selected"
isa = "rv32i"
maintainer = "owner"
repo = "https://example.com/selected"
""",
        encoding="utf-8",
    )
    extensions = tmp_path / "user_extensions.json"
    extensions.write_text(
        json.dumps(
            {
                "schema_version": 2,
                "core_targets": [
                    {
                        "slot": 0,
                        "design_id": "selected_core",
                        "module": "mpw_c0",
                        "reset": "async",
                    }
                ],
                "ip_targets": [],
            }
        ),
        encoding="utf-8",
    )

    active = render_active_manifest(manifest, extensions)

    assert 'id = "selected_core"' in active
    assert 'id = "slow_core"' not in active
    assert "slot = 0" in active
    assert "enabled" not in active


def test_mpw_extension_bindings_match_generated_manifest(tmp_path: Path) -> None:
    extensions_path = tmp_path / "rtl/mini/integration/user_extensions.json"
    extensions_path.parent.mkdir(parents=True)
    extensions = {
        "core_targets": [
            {
                "slot": 0,
                "design_id": "core_zero",
                "module": "mpw_core_zero",
                "reset": "sync",
            },
        ],
        "ip_targets": [
            {"slot": 1, "design_id": "ip_one", "module": "mpw_ip_one"},
        ],
    }
    extensions_path.write_text(json.dumps(extensions), encoding="utf-8")
    output = tmp_path / "output"
    output.mkdir()
    manifest = {
        "designs": [
            {
                "kind": "core",
                "id": "core_zero",
                "slot": 0,
                "top": "mpw_core_zero",
                "reset": "sync",
            },
            {"kind": "ip", "id": "ip_one", "slot": 1, "top": "mpw_ip_one"},
        ]
    }
    (output / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    validate_extension_bindings(tmp_path, output)

    extensions["core_targets"][0]["module"] = "wrong_core"
    extensions_path.write_text(json.dumps(extensions), encoding="utf-8")
    with pytest.raises(ValueError, match="does not match"):
        validate_extension_bindings(tmp_path, output)


def test_prepare_norflash_and_missing_firmware(tmp_path: Path) -> None:
    models = tmp_path / "models"
    models.mkdir()
    for name in ("SECSI.TXT", "SFDP.TXT", "SREG.TXT"):
        (models / name).write_text(name, encoding="utf-8")
    firmware = tmp_path / "firmware.hex"
    firmware.write_text("00\n", encoding="utf-8")
    sim_dir = tmp_path / "sim"
    script = ROOT / "rtl/mini/script/prepare_norflash.py"

    run(
        sys.executable,
        str(script),
        "--sim-dir",
        str(sim_dir),
        "--models-dir",
        str(models),
        "--firmware",
        str(firmware),
    )
    assert (sim_dir / "MEM.TXT").resolve() == firmware.resolve()
    assert (sim_dir / "SFDP.TXT").read_text(encoding="utf-8") == "SFDP.TXT"

    firmware.unlink()
    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--sim-dir",
            str(sim_dir),
            "--models-dir",
            str(models),
            "--firmware",
            str(firmware),
        ],
        text=True,
        capture_output=True,
    )
    assert result.returncode != 0
    assert "firmware image not found" in result.stderr


def test_dependency_helpers_are_idempotent(tmp_path: Path) -> None:
    source = tmp_path / "source"
    run("git", "init", str(source))
    run("git", "config", "user.email", "test@example.com", cwd=source)
    run("git", "config", "user.name", "Test", cwd=source)
    run("git", "config", "commit.gpgsign", "false", cwd=source)
    (source / "dependency.txt").write_text("pinned\n", encoding="utf-8")
    run("git", "add", "dependency.txt", cwd=source)
    run("git", "commit", "-m", "pinned", cwd=source)
    revision = run("git", "rev-parse", "HEAD", cwd=source).stdout.strip()

    destination = tmp_path / "checkout"
    ensure_git_repo(str(source), destination, revision)
    first_head = run("git", "rev-parse", "HEAD", cwd=destination).stdout.strip()
    ensure_git_repo(str(source), destination, revision)
    assert run("git", "rev-parse", "HEAD", cwd=destination).stdout.strip() == first_head

    payload = tmp_path / "payload.bin"
    payload.write_bytes(b"verified")
    digest = hashlib.sha256(payload.read_bytes()).hexdigest()
    downloaded = tmp_path / "downloaded.bin"
    download_file(payload.as_uri(), downloaded, digest)
    first_mtime = downloaded.stat().st_mtime_ns
    download_file(payload.as_uri(), downloaded, digest)
    assert downloaded.stat().st_mtime_ns == first_mtime


def test_dependency_helper_limits_recursive_submodules(monkeypatch, tmp_path: Path) -> None:
    commands: list[tuple[str, ...]] = []
    revision = "a" * 40

    def record(command, *, cwd=None) -> None:
        del cwd
        commands.append(tuple(command))

    def git_output_stub(repo: Path, *args: str) -> str:
        del repo
        if args == ("rev-parse", "HEAD"):
            return revision
        if args == ("status", "--porcelain"):
            return ""
        raise AssertionError(f"unexpected git command: {args}")

    monkeypatch.setattr(setup_helpers, "run", record)
    monkeypatch.setattr(setup_helpers, "git_output", git_output_stub)
    ensure_git_repo(
        "https://example.com/pdk.git",
        tmp_path / "pdk",
        revision,
        recursive=True,
        submodules=("libraries/sky130_fd_sc_hd/latest",),
    )

    assert commands[-1] == (
        "git",
        "submodule",
        "update",
        "--init",
        "--depth",
        "1",
        "--",
        "libraries/sky130_fd_sc_hd/latest",
    )


def test_make_dry_run_and_validation_do_not_write_filelists(tmp_path: Path) -> None:
    def build_state() -> dict[str, tuple[int, int]]:
        build = ROOT / "build"
        if not build.exists():
            return {}
        return {
            str(path.relative_to(build)): (path.stat().st_size, path.stat().st_mtime_ns)
            for path in build.rglob("*")
            if path.is_file()
        }

    before = build_state()
    run("make", "-n", "help")
    run(
        "make",
        "-n",
        f"ARCHINFO_METADATA_SCRIPT={tmp_path / 'missing-generate-metadata.py'}",
        "SIMU=IVERILOG",
        "comp",
    )
    run(
        "make",
        "-n",
        "CONFIG=configs/ci/ihp130.mk",
        "SIMU=IVERILOG",
        "RTL_SIM_TIMEOUT=5200000",
        "sim-asm",
    )
    assert build_state() == before

    for simulator in ("UNKNOWN", "XEZIM", "CVC"):
        invalid = subprocess.run(
            ["make", f"SIMU={simulator}", "help"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        assert invalid.returncode != 0
        assert f"Invalid SIMU='{simulator}'" in invalid.stderr

    removed_core = subprocess.run(
        ["make", "CORE=alternate", "config"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert removed_core.returncode != 0
    assert "CORE has been removed" in removed_core.stderr

    default_core = run("make", "config").stdout
    assert any(
        line.startswith("MGMT_CORE") and line.rstrip().endswith("HAZARD3")
        for line in default_core.splitlines()
    )

    removed_debug = subprocess.run(
        ["make", "HAVE_DEBUG=NO", "config"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert removed_debug.returncode != 0
    assert "HAVE_DEBUG has been removed" in removed_debug.stderr

    removed_ip = subprocess.run(
        ["make", "IP=MDD", "config"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert removed_ip.returncode != 0
    assert "IP is no longer configurable" in removed_ip.stderr


def test_format_file_scope_is_tracked_and_self_owned() -> None:
    paths = [
        Path("Makefile"),
        Path("configs/ci/example.mk"),
        Path("rtl/mini/top/retrosoc.sv"),
        Path("rtl/ip/peripheral/apb4_sysctrl.sv"),
        Path("rtl/tech/tc_clk.sv"),
        Path("rtl/demo/reference.v"),
        Path("tests/rtl/bus_fault_tb.sv"),
        Path("rtl/managed/clusterip/common/rtl/utils/register.sv"),
        Path("rtl/managed/third_party/core.v"),
        Path("rtl/mini/filelist.f"),
    ]

    assert format_files(paths, "make") == [
        Path("Makefile"),
        Path("configs/ci/example.mk"),
    ]
    assert format_files(paths, "rtl") == [
        Path("rtl/demo/reference.v"),
        Path("rtl/ip/peripheral/apb4_sysctrl.sv"),
        Path("rtl/mini/top/retrosoc.sv"),
        Path("rtl/tech/tc_clk.sv"),
        Path("tests/rtl/bus_fault_tb.sv"),
    ]


def test_dependency_lock_and_config_key_include_a_fixed_timestamp(tmp_path: Path) -> None:
    lock = load_lock(ROOT / "dependencies/dependencies.lock.json")
    assert lock["schema_version"] == 1
    assert len(lock["sources"]["mpw"]["revision"]) == 40
    assert lock["sources"]["hazard3"]["destination"] == "rtl/managed/hazard3"
    assert lock["sources"]["pdk_sky130"]["submodules"] == ["libraries/sky130_fd_sc_hd/latest"]
    assert lock["container_images"]["ubuntu_22_04"]["image"] == "ubuntu"
    assert lock["nix_inputs"]["nixpkgs"]["revision"] == "50ab793786d9de88ee30ec4e4c24fb4236fc2674"
    validate_flake_lock(lock, ROOT / "flake.lock")

    command = (
        sys.executable,
        str(ROOT / "scripts/config_key.py"),
        "--lock",
        str(ROOT / "dependencies/dependencies.lock.json"),
        "--profile",
        "unit",
        "--timestamp",
        "2026-07-21-10-39",
        "--value",
        "ARCHITECTURE=fixed-management-and-user-extensions",
        "--value",
        "PDK=IHP130",
    )
    first = run(*command).stdout.strip()
    second = run(*command).stdout.strip()
    assert first == second
    assert re.fullmatch(r"unit-2026-07-21-10-39-[0-9a-f]{12}", first)

    invalid_timestamp = subprocess.run(
        [*command, "--timestamp", "2026-07-21-10-99"],
        text=True,
        capture_output=True,
    )
    assert invalid_timestamp.returncode != 0
    assert "timestamp must use %Y-%m-%d-%H-%M" in invalid_timestamp.stderr

    broken = tmp_path / "broken.json"
    broken.write_text('{"schema_version": 1}\n', encoding="utf-8")
    try:
        load_lock(broken)
    except LockError as error:
        assert "missing or empty" in str(error)
    else:
        raise AssertionError("invalid dependency lock was accepted")

    invalid_submodules = json.loads(json.dumps(lock))
    invalid_submodules["sources"]["pdk_sky130"]["submodules"] = ["../outside"]
    broken.write_text(json.dumps(invalid_submodules), encoding="utf-8")
    try:
        load_lock(broken)
    except LockError as error:
        assert "submodule" in str(error)
    else:
        raise AssertionError("invalid submodule path was accepted")


def test_development_environment_contract_is_lock_pinned(tmp_path: Path) -> None:
    lock_path = ROOT / "dependencies/dependencies.lock.json"
    lock = load_lock(lock_path)
    cache = tmp_path / "development"
    stamp = stamp_data(ROOT, cache, DEFAULT_TOOLS, lock, lock_path)

    assert stamp["tools"]["verilator"] == lock["toolchains"]["ubuntu-22.04"]["verilator"]["version"]
    assert stamp["tools"]["openocd"] == lock["toolchains"]["ubuntu-22.04"]["openocd"]["version"]
    assert set(stamp["python_requirements"]) == {"requirements/build.txt", "requirements/ci.txt"}
    activation = render_activation(cache, [cache / "venv/bin", cache / "toolchains/verilator/bin"])
    assert "export RETROSOC_DEVELOPMENT_CACHE=" in activation
    assert "toolchains/verilator/bin" in activation


def test_container_and_nix_environment_files_use_locked_inputs() -> None:
    lock = load_lock(ROOT / "dependencies/dependencies.lock.json")
    dockerfile = (ROOT / "docker/Dockerfile").read_text(encoding="utf-8")
    flake = (ROOT / "flake.nix").read_text(encoding="utf-8")
    sbom = make_sbom(lock)

    assert f"ubuntu@{lock['container_images']['ubuntu_22_04']['digest']}" in dockerfile
    assert "scripts/development_environment.py" in dockerfile
    assert "scripts/development_environment.py" in flake
    assert "buildFHSEnv" in flake
    assert "retrosoc-development retrosoc-dev" in flake
    assert any(component["name"] == "container/ubuntu_22_04" for component in sbom["components"])
    assert any(component["name"] == "nix/nixpkgs" for component in sbom["components"])


def test_regression_runner_uses_one_build_timestamp(monkeypatch) -> None:
    monkeypatch.setenv("BUILD_TIMESTAMP", "2026-07-21-10-39")
    assert regression_environment()["BUILD_TIMESTAMP"] == "2026-07-21-10-39"

    monkeypatch.delenv("BUILD_TIMESTAMP")
    assert re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}",
        regression_environment()["BUILD_TIMESTAMP"],
    )


def test_verilator_simulations_use_uniform_timeout() -> None:
    verilator_makefile = ROOT / "rtl/mini/mk/verilator.mk"
    verilator_source = verilator_makefile.read_text(encoding="utf-8")
    assert "SOC_SIM_TIME            ?= 180" in verilator_source
    assert "RTL_LINT_FLAGS := --lint-only --no-timing" in verilator_source
    assert "--assert --Wall" in verilator_source

    regression_commands = (*SMOKE_COMMANDS, *PR_COMMANDS, *NIGHTLY_COMMANDS)
    for _, values in regression_commands:
        if "SIMU=VERILATOR" in values:
            assert not any(value.startswith("SOC_SIM_TIME=") for value in values)
            if "debug-sim" not in values:
                assert "HAVE_SVA=YES" in values


def test_verilator_has_no_external_core_selection() -> None:
    command_line = (ROOT / "rtl/mini/dv/verilator/csrc/main.cpp").read_text(encoding="utf-8")
    wrapper = (ROOT / "rtl/mini/dv/verilator/rtl/retrosoc_top.sv").read_text(encoding="utf-8")
    testbench = (ROOT / "rtl/mini/dv/tb/retrosoc_tb.sv").read_text(encoding="utf-8")

    assert "core-sel" not in command_line
    assert "core_sel_i" not in wrapper
    assert "core_sel_i" not in testbench


def test_systemverilog_testbench_starts_in_reset_with_known_clocks() -> None:
    testbench = (ROOT / "rtl/mini/dv/tb/retrosoc_tb.sv").read_text(encoding="utf-8")

    assert "localparam time ResetHoldTime = 170744ns;" in testbench
    for clock in ("r_ext_clk", "r_aud_clk", "r_xtal_clk"):
        assert f"{clock} = 1'b0;" in testbench
        assert f"{clock} = ~{clock};" in testbench
    assert testbench.index("r_rst_n = 1'b0;") < testbench.index("#ResetHoldTime;")
    assert testbench.index("#ResetHoldTime;") < testbench.index("r_rst_n = 1'b1;")
    assert "#43;" not in testbench


def test_management_core_is_fixed_to_hazard3_with_debug() -> None:
    wrapper = (ROOT / "rtl/mini/top/mgmt_core_wrapper.sv").read_text(encoding="utf-8")
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")

    assert "CORE has been removed" in makefile
    assert "HAVE_DEBUG has been removed" in makefile
    assert "CORE_$(CORE)" not in makefile
    assert "`ifdef CORE_" not in wrapper
    assert "`ifdef HAVE_DEBUG" not in wrapper
    assert "ahbl2axi4 u_ahbl2axi4" in wrapper
    assert ".RESET_VECTOR       (`SOC_CPU_RESET_ADDR)" in wrapper
    assert ".DEBUG_SUPPORT      (1)" in wrapper


def test_hazard3_debug_flow_is_locked_and_uses_remote_bitbang() -> None:
    lock = load_lock(ROOT / "dependencies/dependencies.lock.json")
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    wrapper = (ROOT / "rtl/mini/top/mgmt_core_wrapper.sv").read_text(encoding="utf-8")
    debug_wrapper = (ROOT / "rtl/mini/top/mgmt_debug_wrapper.sv").read_text(encoding="utf-8")
    verilator_makefile = (ROOT / "rtl/mini/mk/verilator.mk").read_text(encoding="utf-8")
    driver = (ROOT / "scripts/run_debug_session.py").read_text(encoding="utf-8")
    openocd = (ROOT / "rtl/mini/dv/verilator/openocd/retrosoc_hazard3.cfg").read_text(
        encoding="utf-8"
    )

    assert "JTAG_IDCODE              ?= DEADBEEF" in makefile
    assert "if [ $$value -gt 2147483647 ]" in makefile
    assert "HAVE_DEBUG               ?=" not in makefile
    assert ".MULDIV_UNROLL      (2)" in wrapper
    assert ".BRANCH_PREDICTOR   (1)" in wrapper
    assert ".BREAKPOINT_TRIGGERS(2)" in wrapper
    assert ".HAVE_SBA(0)" in debug_wrapper
    assert "mgmt_debug_reset u_mgmt_debug_reset" in debug_wrapper
    assert "--timeout $(SOC_SIM_TIME)" in verilator_makefile
    assert "--require-debug-tools" in verilator_makefile
    assert "HAVE_DEBUG" not in verilator_makefile
    assert "DEBUG_GDB_PASS" in driver
    assert "break *0x30000008" in driver
    assert "adapter driver remote_bitbang" in openocd
    assert "catch {remote_bitbang port $jtag_port}" in openocd
    assert "remote_bitbang_port $jtag_port" in openocd
    assert "-expected-id 0xdeadbeef" in openocd
    assert lock["toolchains"]["ubuntu-22.04"]["openocd"]["version"] == "0.12.0-1"
    assert any(profile == "configs/ci/ihp130-debug.mk" for profile, _ in PR_COMMANDS)


def test_benchmark_profile_uses_functional_sram_and_reserved_data() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    profile = (ROOT / "configs/benchmark/ihp130-hazard3.mk").read_text(encoding="utf-8")
    benchmark = (ROOT / "app/apps/benchmark/main.c").read_text(encoding="utf-8")

    assert re.search(r"^PDK_BEHAV\s+\?= NO$", makefile, re.MULTILINE)
    assert "PDK_BEHAV HAVE_SVA" in makefile
    assert "PDK_BEHAV=YES is for functional simulation" in makefile
    assert re.search(r"^HAVE_SRAM_MACRO\s*:= YES$", profile, re.MULTILINE)
    assert re.search(r"^SRAM_SIZE_KIB\s*:= 128$", profile, re.MULTILINE)
    assert re.search(r"^PDK_BEHAV\s*:= YES$", profile, re.MULTILINE)
    assert "RS_BENCHMARK_SRAM_OFFSET UINT32_C(0x10000)" in benchmark


def test_open_pdk_profiles_enable_32kib_macro_sram_and_ics55_stays_absent() -> None:
    for pdk in ("ihp130", "gf180", "sky130"):
        profile = (ROOT / f"configs/ci/{pdk}.mk").read_text(encoding="utf-8")
        assert re.search(r"^HAVE_SRAM_IF\s*:= YES$", profile, re.MULTILINE)
        assert re.search(r"^HAVE_SRAM_MACRO\s*:= YES$", profile, re.MULTILINE)
        assert re.search(r"^SRAM_SIZE_KIB\s*:= 32$", profile, re.MULTILINE)

    ics55 = (ROOT / "configs/ci/ics55.mk").read_text(encoding="utf-8")
    assert re.search(r"^HAVE_SRAM_IF\s*:= NO$", ics55, re.MULTILINE)
    assert re.search(r"^HAVE_SRAM_MACRO\s*:= NO$", ics55, re.MULTILINE)

    for name in ("ihp130-hazard3", "ihp130-hazard3-coremark"):
        benchmark = (ROOT / f"configs/benchmark/{name}.mk").read_text(encoding="utf-8")
        assert re.search(r"^SRAM_SIZE_KIB\s*:= 128$", benchmark, re.MULTILINE)


def test_smoke_regression_uses_ihp130_behavioral_coverage_only() -> None:
    commands, profiles = select_regression("smoke", "IHP130")

    assert commands == SMOKE_COMMANDS
    assert profiles == ()
    command_values = [values for _, values in commands]
    assert command_values[0] == RTL_LINT_VALUES
    assert (CI_SMOKE_APP_VALUE, "firmware") in command_values
    assert ("SIMU=VERILATOR", "HAVE_SVA=YES", "comp") in command_values
    assert ("SIMU=IVERILOG", "RTL_SIM_TIMEOUT=5200000", "sim-asm") in command_values
    assert not any(
        "synth" in values or "sta" in values or "netsim" in values for values in command_values
    )

    dry_run = run(
        sys.executable,
        str(ROOT / "scripts/regress.py"),
        "--root",
        str(ROOT),
        "--suite",
        "smoke",
        "--pdk",
        "IHP130",
        "--dry-run",
    )
    assert "+ make CONFIG=configs/ci/ihp130.mk APP=ci_smoke firmware" in dry_run.stdout
    assert "netsim" not in dry_run.stdout

    invalid = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/regress.py"),
            "--root",
            str(ROOT),
            "--suite",
            "smoke",
            "--pdk",
            "GF180",
            "--dry-run",
        ],
        text=True,
        capture_output=True,
    )
    assert invalid.returncode != 0
    assert "smoke regression supports only --pdk IHP130" in invalid.stderr


def test_pdk_pr_regressions_cover_firmware_rtl_and_selected_netlist_target() -> None:
    assert set(PDK_PR_PROFILES) == {"GF180", "IHP130", "ICS55", "SKY130"}
    for pdk, profile in PDK_PR_PROFILES.items():
        commands = pdk_pr_commands(profile)
        command_values = [values for _, values in commands]
        assert command_values[0] == RTL_LINT_VALUES
        assert (CI_SMOKE_APP_VALUE, "firmware") in command_values
        assert any(
            CI_SMOKE_APP_VALUE in values and "SIMU=VERILATOR" in values and "firmware" in values
            for values in command_values
        )
        assert any("SIMU=IVERILOG" in values and "sim-asm" in values for values in command_values)
        assert any("SYNTH=YOSYS" in values and "synth" in values for values in command_values)
        assert not any(
            any(value.startswith("SYNTH_RECIPE=") for value in values) for values in command_values
        )
        assert ("STA=OPENSTA", "sta") in command_values
        netlist_targets = {
            value
            for values in command_values
            for value in values
            if value in {"netsim", "netsim-boot"}
        }
        expected_target = "netsim-boot" if pdk in {"GF180", "ICS55"} else "netsim"
        assert netlist_targets == {expected_target}


def test_nightly_regression_runs_optional_yosys_recipes() -> None:
    commands, profiles = select_regression("nightly", "IHP130")

    assert commands == NIGHTLY_COMMANDS
    assert profiles == ("configs/ci/ihp130.mk",)
    assert (
        "configs/ci/ihp130.mk",
        ("SYNTH=YOSYS", "SYNTH_RECIPE=area", "synth"),
    ) in NIGHTLY_COMMANDS
    assert (
        "configs/ci/ihp130.mk",
        ("STA=OPENSTA", "SYNTH_RECIPE=area", "sta"),
    ) in NIGHTLY_COMMANDS
    assert (
        "configs/ci/ihp130.mk",
        ("SYNTH_RECIPE=area", "metrics"),
    ) in NIGHTLY_COMMANDS
    assert (
        "configs/ci/ihp130.mk",
        ("SYNTH=YOSYS", "SYNTH_RECIPE=speed", "synth"),
    ) in NIGHTLY_COMMANDS
    assert (
        "configs/ci/ihp130.mk",
        ("STA=OPENSTA", "SYNTH_RECIPE=speed", "sta"),
    ) in NIGHTLY_COMMANDS
    assert (
        "configs/ci/ihp130.mk",
        ("SYNTH_RECIPE=speed", "metrics"),
    ) in NIGHTLY_COMMANDS
    assert not any(
        any(value.startswith("SYNTH_RECIPE=") for value in values) for _, values in PR_COMMANDS
    )

    nightly = run(
        sys.executable,
        str(ROOT / "scripts/regress.py"),
        "--root",
        str(ROOT),
        "--suite",
        "nightly",
        "--pdk",
        "IHP130",
        "--dry-run",
    )
    assert (
        "+ make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=area synth" in nightly.stdout
    )
    assert "+ make CONFIG=configs/ci/ihp130.mk STA=OPENSTA SYNTH_RECIPE=area sta" in nightly.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=area metrics" in nightly.stdout
    assert (
        "+ make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=speed synth" in nightly.stdout
    )
    assert "+ make CONFIG=configs/ci/ihp130.mk STA=OPENSTA SYNTH_RECIPE=speed sta" in nightly.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=speed metrics" in nightly.stdout

    pr = run(
        sys.executable,
        str(ROOT / "scripts/regress.py"),
        "--root",
        str(ROOT),
        "--suite",
        "pr",
        "--pdk",
        "IHP130",
        "--dry-run",
    )
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth" in pr.stdout
    assert "SYNTH_RECIPE=area" not in pr.stdout
    assert "SYNTH_RECIPE=speed" not in pr.stdout


def test_nightly_extra_regression_skips_pr_netsim() -> None:
    commands, profiles = select_regression("nightly-extra", "IHP130")

    assert commands == NIGHTLY_EXTRA_COMMANDS
    assert profiles == ("configs/ci/ihp130.mk",)
    assert NIGHTLY_COMMANDS == (*PR_COMMANDS, *NIGHTLY_EXTRA_COMMANDS)
    assert not any("netsim" in values for _, values in commands)

    extra = run(
        sys.executable,
        str(ROOT / "scripts/regress.py"),
        "--root",
        str(ROOT),
        "--suite",
        "nightly-extra",
        "--pdk",
        "IHP130",
        "--dry-run",
    )
    assert (
        "+ make CONFIG=configs/benchmark/ihp130-hazard3-coremark.mk SIMU=VERILATOR HAVE_SVA=YES coremark-report"
        in extra.stdout
    )
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=area synth" in extra.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk STA=OPENSTA SYNTH_RECIPE=area sta" in extra.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=area metrics" in extra.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS SYNTH_RECIPE=speed synth" in extra.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk STA=OPENSTA SYNTH_RECIPE=speed sta" in extra.stdout
    assert "+ make CONFIG=configs/ci/ihp130.mk SYNTH_RECIPE=speed metrics" in extra.stdout
    assert "netsim" not in extra.stdout

    invalid = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/regress.py"),
            "--root",
            str(ROOT),
            "--suite",
            "nightly-extra",
            "--pdk",
            "GF180",
            "--dry-run",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert invalid.returncode != 0
    assert "nightly-extra regression supports only --pdk IHP130" in invalid.stderr


def test_nightly_workflow_splits_netsim_from_extended_recipes() -> None:
    nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
    quality = (ROOT / ".github/workflows/quality.yml").read_text()

    assert "suite: pr" in nightly
    assert "timeout_minutes: 360" in nightly
    assert "suite: nightly-extra" in nightly
    assert "timeout_minutes: 180" in nightly
    assert "suite: nightly\n" not in nightly
    assert "--suite nightly-extra --pdk IHP130 --dry-run" in quality


def test_regression_observations_do_not_block_or_skip_metrics(
    monkeypatch, tmp_path: Path, capsys
) -> None:
    calls: list[list[str]] = []

    monkeypatch.setattr(
        regress,
        "select_regression",
        lambda _suite, _pdk: (
            (("unit-profile", ("rtl-lint",)),),
            ("unit-profile",),
        ),
    )
    monkeypatch.setattr(regress, "regression_environment", lambda: {})
    monkeypatch.setattr(regress, "self_owned_warnings", lambda _root, _output: [])
    strict_calls: list[list[str]] = []

    def pass_blocking_check(
        command: list[str], root: Path, capture_output: bool, environment: dict[str, str]
    ) -> str:
        assert root == tmp_path
        assert capture_output is False
        assert environment == {}
        strict_calls.append(command)
        return ""

    monkeypatch.setattr(regress, "run_command", pass_blocking_check)

    def fail_quality_check(
        command: list[str], *, cwd: Path, env: dict[str, str], check: bool
    ) -> subprocess.CompletedProcess[str]:
        assert cwd == tmp_path
        assert env == {}
        assert check is False
        calls.append(command)
        return subprocess.CompletedProcess(command, returncode=1)

    monkeypatch.setattr(regress.subprocess, "run", fail_quality_check)
    monkeypatch.setattr(
        sys,
        "argv",
        ["regress.py", "--root", str(tmp_path), "--suite", "pr"],
    )

    assert regress.main() == 0
    assert strict_calls == [["make", "CONFIG=unit-profile", "rtl-lint"]]
    assert calls == [
        [
            "make",
            "CONFIG=unit-profile",
            "SIMU=VERILATOR",
            "HAVE_SVA=YES",
            "check-rtl-lint",
        ],
        ["make", "CONFIG=unit-profile", "check-warnings"],
        ["make", "CONFIG=unit-profile", "check-metrics"],
    ]
    assert capsys.readouterr().err.count("non-blocking observation failed") == 3


def test_rtl_lint_warning_baseline_is_independent(tmp_path: Path) -> None:
    profile = "unit-profile"
    lint_log = tmp_path / "variant/lint/verilator/lint.log"
    lint_log.parent.mkdir(parents=True)
    lint_log.write_text(
        f"%Warning-WIDTH: {tmp_path}/rtl/top.sv:12: width mismatch\n",
        encoding="utf-8",
    )
    baseline = tmp_path / f"quality/warnings/{profile}/rtl-lint.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "baseline",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--tool",
        "rtl-lint",
        "--log",
        str(lint_log),
        "--output",
        str(baseline),
    )
    report = tmp_path / "rtl-lint-warnings.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "check",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--variant-root",
        str(tmp_path / "variant"),
        "--tool",
        "rtl-lint",
        "--output",
        str(report),
    )
    assert json.loads(report.read_text(encoding="utf-8"))["status"] == "passed"

    lint_log.write_text(
        lint_log.read_text(encoding="utf-8")
        + f"%Warning-UNUSED: {tmp_path}/rtl/top.sv:20: unused signal\n",
        encoding="utf-8",
    )
    failed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/analyze_warnings.py"),
            "check",
            "--root",
            str(tmp_path),
            "--profile",
            profile,
            "--variant-root",
            str(tmp_path / "variant"),
            "--tool",
            "rtl-lint",
            "--output",
            str(report),
        ],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert json.loads(report.read_text(encoding="utf-8"))["failed_tools"] == ["rtl-lint"]


def test_run_flow_writes_structured_result(tmp_path: Path) -> None:
    log = tmp_path / "flow.log"
    result = tmp_path / "result.json"
    run(
        sys.executable,
        str(ROOT / "scripts/run_flow.py"),
        "--tool",
        "unit",
        "--log",
        str(log),
        "--result",
        str(result),
        "--",
        sys.executable,
        "-c",
        "print('flow output')",
    )
    data = json.loads(result.read_text(encoding="utf-8"))
    assert data["status"] == "passed"
    assert data["exit_code"] == 0
    assert data["duration_seconds"] >= 0
    assert log.read_text(encoding="utf-8") == "flow output\n"


def test_run_flow_can_terminate_an_opt_in_local_flow_at_success_marker(tmp_path: Path) -> None:
    log = tmp_path / "marker.log"
    result = tmp_path / "marker.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/run_flow.py"),
            "--tool",
            "test",
            "--log",
            str(log),
            "--result",
            str(result),
            "--success-marker",
            "Hello retroSoC!",
            "--terminate-on-success-marker",
            "--",
            sys.executable,
            "-c",
            "import time; print('Hello retroSoC!', flush=True); time.sleep(30)",
        ],
        text=True,
        capture_output=True,
        timeout=10,
    )
    report = json.loads(result.read_text(encoding="utf-8"))
    assert completed.returncode == 0
    assert report["status"] == "passed"
    assert report["completion_mode"] == "success_marker"
    assert report["success_marker_seen"] is True
    assert "Hello retroSoC!" in log.read_text(encoding="utf-8")


def test_regression_boot_only_mode_replaces_only_netsim_command() -> None:
    transformed = regress.with_netsim_boot_only(PR_COMMANDS)
    flattened = [value for _, values in transformed for value in values]
    assert "netsim" not in flattened
    assert "netsim-boot" in flattened
    assert "SIM_FIRMWARE_NAME=retrosoc_asm" in flattened
    assert not any(value.startswith("SIM_SUCCESS_MARKER=") for value in flattened)
    assert any("sta" in values for _, values in transformed)


def test_run_flow_adds_carriage_return_when_terminal_disables_onlcr(monkeypatch) -> None:
    class Terminal(io.StringIO):
        def isatty(self) -> bool:
            return True

        def fileno(self) -> int:
            return 42

    terminal = Terminal()
    monkeypatch.setattr(run_flow.sys, "stdout", terminal)
    monkeypatch.setattr(
        run_flow.termios,
        "tcgetattr",
        lambda descriptor: [0, run_flow.termios.OPOST, 0, 0, 0, 0, 0],
    )

    run_flow.write_console_output("first\nsecond\n")

    assert terminal.getvalue() == "first\r\nsecond\r\n"


def test_run_flow_keeps_newlines_when_terminal_maps_them_to_carriage_return(monkeypatch) -> None:
    class Terminal(io.StringIO):
        def isatty(self) -> bool:
            return True

        def fileno(self) -> int:
            return 42

    terminal = Terminal()
    monkeypatch.setattr(run_flow.sys, "stdout", terminal)
    monkeypatch.setattr(
        run_flow.termios,
        "tcgetattr",
        lambda descriptor: [0, run_flow.termios.OPOST | run_flow.termios.ONLCR, 0, 0, 0, 0, 0],
    )

    run_flow.write_console_output("first\nsecond\n")

    assert terminal.getvalue() == "first\nsecond\n"


def test_run_flow_byte_output_adds_carriage_return_only_for_terminal(monkeypatch) -> None:
    class Terminal(io.StringIO):
        def __init__(self) -> None:
            super().__init__()
            self.buffer = io.BytesIO()

        def isatty(self) -> bool:
            return True

        def fileno(self) -> int:
            return 42

    terminal = Terminal()
    monkeypatch.setattr(run_flow.sys, "stdout", terminal)
    monkeypatch.setattr(
        run_flow.termios,
        "tcgetattr",
        lambda descriptor: [0, run_flow.termios.OPOST, 0, 0, 0, 0, 0],
    )

    run_flow.write_console_bytes(b"first\nsecond\n")

    assert terminal.buffer.getvalue() == b"first\r\nsecond\r\n"


def test_run_flow_streams_bytes_without_waiting_for_newline(tmp_path: Path) -> None:
    log = tmp_path / "flow.log"
    result = tmp_path / "result.json"
    process = subprocess.Popen(
        [
            sys.executable,
            str(ROOT / "scripts/run_flow.py"),
            "--tool",
            "unit",
            "--stream-bytes",
            "--log",
            str(log),
            "--result",
            str(result),
            "--",
            sys.executable,
            "-c",
            "import os, time; os.write(1, b'A'); time.sleep(2); os.write(1, b'\\xffB')",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    started = time.monotonic()

    assert process.stdout.read(1) == b"A"
    assert time.monotonic() - started < 1

    remaining, stderr = process.communicate(timeout=10)
    assert process.returncode == 0
    assert stderr == b""
    assert remaining == b"\xffB"
    assert log.read_bytes() == b"A\xffB"
    assert json.loads(result.read_text(encoding="utf-8"))["status"] == "passed"


def test_run_flow_records_interruption(tmp_path: Path) -> None:
    log = tmp_path / "interrupted.log"
    result = tmp_path / "interrupted.json"
    process = subprocess.Popen(
        [
            sys.executable,
            str(ROOT / "scripts/run_flow.py"),
            "--tool",
            "unit",
            "--log",
            str(log),
            "--result",
            str(result),
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    for _ in range(50):
        if log.exists():
            break
        time.sleep(0.02)
    process.send_signal(signal.SIGINT)
    process.communicate(timeout=10)
    assert process.returncode == 130
    data = json.loads(result.read_text(encoding="utf-8"))
    assert data["status"] == "failed"
    assert data["exit_code"] == 130
    assert data["error"] == "interrupted"


def test_simulation_success_marker_and_failure_detection(tmp_path: Path) -> None:
    log = tmp_path / "sim.log"
    result = tmp_path / "result.json"
    log.write_text(
        "SIM_TEST_PASS code=0\nSimulation complete\n",
        encoding="utf-8",
    )
    run(
        sys.executable,
        str(ROOT / "scripts/check_simulation.py"),
        "--log",
        str(log),
        "--result",
        str(result),
    )
    assert json.loads(result.read_text(encoding="utf-8"))["status"] == "passed"

    log.write_text(
        "SIM_TEST_PASS code=0\nSIM_TEST_FAIL code=1\n",
        encoding="utf-8",
    )
    failed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/check_simulation.py"),
            "--log",
            str(log),
            "--result",
            str(result),
        ],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert json.loads(result.read_text(encoding="utf-8"))["status"] == "failed"


def test_warning_baseline_rejects_new_signature(tmp_path: Path) -> None:
    profile = "unit-profile"
    log = tmp_path / "variant/sim/verilator/verilating.log"
    log.parent.mkdir(parents=True)
    log.write_text(
        f"%Warning-WIDTH: {tmp_path}/rtl/top.sv:12: width mismatch\n",
        encoding="utf-8",
    )
    baseline = tmp_path / f"quality/warnings/{profile}/verilator.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "baseline",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--tool",
        "verilator",
        "--log",
        str(log),
        "--output",
        str(baseline),
    )
    report = tmp_path / "warnings.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "check",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--variant-root",
        str(tmp_path / "variant"),
        "--tool",
        "verilator",
        "--output",
        str(report),
    )

    log.write_text(
        log.read_text(encoding="utf-8")
        + f"%Warning-UNUSED: {tmp_path}/rtl/top.sv:20: unused signal\n",
        encoding="utf-8",
    )
    failed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/analyze_warnings.py"),
            "check",
            "--root",
            str(tmp_path),
            "--profile",
            profile,
            "--variant-root",
            str(tmp_path / "variant"),
            "--tool",
            "verilator",
            "--output",
            str(report),
        ],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert json.loads(report.read_text(encoding="utf-8"))["failed_tools"] == ["verilator"]


def test_warning_normalization_keeps_ranges_and_removes_variant_hash(tmp_path: Path) -> None:
    message = (
        f"{tmp_path}/build/profile-deadbeef/generated/core.sv:42: "
        "Bit extraction of var[7:0] is too wide"
    )
    normalized = normalize(tmp_path, "WIDTH", message)
    assert normalized == (
        "WIDTH:$BUILD/generated/core.sv:<line>: Bit extraction of var[7:0] is too wide"
    )


def test_warning_normalization_preserves_pdk_signatures(tmp_path: Path) -> None:
    message = (
        f"{tmp_path}/physical/pdk/IHP-Open-PDK/ihp-sg13g2/"
        "libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v:42: "
        "Ignoring unsupported specify block"
    )

    normalized = normalize(tmp_path, "SPECIFYIGN", message)

    assert normalized == (
        "SPECIFYIGN:$ROOT/pdk/IHP-Open-PDK/ihp-sg13g2/"
        "libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v:<line>: "
        "Ignoring unsupported specify block"
    )


def test_warning_normalization_maps_isolated_mpw_sources_to_managed_sources(
    tmp_path: Path,
) -> None:
    message = (
        f"{tmp_path}/build/ihp130-deadbeef/generated/mpw/verilator/core/username1/"
        "./kianV/kianv_harris_mc_edition_username1.v:42: unused signal"
    )
    normalized = normalize(tmp_path, "UNUSEDSIGNAL", message)
    assert normalized == (
        "UNUSEDSIGNAL:$ROOT/rtl/managed/mpw/core/username1/kianV/"
        "kianv_harris_mc_edition.v:<line>: unused signal"
    )


def test_c_warning_filter_excludes_vendored_sources(tmp_path: Path) -> None:
    policy_dir = tmp_path / "quality"
    policy_dir.mkdir()
    (policy_dir / "embedded_c_policy.json").write_text(
        (ROOT / "quality/embedded_c_policy.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    output = "\n".join(
        (
            f"{tmp_path}/crt/src/hal/timer.c:9:1: warning: self-owned warning",
            f"{tmp_path}/app/coremark/coremark-main/core_main.c:4:1: warning: vendor warning",
        )
    )

    warnings = self_owned_warnings(tmp_path, output)

    assert warnings == ["crt/src/hal/timer.c:9: warning: self-owned warning"]


def test_metrics_collection_and_observe_policy(tmp_path: Path) -> None:
    variant = tmp_path / "variant"
    (variant / "sw").mkdir(parents=True)
    (variant / "sw/firmware.bin").write_bytes(b"1234")
    report_dir = variant / "syn/yosys/rpt"
    report_dir.mkdir(parents=True)
    (report_dir / "retrosoc_asic_area.rpt").write_text(
        "  42 1.23E+02 retrosoc_asic\nChip area for top module '\\retrosoc_asic': 123.0\n",
        encoding="utf-8",
    )
    (report_dir / "retrosoc_asic_area.json").write_text(
        json.dumps({"design": {"area": 124.0, "num_cells": 43}}),
        encoding="utf-8",
    )
    timing_dir = variant / "sta/opensta"
    timing_dir.mkdir(parents=True)
    (timing_dir / "timing_metrics.rpt").write_text("-1.0\n-2.0\n-3.0\n-4.0\n", encoding="utf-8")
    (variant / "result-unit.json").write_text(
        json.dumps({"status": "passed", "duration_seconds": 1.25}),
        encoding="utf-8",
    )
    metrics = tmp_path / "metrics.json"
    run(
        sys.executable,
        str(ROOT / "scripts/metrics.py"),
        "collect",
        "--variant-root",
        str(variant),
        "--output",
        str(metrics),
    )
    data = json.loads(metrics.read_text(encoding="utf-8"))
    assert data["firmware"]["firmware.bin"]["bytes"] == 4
    assert data["synthesis"] == {"recipe": "balanced", "top_area": 124.0, "top_cells": 43}
    assert data["timing"]["wns_min"] == -1.0

    policy = tmp_path / "policy.json"
    policy.write_text('{"mode": "observe"}\n', encoding="utf-8")
    run(
        sys.executable,
        str(ROOT / "scripts/metrics.py"),
        "check",
        "--metrics",
        str(metrics),
        "--policy",
        str(policy),
    )


def test_metrics_collection_selects_recipe_roots(tmp_path: Path) -> None:
    variant = tmp_path / "variant"
    synth_root = variant / "syn/yosys-area"
    sta_root = variant / "sta/opensta-area"
    (synth_root / "rpt").mkdir(parents=True)
    sta_root.mkdir(parents=True)
    (synth_root / "rpt/retrosoc_asic_area.json").write_text(
        json.dumps({"design": {"area": 88.0, "num_cells": 19}}), encoding="utf-8"
    )
    (sta_root / "timing_metrics.rpt").write_text("wns_max=-0.25\n", encoding="utf-8")
    metrics = tmp_path / "metrics-area.json"
    run(
        sys.executable,
        str(ROOT / "scripts/metrics.py"),
        "collect",
        "--variant-root",
        str(variant),
        "--synth-root",
        str(synth_root),
        "--sta-root",
        str(sta_root),
        "--recipe",
        "area",
        "--output",
        str(metrics),
    )
    data = json.loads(metrics.read_text(encoding="utf-8"))
    assert data["schema_version"] == 2
    assert data["synthesis"] == {"recipe": "area", "top_area": 88.0, "top_cells": 19}
    assert data["timing"]["wns_max"] == -0.25


def test_safe_extract_rejects_parent_traversal(tmp_path: Path) -> None:
    archive = tmp_path / "unsafe.tar"
    with tarfile.open(archive, "w") as bundle:
        member = tarfile.TarInfo("../outside")
        payload = b"unsafe"
        member.size = len(payload)
        bundle.addfile(member, io.BytesIO(payload))
    try:
        safe_extract(archive, tmp_path / "output")
    except ValueError as error:
        assert "unsafe archive member" in str(error)
    else:
        raise AssertionError("unsafe archive was extracted")
    assert not (tmp_path / "outside").exists()


def test_fatfs_update_reextracts_downloaded_archive(tmp_path: Path) -> None:
    module_path = ROOT / "app/setup.py"
    spec = importlib.util.spec_from_file_location("retrosoc_app_setup", module_path)
    assert spec is not None and spec.loader is not None
    app_setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_setup)

    archive = tmp_path / "ff16.zip"
    with ZipFile(archive, "w") as zip_archive:
        zip_archive.writestr("source/ff.c", "new archive contents\n")

    source = tmp_path / "source"
    source.mkdir()
    (source / "ff.c").write_text("stale contents\n", encoding="utf-8")
    app_setup.extract_fatfs(archive, source, update=False)
    assert (source / "ff.c").read_text(encoding="utf-8") == "stale contents\n"

    app_setup.extract_fatfs(archive, source, update=True)
    assert (source / "ff.c").read_text(encoding="utf-8") == "new archive contents\n"


def test_coremark_setup_patch_is_idempotent(tmp_path: Path) -> None:
    module_path = ROOT / "app/setup.py"
    spec = importlib.util.spec_from_file_location("retrosoc_app_setup", module_path)
    assert spec is not None and spec.loader is not None
    app_setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_setup)

    coremark = tmp_path / "coremark"
    coremark.mkdir()
    (coremark / "coremark.h").write_text('#include "core_portme.h"\n', encoding="utf-8")
    (coremark / "core_main.c").write_text(
        "/* Function: main */\nmain(void) {\n"
        "  if (time_in_secs(total_time) < 10) {\n  }\n"
        "    return MAIN_RETURN_VAL;\n}\n",
        encoding="utf-8",
    )
    previous_coremark_dir = app_setup.COREMARK_DIR
    try:
        app_setup.COREMARK_DIR = coremark
        app_setup.patch_coremark()
        first = (coremark / "core_main.c").read_text(encoding="utf-8")
        app_setup.patch_coremark()
        second = (coremark / "core_main.c").read_text(encoding="utf-8")
    finally:
        app_setup.COREMARK_DIR = previous_coremark_dir

    assert first == second
    assert "core_main(void)" in first
    assert "COREMARK_MIN_RUN_SECS" in first
    assert "#if COREMARK_MIN_RUN_SECS > 0" in first
    assert "return total_errors == 0 ? 0 : 1;" in first


def test_ci_actions_are_pinned_to_commits() -> None:
    action_files = [
        *sorted((ROOT / ".github/workflows").glob("*.yml")),
        *sorted((ROOT / ".github/actions").glob("*/action.yml")),
    ]
    remote_uses = []
    for path in action_files:
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"\s*-?\s*uses:\s*([^\s#]+)", line)
            if match and not match.group(1).startswith("./"):
                remote_uses.append((path, match.group(1)))
    assert remote_uses
    for path, value in remote_uses:
        assert re.fullmatch(r"[^@]+@[0-9a-f]{40}", value), f"unpinned action in {path}: {value}"


HASH_LOCKED_REQUIREMENT = re.compile(r"[^\s=]+==[^\s]+(?:\s+--hash=sha256:[0-9a-f]{64})+")


def hash_locked_requirement_lines(content: str) -> list[str]:
    logical_content = re.sub(r"\\\r?\n[ \t]*", " ", content)
    return [
        line.strip()
        for line in logical_content.splitlines()
        if line.strip() and not line.lstrip().startswith(("#", "--"))
    ]


def test_python_requirements_are_hash_locked() -> None:
    for path in sorted((ROOT / "requirements").glob("*.txt")):
        content = path.read_text(encoding="utf-8")
        assert "--require-hashes" in content
        assert "--only-binary=:all:" in content
        requirements = hash_locked_requirement_lines(content)
        assert requirements
        for requirement in requirements:
            assert HASH_LOCKED_REQUIREMENT.fullmatch(requirement), (
                f"unlocked requirement in {path}: {requirement}"
            )


def test_python_requirement_hash_validation_accepts_multiple_hashes() -> None:
    first_hash = "a" * 64
    second_hash = "b" * 64
    requirements = hash_locked_requirement_lines(
        "--only-binary=:all:\n"
        "--require-hashes\n"
        "ruff==0.15.21 \\\n"
        f"  --hash=sha256:{first_hash} \\\n"
        f"  --hash=sha256:{second_hash}\n"
    )

    assert len(requirements) == 1
    assert HASH_LOCKED_REQUIREMENT.fullmatch(requirements[0])


def test_python_requirement_hash_validation_rejects_unlocked_entries() -> None:
    valid_hash = "a" * 64
    invalid_requirements = (
        "ruff>=0.15.21 --hash=sha256:" + valid_hash,
        "ruff==0.15.21",
        "ruff==0.15.21 --hash=sha256:" + "a" * 63,
        "ruff==0.15.21 --hash=sha256:" + valid_hash + " --extra",
    )

    for requirement in invalid_requirements:
        assert not HASH_LOCKED_REQUIREMENT.fullmatch(requirement)


def test_clean_all_stays_within_repository(tmp_path: Path) -> None:
    fake_root = tmp_path / "repository"
    (fake_root / ".git").mkdir(parents=True)
    (fake_root / "Makefile").write_text("all:\n", encoding="utf-8")
    generated = fake_root / "rtl/mini/.iverilog_build"
    generated.mkdir(parents=True)
    (generated / "simv").write_text("generated", encoding="utf-8")
    dependency = fake_root / "rtl/managed/third_party"
    dependency.mkdir(parents=True)
    (dependency / "model.v").write_text("dependency", encoding="utf-8")

    run(
        sys.executable,
        str(ROOT / "scripts/clean.py"),
        "--root",
        str(fake_root),
        "--path",
        str(generated),
    )
    assert not generated.exists()
    assert (dependency / "model.v").is_file()

    outside = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/clean.py"),
            "--root",
            str(fake_root),
            "--path",
            str(tmp_path / "outside"),
        ],
        text=True,
        capture_output=True,
    )
    assert outside.returncode != 0

    external = tmp_path / "external"
    external.mkdir()
    link = fake_root / "build-link"
    link.symlink_to(external, target_is_directory=True)
    run(
        sys.executable,
        str(ROOT / "scripts/clean.py"),
        "--root",
        str(fake_root),
        "--path",
        str(link),
    )
    assert not link.exists()
    assert external.is_dir()
