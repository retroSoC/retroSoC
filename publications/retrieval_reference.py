"""Publication-only register lookup, diagnostic codes and release evidence."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

from publications.register_reference import number, strip_comments


def dependencies(spec: dict) -> set[str]:
    if "register_index" in spec:
        return set(spec["sources"])
    paths = set(spec.get("sources", []))
    for row in [*spec.get("instances", []), *spec.get("codes", []),
                *spec.get("status_registers", []), *spec.get("verification", [])]:
        paths.update(row.get("sources", []))
        paths.update(row.get("tests", []))
        paths.update(row.get("profiles", []))
        paths.update(b["file"] for b in row.get("bindings", []))
        if row.get("source"):
            paths.add(row["source"])
        for report in row.get("reports", []):
            paths.update((report["path"], report["profile"]))
    return paths


def validate_bindings(root: Path, row: dict) -> None:
    for binding in row.get("bindings", []):
        text = (root / binding["file"]).read_text(encoding="utf-8")
        if re.sub(r"\s+", "", binding["text"]) not in re.sub(r"\s+", "", text):
            raise ValueError(f"retrieval source binding changed: {row['id']}")


def register_index(registers: dict, regions: list[dict], catalog: list[dict],
                   instances: list[dict], mpw: dict) -> dict:
    windows = {r["symbol"]: r for r in regions}
    catalog_map = {r["id"]: r for r in catalog}
    expected = {(family, r["key"]) for family, v in registers.items() for r in v["registers"]}
    covered, identities, occupied = set(), set(), {}
    result = []
    for instance in instances:
        identifier, family = instance["id"], instance["family"]
        if identifier in identities or family not in registers:
            raise ValueError("duplicate instance or unknown register family")
        identities.add(identifier)
        window = windows.get(instance["region"])
        if (window is None or window["kind"] != "active"
                or window["route"] not in {"apb4_system", "apb4_periph"}):
            raise ValueError(f"register index requires an active register window: {identifier}")
        catalog_id = "user-ip" if instance["mode"] == "MPW" else instance.get("catalog", instance["chapter"])
        if window["symbol"] not in catalog_map.get(catalog_id, {}).get("regions", []):
            raise ValueError(f"register window does not belong to instance: {identifier}")
        if instance["mode"] == "MPW":
            matches = [r for r in mpw["ip_targets"] if r["slot"] == instance.get("slot")]
            if len(matches) != 1 or matches[0]["design_id"] != instance.get("design_id"):
                raise ValueError("MPW selection does not match the locked extension manifest")
        elif instance["mode"] != "PRODUCT" or window["symbol"] == "APB4_USER_IP":
            raise ValueError("invalid register index mode")
        reference = registers[family]
        groups = {g["id"]: g for g in reference["groups"]}
        selected = set(instance.get("groups", groups))
        if not selected or not selected <= groups.keys():
            raise ValueError("unknown or empty register group selection")
        excluded = set(instance.get("exclude", []))
        keys = {r["key"] for r in reference["registers"]}
        overrides = instance.get("overrides", {})
        if not excluded <= keys or not overrides.keys() <= keys:
            raise ValueError("unknown index exclusion or override")
        if overrides and not instance.get("bindings"):
            raise ValueError("instance-specific register values require source bindings")
        rows = []
        for register in reference["registers"]:
            if register["group"] not in selected or register["key"] in excluded:
                continue
            group = groups[register["group"]]
            base, stride, count = (group[k] for k in ("base", "stride", "count"))
            if (any(type(v) is not int for v in (base, stride, count, register["offset"]))
                    or base < 0 or count < 1 or stride < 0
                    or (count > 1 and (stride < 4 or stride % 4))):
                raise ValueError("invalid register array geometry")
            first_offset = base + register["offset"]
            last_offset = first_offset + (count - 1) * stride
            width = register["width"]
            if width != 32 or first_offset < 0 or first_offset % 4 or last_offset + 4 > window["size"]:
                raise ValueError(f"unaligned or out-of-window register: {identifier}/{register['key']}")
            first = window["base"] + first_offset
            last = window["base"] + last_offset
            if last + 3 > 0xFFFFFFFF:
                raise ValueError("register address exceeds RV32 address space")
            # Check every covered address, even though the PDF retains compact array formulas.
            scope = (instance["mode"], instance.get("slot"))
            for n in range(count):
                address = first + n * stride
                key = (*scope, address)
                if key in occupied:
                    raise ValueError(f"overlapping register index address: {identifier}/{register['key']}")
                occupied[key] = identifier
            row = {k: register[k] for k in ("key", "name", "width", "offset", "access", "reset", "group")}
            override = overrides.get(register["key"], {})
            if set(override) - {"access", "reset"}:
                raise ValueError("index overrides may qualify only access and reset")
            row.update(override)
            row.update(first=first, last=last, first_hex=f"0x{first:08X}",
                       offset_hex=f"0x{first_offset:03X}", group_base=base,
                       stride=stride, count=count, link=f"reg-{family}-{register['key']}")
            rows.append(row)
            covered.add((family, register["key"]))
        if not rows:
            raise ValueError("empty register index instance")
        result.append({**instance, "base": window["base"], "base_hex": window["base_hex"],
                       "window_size": window["size"], "rows": sorted(rows, key=lambda r: r["first"])})
    if covered != expected:
        raise ValueError(f"register index coverage mismatch: {sorted(expected - covered)}")
    product_windows = {r["symbol"] for r in regions if r["kind"] == "active"
                       and r["route"] in {"apb4_system", "apb4_periph"}
                       and r["symbol"] != "APB4_USER_IP"}
    if {r["region"] for r in result if r["mode"] == "PRODUCT"} != product_windows:
        raise ValueError("register index omits an active PRODUCT register instance")
    if {r.get("slot") for r in result if r["mode"] == "MPW"} != {r["slot"] for r in mpw["ip_targets"]}:
        raise ValueError("register index omits an MPW selection")
    return {"instances": sorted(result, key=lambda r: (r["mode"] == "MPW", r["base"], r["id"])),
            "definitions": len(expected), "rows": sum(len(r["rows"]) for r in result),
            "addresses": len(occupied)}


def code_group(root: Path, spec: dict) -> dict:
    """Read explicitly selected declarations/branches; never evaluate arbitrary source."""
    text = strip_comments((root / spec["source"]).read_text(encoding="utf-8"))
    found = {}
    if spec.get("enum_type"):
        enums = re.findall(r"typedef\s+enum\s+logic(?:\s*\[[^\]]+\])?\s*\{([^{}]*)\}\s*"
                           + re.escape(spec["enum_type"]) + r"\s*;", text, re.S)
        if len(enums) != 1:
            raise ValueError("missing or ambiguous diagnostic enum")
        value = -1
        for declaration in enums[0].split(","):
            parts = declaration.strip().split("=")
            key = parts[0].strip()
            if not re.fullmatch(r"[A-Za-z_]\w*", key) or key in found or len(parts) > 2:
                raise ValueError("unsupported or duplicate diagnostic enum member")
            value = number(parts[1]) if len(parts) == 2 else value + 1
            found[key] = value
    else:
        for match in re.finditer(spec["pattern"], text, re.M):
            value = number(match["value"])
            key = str(value) if spec.get("assignment_values") else match["name"]
            if key in found and not spec.get("assignment_values"):
                raise ValueError(f"duplicate diagnostic code declaration: {spec['id']}/{key}")
            found[key] = value
    if found != spec["expected"] or set(found) != set(spec["meanings"]):
        raise ValueError(f"diagnostic code coverage/value drift: {spec['id']}")
    if len(set(found.values())) != len(found):
        raise ValueError(f"diagnostic enum contains unqualified aliases: {spec['id']}")
    if spec["kind"] not in {"enum", "mask"}:
        raise ValueError("diagnostic code kind must distinguish enum from mask")
    if spec["kind"] == "mask" and any(v <= 0 or v & (v - 1) for v in found.values()):
        raise ValueError("diagnostic mask entries must be individual bits")
    return {**spec, "rows": [{"name": key, "value": value,
                             "display": f"0x{value:X}" if spec["kind"] == "mask" else str(value),
                             "meaning": spec["meanings"][key]}
                            for key, value in sorted(found.items(), key=lambda pair: pair[1])]}


def status_registers(specs: list[dict], registers: dict) -> list[dict]:
    rows, seen = [], set()
    for spec in specs:
        if spec["id"] in seen:
            raise ValueError("duplicate diagnostic register group")
        seen.add(spec["id"])
        family = registers.get(spec["family"])
        if family is None:
            raise ValueError("unknown diagnostic register family")
        by_key = {r["key"]: r for r in family["registers"]}
        if not spec["registers"] or len(set(spec["registers"])) != len(spec["registers"]):
            raise ValueError("empty or repeated diagnostic register selection")
        overrides = spec.get("field_overrides", {})
        if overrides and (not spec.get("bindings") or not overrides.keys() <= set(spec["registers"])):
            raise ValueError("diagnostic field qualification requires selected registers and source bindings")
        selected = []
        for key in spec["registers"]:
            if key not in by_key:
                raise ValueError("unknown diagnostic register")
            r = by_key[key]
            fields = overrides.get(key, [{k: f[k] for k in ("name", "lsb", "msb", "description")}
                                        for f in r["fields"] if f["name"] != "Reserved"])
            used = set()
            for field in fields:
                bits = set(range(field["lsb"], field["msb"] + 1))
                if (not field["name"] or not field["description"] or not bits
                        or field["lsb"] < 0 or field["msb"] >= r["width"] or used & bits):
                    raise ValueError("invalid diagnostic field qualification")
                used.update(bits)
            selected.append({"name": r["name"], "link": f"reg-{spec['family']}-{key}",
                             "access": r["access"], "description": r["description"],
                             "fields": fields})
        rows.append({**spec, "rows": selected})
    return rows


def boot_status(root: Path, spec: dict) -> dict:
    source = strip_comments((root / "app/apps/hp_boot/main.c").read_text(encoding="utf-8"))
    header = (root / "app/apps/hp_boot/hp_boot_bundle.h").read_text(encoding="utf-8")
    direct = [int(v) for v in re.findall(r"rs_hp_boot_fail\(UINT8_C\((\d+)\)\)", source)]
    count = re.findall(r"^#define RS_HP_BOOT_BUNDLE_ENTRY_COUNT UINT32_C\((\d+)\)", header, re.M)
    base = re.findall(r"rs_hp_boot_fail\(\(uint8_t\)\(UINT8_C\((\d+)\) \+ \(uint8_t\)index\)\)", source)
    terminals = re.findall(r"rs_test_finish\((RS_TEST_\w+), UINT8_C\((\d+)\)\)", source)
    if (direct != spec["expected_direct"] or len(count) != 1 or len(base) != 1
            or int(count[0]) != spec["expected_entries"]
            or set(terminals) != {("RS_TEST_FAILED", "1"), ("RS_TEST_PASSED", "0")}):
        raise ValueError("HP boot diagnostic branches changed")
    codes = [0, 1, *direct, *range(int(base[0]), int(base[0]) + int(count[0]))]
    if len(set(codes)) != len(codes) or set(map(str, codes)) != set(spec["meanings"]):
        raise ValueError("HP boot code coverage or scope mismatch")
    hal = (root / "crt/src/hal/sysctrl.c").read_text(encoding="utf-8")
    rtl = (root / "rtl/ip/peripheral/sysctrl_define.svh").read_text(encoding="utf-8")
    positions = {}
    for key in ("VALID", "PASS", "CODE"):
        matches = re.findall(r"^`define APB4_SYSCTRL__TEST_STATUS_" + key + r"\s+(\d+)", rtl, re.M)
        if len(matches) != 1:
            raise ValueError("missing TEST_STATUS field")
        positions[key] = int(matches[0])
    if positions != {"VALID": 31, "PASS": 0, "CODE": 8}:
        raise ValueError("TEST_STATUS field layout changed")
    for key in ("VALID", "PASS"):
        matches = re.findall(r"^#define RS_SYSCTRL_TEST_STATUS_" + key + r"\s+UINT32_C\((0x[0-9A-F]+)\)", hal, re.M)
        if len(matches) != 1 or int(matches[0], 0) != 1 << positions[key]:
            raise ValueError("TEST_STATUS RTL/HAL mask mismatch")
    if not re.search(r"^#define RS_SYSCTRL_TEST_STATUS_CODE_SHIFT\s+8U", hal, re.M):
        raise ValueError("TEST_STATUS RTL/HAL code shift mismatch")
    markers = ("SIM_TEST_PASS", "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT")
    for path in ("rtl/mini/dv/tb/retrosoc_tb.sv", "rtl/mini/dv/verilator/csrc/Emulator.cpp"):
        text = (root / path).read_text(encoding="utf-8")
        if any(marker not in text for marker in markers):
            raise ValueError("simulator completion marker changed")
    return {"rows": [{"value": value, "meaning": spec["meanings"][str(value)]} for value in sorted(codes)],
            "positions": positions, "markers": list(markers)}


def validate_report(root: Path, report: dict, revision: str, profiles: list[str], stage: str) -> None:
    if (report.get("revision") != revision or report.get("profile") not in profiles
            or report.get("stage") != stage or report.get("result") != "pass"):
        raise ValueError("release report does not match revision, profile, stage and pass result")
    path = root / report["path"]
    if not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError("release report file is missing")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if any(payload.get(k) != report[k] for k in ("revision", "profile", "stage", "result")):
        raise ValueError("release report content contradicts its publication record")


def release_evidence(root: Path, spec: dict, revision: str, support: list[dict]) -> dict:
    readiness = json.loads((root / "rtl/rtl_readiness.json").read_text(encoding="utf-8"))
    targets = [{k: row[k] for k in ("name", "status", "baseline_revision", "configuration_digest",
                                   "configuration_profiles", "required_evidence")}
               for row in readiness["targets"]]
    rows, ids = [], set()
    for row in spec["verification"]:
        if row["id"] in ids or row["stage"] not in {"source", "host", "simulation", "physical-analysis", "fpga", "silicon"}:
            raise ValueError("duplicate verification row or invalid evidence stage")
        ids.add(row["id"])
        reports = row.get("reports", [])
        if row["status"] == "Reported pass" and not reports:
            raise ValueError("release pass requires a matching report")
        if reports and row["status"] != "Reported pass":
            raise ValueError("release report and evidence state disagree")
        if row["status"] not in {"Source reviewed", "Tests available", "Not supplied", "Reported pass"}:
            raise ValueError("invalid release verification status")
        if row["status"] == "Tests available" and not row.get("tests"):
            raise ValueError("test availability requires a test entry")
        for report in reports:
            validate_report(root, report, revision, row["profiles"], row["stage"])
        rows.append(copy.deepcopy(row))
    return {"rows": rows, "readiness": targets,
            "support_counts": {value: sum(r["verification"] == value for r in support)
                               for value in ("Source reviewed", "Tests available", "Reported pass")}}


def collect_retrieval(root: Path, spec: dict, registers: dict, regions: list[dict],
                      catalog: list[dict], mpw: dict, revision: str, support: list[dict]) -> dict:
    for row in [*spec["instances"], *spec["codes"], *spec["status_registers"], *spec["verification"]]:
        validate_bindings(root, row)
    code_ids = [r["id"] for r in spec["codes"]]
    if len(code_ids) != len(set(code_ids)):
        raise ValueError("duplicate diagnostic code namespace")
    return {"register_index": register_index(registers, regions, catalog, spec["instances"], mpw),
            "sources": sorted(dependencies(spec)),
            "codes": [code_group(root, row) for row in spec["codes"]],
            "status_registers": status_registers(spec["status_registers"], registers),
            "boot": boot_status(root, spec["boot"]),
            "verification": release_evidence(root, spec, revision, support)}
