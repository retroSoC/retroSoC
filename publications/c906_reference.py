"""Check Mini's fixed OpenC906 integration and publication evidence boundaries."""
from __future__ import annotations

import json
import re
from pathlib import Path

from scripts.generate_openc906 import (
    OVERRIDES, UPSTREAM_FILELISTS, collect_sources, validate_locked_source,
)

SOURCES = (
    "dependencies/dependencies.lock.json", "scripts/generate_openc906.py",
    "rtl/mini/top/hp_core_wrapper.sv", "rtl/mini/top/soc_data_plane.sv",
    "rtl/mini/top/axi4_mmio_demux.sv", "rtl/mini/top/axi4_downsizer_128to64.sv",
    "rtl/mini/top/apb4_periph.sv", "rtl/mini/integration/soc_topology.json",
    "rtl/mini/address_map/memory_map.json", "app/apps/hp_boot/main.c",
    "app/ports/linux/opensbi/retrosoc_hp/platform.c",
    "app/ports/linux/linux/retrosoc_hp.dts", "app/ports/rtthread/start.S",
    "app/ports/linux/smoke/start.S", "app/ports/hp-apu/main.c",
    "app/benchmark/npu/npu_p6_runner.c", "rtl/tech/gf180_sram_sim_cells.sv",
    *(f"rtl/mini/ip_overrides/{name}" for name, _ in OVERRIDES.values()),
)
VENDOR_INPUTS = (
    "C906_RTL_FACTORY/gen_rtl/cpu/rtl/cpu_cfig.h",
    "C906_RTL_FACTORY/gen_rtl/cpu/rtl/openC906.v",
)


def compact(text: str) -> str:
    return re.sub(r"\s+", "", re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S))


