"""Tiny-only publication assembly; no Mini product collector or data is loaded."""
from __future__ import annotations

import copy
import ctypes
import dataclasses
import json
import re
import subprocess
from pathlib import Path

from publications import register_reference as registers
from publications.waveform_reference import source_paths as wave_sources, validate_waveforms
from scripts.check_clock_reset_domains import validate as validate_clocks
from scripts.generate_tiny import read_topology
from scripts.rtl.generate_memory_map import read_map as read_memory
from scripts.rtl.generate_pin_map import read_map as read_pins

ROOT = Path(__file__).resolve().parents[1]
BOOK = Path("publications/datasheets/tiny")
MAP = "rtl/tiny/address_map/memory_map.json"
TOPOLOGY = "rtl/tiny/integration/soc_topology.json"
PINS = "rtl/tiny/pin_map/pin_map.json"
CLOCKS = "rtl/tiny/integration/clock_reset_domains.json"
TOP = "rtl/tiny/top/retrosoc_tiny.sv"
SYSCTRL = "rtl/tiny/top/tiny_sysctrl.sv"
ARCHINFO = "rtl/tiny/top/tiny_archinfo.sv"
FAMILIES = {"xpi", "sram", "gpio", "dma", "timer", "pwm", "rtc", "wdg", "uart", "i2c", "clint", "archinfo"}
MANAGED = {"publication_media", "hazard3", "cluster_common", "cluster_archinfo", "cluster_pwm", "cluster_rtc", "cluster_wdg"}
SUPPORTED_SYSCTRL = {
    "CORESEL", "IPSEL", "USER_CORE_RESET", "USER_CORE_STATUS", "FAULT_STATUS", "FAULT_ADDR",
    "FAULT_COUNT", "FAULT_MASTER", "FAULT_DETAIL", "PERF_CTRL", "PERF_MGMT_WAIT_LO",
    "PERF_MGMT_WAIT_HI", "PERF_DMA_WAIT_LO", "PERF_DMA_WAIT_HI", "TEST_STATUS", "RTC_WAKE_STATUS",
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def profile_values(path: Path) -> dict[str, str]:
    return dict(re.findall(r"^\s*(\w+)\s*:?=\s*([^\s#]+)", path.read_text(encoding="utf-8"), re.M))


def instance_parameters(text: str, module: str, instance: str) -> dict[str, int]:
    found = re.findall(rf"\b{module}\s*#\s*\((.*?)\)\s+{instance}\s*\(", text, re.S)
    if len(found) != 1:
        raise ValueError(f"missing or ambiguous Tiny instance: {instance}")
    return {name: registers.number(value) for name, value in re.findall(r"\.(\w+)\s*\(([^()]*)\)", found[0])}


def require_snippets(root: Path, path: str, snippets: list[str]) -> None:
    text = re.sub(r"\s+", "", registers.strip_comments((root / path).read_text(encoding="utf-8")))
    for snippet in snippets:
        if re.sub(r"\s+", "", snippet) not in text:
            raise ValueError(f"Tiny behavior binding changed: {path}: {snippet}")


def facts(root: Path = ROOT) -> dict:
    profile = profile_values(root / "configs/ci/ihp130-tiny.mk")
    required = {"SOC": "TINY", "PDK": "IHP130", "HAVE_HP": "NO", "HAVE_PLL": "NO",
                "SRAM_SIZE_KIB": "128", "EXT_CLK_HZ": "24000000", "ISA": "RV32IM",
                "HAVE_CSR": "YES", "LINK_TYPE": "ld2_all_sram"}
    if any(profile.get(key) != value for key, value in required.items()):
        raise ValueError("Tiny publication profile changed; review configuration and ISA boundary")
    top = (root / TOP).read_text(encoding="utf-8")
    ram = instance_parameters(top, "onchip_ram", "u_sram")
    dma = instance_parameters(top, "apb4_dma", "u_dma")
    cpu = instance_parameters(top, "mgmt_core_wrapper", "u_cpu")
    if ram != {"CapacityKiB": 128, "DataWidth": 32, "IdWidth": 1}:
        raise ValueError("Tiny SRAM parameters changed")
    if dma != {"NumChannels": 4, "MaxBurstBeats": 16, "FifoDepth": 32, "RequestMask": 0x7F9, "EnableStreams": 0}:
        raise ValueError("Tiny DMA parameters changed")
    if cpu != {"ExternalIrqCount": 30, "EnableAtomics": 0, "TwoCycleBusErrors": 1}:
        raise ValueError("Tiny CPU integration changed")
    require_snippets(root, "rtl/ip/core/mgmt_core_wrapper.sv", [".EXTENSION_C(1)", ".EXTENSION_A(EnableAtomics)"])
    require_snippets(root, TOP, ["u_masters_axi4_if[2]", ".axi4(u_masters_axi4_if[0])",
                               ".axi4(u_masters_axi4_if[1])", ".cfg_apb4(u_sram_apb4_if)",
                               "assign s_tick = s_tick_count_q == 5'd23;"])
    require_snippets(root, SYSCTRL, ["(apb4.paddr[1:0] != 2'd0)", "(apb4.pstrb != 4'hf)",
                                   "if (!s_test_q[31] && apb4.pwdata[31]) s_test_d = apb4.pwdata & 32'h8000_ff01;",
                                   "if (!s_fault_stat_d[0])", "if (rtc_wake_i) s_wake_d = 1'b1;"])
    arch = instance_parameters((root / ARCHINFO).read_text(encoding="utf-8").split(".BUILD_ID")[0] + ") u_archinfo (", "apb4_archinfo", "u_archinfo")
    if arch != {"REFERENCE_CLOCK_HZ": 24000000, "SRAM_BYTES": 131072, "TOPOLOGY": 0x20200001,
                "FEATURES0": 0x7FFE, "TECHNOLOGY": 0x02010082}:
        raise ValueError("Tiny discovery parameters changed")
    require_snippets(root, ARCHINFO, ["32'h5449_4e59 : u_info_apb4_if.prdata", ".device_id_valid_i(1'b0)", ".device_id_read_enable_i(1'b0)"])
    return {"profile": profile, "sram": ram, "dma": dma, "cpu": cpu, "archinfo": arch,
            "hardware_isa": "RV32IMC", "firmware_isa": profile["ISA"], "soc_id": 0x54494E59,
            "system_hz": int(profile["EXT_CLK_HZ"]), "timebase_hz": int(profile["CLINT_TIMEBASE_HZ"])}


def field_rows(parts: list[tuple[str, int, int, str]]) -> list[dict]:
    rows, used = [], set()
    for name, low, high, description in parts:
        rows.append(dict(name=name, lsb=low, msb=high, description=description, reset="0", expression="Tiny source-bound field"))
        if used.intersection(range(low, high + 1)):
            raise ValueError("overlapping Tiny SYSCTRL field")
        used.update(range(low, high + 1))
    for low in range(32):
        if low in used:
            continue
        high = low
        while high + 1 < 32 and high + 1 not in used:
            high += 1
        used.update(range(low, high + 1))
        rows.append(dict(name="Reserved", lsb=low, msb=high, description="Reads zero; use zero when writing. No stored state.", reset="0", expression="zero"))
    return sorted(rows, key=lambda row: row["lsb"])


def sysctrl_registers(root: Path) -> dict:
    text = (root / SYSCTRL).read_text(encoding="utf-8")
    read_case = text.split("unique case (s_offset)")[1].split("endcase")[0]
    active = set(re.findall(r"`APB4_SYSCTRL__(\w+)", read_case))
    if active != SUPPORTED_SYSCTRL:
        raise ValueError("Tiny SYSCTRL decode coverage changed")
    offsets = {r["symbol"]: int(r["offset"], 0) for r in read(root / MAP)["sysctrl_registers"]}
    definitions = {
        "FAULT_STATUS": ("RW1C", "Sticky first fault. Bit 0 clears pending; a new fault can win after clear.", [("PENDING", 0, 0, "A fault record is pending."), ("WRITE", 1, 1, "Faulting transaction was a write."), ("CLASS", 2, 4, "1: decode error; 2: protocol/target error.")]),
        "FAULT_MASTER": ("RO", "Master of the captured first fault.", [("MASTER", 0, 0, "0 CPU, 1 DMA.")]),
        "FAULT_DETAIL": ("RO", "Captured AXI response code.", [("RESPONSE", 0, 1, "AXI RRESP/BRESP encoding.")]),
        "PERF_CTRL": ("RW / command", "Enable counters, clear counters/snapshots or capture a coherent pair. Clear takes precedence over snapshot.", [("ENABLE", 0, 0, "Counter enable state."), ("CLEAR", 1, 1, "Write-one pulse; reads zero."), ("SNAPSHOT", 2, 2, "Write-one pulse; reads zero.")]),
        "TEST_STATUS": ("RW sticky", "First full-word valid result is sticky until system reset; write mask 0x8000FF01.", [("PASS", 0, 0, "Pass when valid is set."), ("CODE", 8, 15, "Application-defined result code."), ("VALID", 31, 31, "The first valid write locks the result.")]),
        "RTC_WAKE_STATUS": ("RO / W1C", "Live wake and sticky observation; hardware set wins over clear.", [("LIVE", 0, 0, "Live RTC wake input."), ("SEEN", 1, 1, "Sticky seen flag; write one to clear.")]),
    }
    rows = []
    for name in sorted(active, key=offsets.get):
        default = "Read-only compatibility value; no selectable core or IP." if name in {"CORESEL", "IPSEL", "USER_CORE_RESET", "USER_CORE_STATUS"} else (
            "Saturating count of fault events; clearing pending does not clear this count." if name == "FAULT_COUNT" else
            "Captured first-fault address." if name == "FAULT_ADDR" else "Word of the CPU/DMA wait-counter snapshot; capture through PERF_CTRL before combining halves.")
        access, description, parts = definitions.get(name, ("RO", default, [("VALUE", 0, 31, default)]))
        reset = 0xFFFFFFFF if name == "USER_CORE_RESET" else 0x200 if name == "USER_CORE_STATUS" else 0
        fields = field_rows(parts)
        for f in fields:
            f["reset"] = hex((reset >> f["lsb"]) & ((1 << (f["msb"] - f["lsb"] + 1)) - 1))
        rows.append(dict(key="main." + name, name=name, symbol="APB4_SYSCTRL__" + name, offset=offsets[name], group="main",
                         width=32, access=access, reset=f"0x{reset:08X}", rtl_reset=f"0x{reset:08X}", description=description,
                         fields=fields, source=SYSCTRL, line=text[:text.index("`APB4_SYSCTRL__" + name)].count("\n") + 1,
                         c_source="crt/include/retrosoc/hal/sysctrl.h", review=None, readback=[]))
    return dict(id="sysctrl", groups=[dict(id="main", title="Tiny control and diagnostics", base=0, stride=0, count=1)],
                registers=rows, document="docs/ip/tiny-soc.md", sources=[SYSCTRL, MAP, "rtl/ip/peripheral/sysctrl_define.svh", "crt/include/retrosoc/hal/sysctrl.h", "crt/src/hal/sysctrl.c"])


def collect_registers(fact: dict, root: Path = ROOT) -> dict:
    profiles = read(root / BOOK / "register-profiles.json")
    annotations = read(root / BOOK / "register-annotations.json")
    if set(profiles) != FAMILIES or any(s.get("memory_map") != MAP for s in profiles.values()):
        raise ValueError("Tiny register families must be independent of Mini")
    profiles["sram"]["parameters"].update(CapacityKiB=fact["sram"]["CapacityKiB"], BankCount=32, DataBytes=4)
    profiles["dma"]["parameters"].update(NumChannels=fact["dma"]["NumChannels"], EnableStreams=0, ChannelIndexWidth=2)
    profiles["dma"]["groups"][1]["count"] = fact["dma"]["NumChannels"]
    profiles["archinfo"]["parameters"].update(fact["archinfo"])
    result = {name: registers.extract_profile(name, spec, annotations.get(name, {})) for name, spec in profiles.items()}
    info = result["archinfo"]
    info["sources"].append(ARCHINFO)
    for reg in info["registers"]:
        if reg["name"] == "SOC_ID":
            value = fact["soc_id"]
            reg.update(reset=f"0x{value:08X}", rtl_reset=f"0x{value:08X}", readback=["Tiny adapter constant 0x54494E59"], description="Tiny SoC identity supplied by the owned adapter.", source=ARCHINFO, line=28,
                       fields=[dict(name="SOC_ID", lsb=0, msb=31, description="ASCII TINY; validate before using product-specific controls.", reset=hex(value), expression="Tiny adapter constant")])
        if reg["name"] in {"BUILD_ID_LO", "BUILD_ID_HI", "CONFIG_ID", "BUILD_STATUS"}:
            reg.pop("rtl_reset", None)
            reg["reset"] = "Build-dependent"
            for f in reg["fields"]:
                f["reset"] = "Build-dependent"
    result["sysctrl"] = sysctrl_registers(root)
    registers.validate_reference(result)
    validate_register_inventory(result, read(root / BOOK / "register-contract.json"))
    return result


def validate_register_inventory(reference: dict, expected: dict) -> None:
    actual = {family: {r["key"]: r["offset"] for r in value["registers"]} for family, value in reference.items()}
    if actual != expected:
        raise ValueError("Tiny frozen register inventory has missing, extra or changed entries")


def validate_evidence(value: dict) -> None:
    if value.get("status") != "prototype" or value.get("current_commit_reports") != []:
        raise ValueError("Tiny qualification requires matching independently reviewed reports")
    if value.get("historical_source") != "docs/ip/tiny-soc-verification.md" or not value.get("boundary"):
        raise ValueError("Tiny historical evidence needs its source and scope")


def validate_configuration(config: dict) -> None:
    expected = {"title": "retroSoC Tiny Gen1", "document_id": "RS-TINY-DS", "status": "DRAFT",
                "profile": "configs/ci/ihp130-tiny.mk", "entrypoint": "publications/datasheets/tiny/datasheet.typ",
                "filename": "retrosoc-tiny-gen1-datasheet.pdf"}
    if any(config.get(key) != value for key, value in expected.items()):
        raise ValueError("Tiny publication configuration cannot select another product or claim release")


def validate_maps(root: Path, fact: dict) -> tuple:
    topology = read_topology(root / TOPOLOGY, root / MAP)
    reset, regions, _ = read_memory(root / MAP, fact["sram"]["CapacityKiB"])
    contract = read(root / BOOK / "source-contract.json")
    if {r["symbol"]: (r["base"], r["size"]) for r in regions} != {k: tuple(v) for k, v in contract["regions"].items()}:
        raise ValueError("Tiny address coverage changed")
    if {r["name"]: r["core_bit"] for r in topology["interrupts"]} != contract["interrupts"]:
        raise ValueError("Tiny interrupt coverage changed")
    return reset, regions, topology


def collect(config: dict, *, check_snapshot: bool = True) -> dict:
    validate_configuration(config)
    fact = facts()
    reset, regions, topology = validate_maps(ROOT, fact)
    pads, _ = read_pins(ROOT / PINS)
    validate_clocks(ROOT / CLOCKS, ROOT)
    contract = read(ROOT / BOOK / "source-contract.json")
    for binding in contract["bindings"]:
        require_snippets(ROOT, binding["file"], binding["text"])
    refs = collect_registers(fact)
    catalog = read(ROOT / BOOK / "catalog.json")
    index = read(ROOT / BOOK / "chapter-index.json")
    frozen_ids = read(ROOT / BOOK / "structure-contract.json")["ip_ids"]
    if ([r["id"] for r in catalog] != [r["id"] for r in index] or [r["id"] for r in index] != frozen_ids
            or len(catalog) != 14 or any(r["family"] not in refs for r in catalog)):
        raise ValueError("Tiny IP inventory must contain the fourteen reviewed chapters")
    assigned = {r for row in catalog for r in row["regions"]}
    if assigned != {r["symbol"] for r in regions} or sum(len(r["regions"]) for r in catalog) != len(assigned):
        raise ValueError("Tiny catalog misses an address region")
    waves = read(ROOT / BOOK / "waveforms.json")
    audit = validate_waveforms(waves, ROOT)
    evidence = read(ROOT / BOOK / "evidence.json")
    validate_evidence(evidence)
    lock = read(ROOT / "dependencies/dependencies.lock.json")
    paths = {MAP, TOPOLOGY, PINS, CLOCKS, TOP, SYSCTRL, ARCHINFO, config["profile"],
             "docs/ip/tiny-soc.md", "docs/ip/tiny-soc-verification.md", "dependencies/dependencies.lock.json", "LICENSE"}
    paths.update(contract["sources"])
    paths.update(b["file"] for b in contract["bindings"])
    paths.update(wave_sources(waves))
    for item in refs.values():
        paths.update(item["sources"])
        paths.add(item["document"])
    for row in catalog:
        paths.update(row["sources"])
    for template in (ROOT / BOOK).glob("*.typ"):
        paths.update(re.findall(r'source(?:-note)?\(\s*"([^"]+)"', template.read_text(encoding="utf-8")))
    examples, apis = {}, {}
    for family in refs:
        alias = {"sram": "onchip_sram", "wdg": "watchdog"}.get(family, family)
        header = "crt/include/retrosoc/" + ("core/archinfo.h" if family == "archinfo" else f"hal/{alias}.h")
        paths.add(header)
        declarations = re.findall(r"\b((?:rs_status_t|void|bool|uint\d+_t)\s+(rs_\w+)\s*\([^;{}]*\));", (ROOT / header).read_text(encoding="utf-8"))
        apis[family] = [dict(name=name, signature=" ".join(signature.split()) + ";") for signature, name in declarations
                        if family != "sysctrl" or any(term in name for term in ("fault", "perf", "test_status", "rtc_wake"))]
        path = ROOT / "publications/examples/tiny" / f"{family}.c"
        if path.is_file():
            paths.add(path.relative_to(ROOT).as_posix())
            examples[family] = path.read_text(encoding="utf-8")
    header_text = (ROOT / "crt/include/retrosoc/hal/dma.h").read_text(encoding="utf-8")
    tcd_text = re.search(r"typedef struct\s*\{([^}]+)\}\s*rs_dma_tcd_t;", header_text)
    members = re.findall(r"(uint32_t|int32_t|uint16_t)\s+(\w+)\s*;", tcd_text[1])
    types = {"uint32_t": ctypes.c_uint32, "int32_t": ctypes.c_int32, "uint16_t": ctypes.c_uint16}
    layout = type("TinyTcd", (ctypes.Structure,), {"_fields_": [(name, types[kind]) for kind, name in members]})
    if ctypes.sizeof(layout) != 64 or len(members) != 17:
        raise ValueError("Tiny TCD layout changed")
    tcd = [dict(name=name, offset=getattr(layout, name).offset, bytes=ctypes.sizeof(types[kind]),
                role="reserved" if "reserved" in name else "HAL result" if name in {"crc_result", "status", "bytes_done", "error_status"} else "configuration") for kind, name in members]
    for relative in paths:
        if relative.startswith("rtl/mini/") or not (ROOT / relative).is_file():
            raise ValueError(f"Tiny source missing or product leak: {relative}")
    if check_snapshot:
        if not re.fullmatch(r"[a-f0-9]{40}", config["source_revision"]):
            raise ValueError("Tiny requires a complete reviewed SHA")
        technical = sorted(p for p in paths if not p.startswith("publications/") and p != "dependencies/dependencies.lock.json")
        changed = subprocess.check_output(["git", "diff", "--name-only", config["source_revision"], "--", *technical], cwd=ROOT, text=True).strip()
        if changed:
            raise ValueError("Tiny technical sources differ from reviewed snapshot:\n" + changed)
    for r in regions:
        r.update(base_hex=f"0x{r['base']:08X}", end_hex=f"0x{r['end']:08X}", size_label=f"{r['size'] // 1024} KiB")
    return dict(document=config, facts=fact, reset_address=f"0x{reset:08X}", regions=regions, interrupts=topology["interrupts"], gpio=topology["gpio_alt_functions"],
                pads=[dataclasses.asdict(p) for p in pads], clocks=read(ROOT / CLOCKS)["domains"], registers=refs, catalog=catalog,
                chapter_index=index, waveforms=waves, waveform_audit=audit, source_paths=sorted(paths),
                managed_sources=[v for k, v in lock["sources"].items() if k in MANAGED],
                wave_renderer="/" + lock["archives"]["typst_wavy"]["destination"] + "/wavy.js",
                evidence=copy.deepcopy(evidence), examples=examples, apis=apis, tcd=tcd)