def vendor_root(root: Path) -> Path:
    lock = json.loads((root / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    path = (root / lock["sources"]["openc906"]["destination"]).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("OpenC906 source escapes repository")
    return path


def source_paths(root: Path, *, validate: bool = False) -> set[str]:
    source = vendor_root(root)
    if validate:
        lock = json.loads((root / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
        validate_locked_source(source, lock["sources"]["openc906"]["revision"])
    files, _ = collect_sources(root, source)
    paths = {*files, *(source / p for p in (*UPSTREAM_FILELISTS, *OVERRIDES, *VENDOR_INPUTS))}
    return set(SOURCES) | {p.resolve().relative_to(root.resolve()).as_posix() for p in paths}


def plic_offset(root: Path) -> int:
    wrapper = compact((root / "rtl/mini/top/hp_core_wrapper.sv").read_text(encoding="utf-8"))
    core = compact((vendor_root(root) / VENDOR_INPUTS[1]).read_text(encoding="utf-8"))
    if (".pad_plic_int_vld({224'd0,plic_src_i})" not in wrapper
            or "assignplic_int_vld[`PLIC_INT_NUM+15:0]={pad_plic_int_vld[`PLIC_INT_NUM-1:0],14'b0,l2c_plic_ecc_int_vld,1'b0};" not in core):
        raise ValueError("OpenC906 PLIC source-to-ID mapping changed")
    return 16


def internal_interrupt_map(platform: str, dts: str) -> dict[str, str]:
    """Keep internal controller bases distinct from the encompassing system window."""
    definitions = re.findall(r"^#define\s+RETROSOC_HP_CLINT_(\w+)\s+(0x[0-9A-Fa-f]+)UL\b", platform, re.M)
    values = {name: int(value, 16) for name, value in definitions}
    expected = {"BASE": 0x0C000000, "MTIMECMP_LO": 0x4000, "MTIMECMP_HI": 0x4004,
                "STIMECMP_LO": 0xD000, "STIMECMP_HI": 0xD004}
    if len(definitions) != len(values) or values != expected:
        raise ValueError("OpenC906 internal timer address map changed")
    for label, name, base, size in (("hp_clint", "timer", values["BASE"], 0x10000),
                                    ("hp_plic", "interrupt-controller", 0x08000000, 0x04000000)):
        nodes = re.findall(rf"\b{label}:\s*{name}@([0-9a-fA-F]+)\s*\{{(.*?)\}};", dts, re.S)
        if len(nodes) != 1:
            raise ValueError("OpenC906 internal interrupt node missing or ambiguous")
        unit, body = nodes[0]
        regions = re.findall(r"\breg\s*=\s*<\s*(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)\s*>\s*;", body)
        if (int(unit, 16) != base or len(regions) != 1
                or tuple(int(value, 16) for value in regions[0]) != (base, size)):
            raise ValueError("OpenC906 internal interrupt address map changed")
    return {"clint_base": f"0x{values['BASE']:08X}", "plic_base": "0x08000000"}


def collect_c906(root: Path) -> dict:
    from publications.implementation_reference import hp_isa, hp_parameters

    def read(path: str) -> str:
        return compact((root / path).read_text(encoding="utf-8"))

    identity = hp_isa((root / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8"))
    hp = hp_parameters((root / "rtl/mini/top/hp_core_wrapper.sv").read_text(encoding="utf-8"),
                       (root / "rtl/mini/ip_overrides/aq_sysio_kid.v").read_text(encoding="utf-8"))
    if (identity["isa_base"] != "rv64i" or identity["mmu"] != "sv39"
            or set(identity["extensions"]) != {"i", "m", "a", "f", "d", "c", "zicsr", "zifencei"}):
        raise ValueError("OpenC906 ISA/MMU declaration differs from the locked default")
    if hp != {"resetVector": "0x38000000", "sysWindowBase": "0x08000000",
              "coreAxiDataWidth": "128", "fabricAxiDataWidth": "64",
              "externalInterruptSources": "16", "hartId": "1"}:
        raise ValueError("OpenC906 integration identity changed")

    topology = json.loads((root / "rtl/mini/integration/soc_topology.json").read_text(encoding="utf-8"))
    masters = topology["data_master_policies"]
    if (masters[0]["name"] != "hp_mem" or not masters[0]["allow_instruction"]
            or masters[0]["write_targets"] != ["sram", "sdram", "qpi", "opi"]
            or masters[1]["name"] != "hp_retired" or masters[1]["read_targets"]
            or masters[1]["write_targets"] or masters[1]["allow_instruction"]):
        raise ValueError("OpenC906 merged/retired master policy changed")
    regions = json.loads((root / "rtl/mini/address_map/memory_map.json").read_text(encoding="utf-8"))["regions"]
    internal = [r for r in regions if r["symbol"] == "HP_C906_SYS"]
    if (len(internal) != 1 or int(internal[0]["base"], 0) != 0x08000000
            or int(internal[0]["size"], 0) != 0x08000000
            or internal[0]["route"] != "reserved" or internal[0]["user_access"] != "none"
            or any(r["symbol"] in {"HP_ACLINT", "HP_PLIC"} for r in regions)):
        raise ValueError("OpenC906 internal system window changed")
    bindings = {
        "rtl/mini/top/hp_core_wrapper.sv": (
            "openC906 u_openc906 (", ".pad_cpu_sys_cnt(time_i)",
            "assign u_c906_axi4_if.araddr = s_c906_araddr[31:0];",
            "assign u_c906_axi4_if.awaddr = s_c906_awaddr[31:0];",
            ".pad_yy_icg_scan_en(!s_core_rst_b)",
            "axi4_downsizer_128to64 u_hp_downsizer (", "axi4_mmio_demux u_hp_mmio_demux (",
        ),
        "rtl/mini/top/soc_data_plane.sv": (
            "axi4_master_idle u_hp_retired_idle (.axi4(u_master_axi4[1]));",
            "axi4_connector u_hp_mem_connector (.source(u_hp_mem_prefixed_axi4), .sink(u_master_axi4[0]));",
        ),
        "rtl/mini/top/apb4_periph.sv": ("assign hp_time_o = u_clint_if.mtime_o;",),
        "rtl/mini/top/axi4_mmio_demux.sv": (
            "parameter logic [31:0] MmioBase = 32'h0200_0000",
            "parameter logic [31:0] MmioLimit = 32'h3000_0000",
        ),
        "rtl/mini/ip_overrides/aq_biu_write_channel.v": (
            "assign retro_w_ordered = (retro_aw_issued_q != retro_wburst_done_q);",
            "assign wbuf_create_en = wvalid & (!wbuf_vld | pad_biu_wready) & retro_w_ordered;",
        ),
    }
    for path, snippets in bindings.items():
        text = read(path)
        if any(compact(snippet) not in text for snippet in snippets):
            raise ValueError(f"OpenC906 integration binding changed: {path}")
    periph = read("rtl/mini/top/apb4_periph.sv")
    if "u_apb4_hp_aclint" in periph or "u_apb4_hp_plic" in periph:
        raise ValueError("retired HP interrupt controller returned as a SoC target")
    config = (vendor_root(root) / VENDOR_INPUTS[0]).read_text(encoding="utf-8")
    defines = set(re.findall(r"^`define\s+(\w+)", config, re.M))
    if not {"ICACHE_32K", "DCACHE_32K", "PMP_REGION_8", "BHT_16K", "FPU"} <= defines:
        raise ValueError("OpenC906 locked default configuration changed")
    from publications.software_reference import function_body

    platform = (root / "app/ports/linux/opensbi/retrosoc_hp/platform.c").read_text(encoding="utf-8")
    interrupt_map = internal_interrupt_map(
        platform, (root / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8"))
    early = compact(function_body(platform, "retrosoc_hp_early_init"))
    sequence = (
        "csr_write(RETROSOC_HP_CSR_MCOR, RETROSOC_HP_MCOR_INVALIDATE_ALL);",
        "csr_write(RETROSOC_HP_CSR_MHCR, RETROSOC_HP_MHCR_CACHES_BPU);",
        "csr_clear(RETROSOC_HP_CSR_MXSTATUS, RETROSOC_HP_MXSTATUS_MAEE);",
        "retrosoc_hp_mtimecmp_write(~0ULL);",
        "RETROSOC_HP_CLINT_BASE + RETROSOC_HP_CLINT_STIMECMP_LO",
        "RETROSOC_HP_CLINT_BASE + RETROSOC_HP_CLINT_STIMECMP_HI",
        "retrosoc_hp_uart_write(RETROSOC_HP_UART_CTRL_REG, 0U);",
    )
    cursor = 0
    for operation in sequence:
        found = early.find(compact(operation), cursor)
        if found < 0:
            raise ValueError("OpenC906 cold-boot initialization order changed")
        cursor = found + len(compact(operation))
    if ".irqchip_init=fdt_irqchip_init," not in compact(platform):
        raise ValueError("OpenC906 OpenSBI PLIC initialization changed")
    return {"plic_offset": plic_offset(root), "icache_kib": 32, "dcache_kib": 32,
            "pmp_regions": 8, "master_slot": 0, "retired_slot": 1,
            "core_address_bits": 40, "physical_address_bits": 32,
            "system_window_base": "0x08000000", **interrupt_map,
            "macro_qualification": "Source integration and separately scoped functional-model evidence only"}
