"""Source-bound runtime, Linux handoff and application diagnostic publication data."""
from __future__ import annotations

import copy
import re
from pathlib import Path

from publications.implementation_reference import without_comments


def dependencies(spec: dict) -> set[str]:
    paths = set(spec.get("sources", []))
    paths.update(spec.get("runtime_profiles", []))
    for row in spec.get("bindings", []):
        paths.add(row["file"])
    for app in spec.get("applications", []):
        paths.add(app["source"])
        paths.update(app["profiles"])
    return paths


def function_body(source: str, name: str) -> str:
    source = without_comments(source)
    matches = list(re.finditer(r"(?:^|(?<=[;}]))[ \t]*(?:[A-Za-z_]\w*[ \t*]+)+" + re.escape(name)
                              + r"\s*\([^;{}]*\)\s*\{", source, re.M))
    if len(matches) != 1:
        raise ValueError(f"missing or ambiguous software function: {name}")
    start = matches[0].end()
    # Quoted braces must not terminate a C function body.
    masked = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', lambda m: " " * len(m[0]), source)
    depth = 1
    for offset in range(start, len(masked)):
        depth += (masked[offset] == "{") - (masked[offset] == "}")
        if depth == 0:
            return source[start:offset]
    raise ValueError(f"unterminated software function: {name}")


def validate_bindings(root: Path, spec: dict) -> None:
    for relative in dependencies(spec):
        path = root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("software publication source escapes repository")
        if not path.is_file():
            raise ValueError(f"missing software publication source: {relative}")
    for row in spec["bindings"]:
        source = (root / row["file"]).read_text(encoding="utf-8")
        if row.get("function"):
            source = function_body(source, row["function"])
        def compact(s: str) -> str:
            return re.sub(r"\s+", "", without_comments(s))
        if compact(row["text"]) not in compact(source):
            raise ValueError(f"software source binding changed: {row['id']}")


def assignment(source: str, name: str) -> str:
    matches = re.findall(r"^" + re.escape(name) + r"\s*:?=\s*([^#\n]+)", source, re.M)
    if len(matches) != 1:
        raise ValueError(f"missing or duplicate profile value: {name}")
    value = matches[0].strip()
    if "$" in value:
        raise ValueError("software profile requires a literal committed value")
    return value


def runtime_profiles(root: Path, spec: dict) -> list[dict]:
    rows = []
    for relative in spec["runtime_profiles"]:
        source = (root / relative).read_text(encoding="utf-8")
        values = {key: assignment(source, key) for key in ("APP", "HAVE_CSR", "ISA", "LINK_TYPE")}
        app = values["APP"]
        makefile = (root / f"app/apps/{app}/app.mk").read_text(encoding="utf-8")
        override = re.findall(r"^APP_CRT_SRCS\s*\+=\s*\$\(ROOT_PATH\)/([^\s]+)\s*$", makefile, re.M)
        if len(override) > 1:
            raise ValueError("unsupported multiple application CRT overrides")
        startup = override[0] if override else "crt/arch/riscv/startup.S"
        if startup not in dependencies(spec) or f"crt/linker/{values['LINK_TYPE']}.lds" not in dependencies(spec):
            raise ValueError("startup or linker source missing from software inventory")
        rows.append({"profile": relative, "app": app, "isa": values["ISA"], "have_csr": values["HAVE_CSR"],
                     "link_type": values["LINK_TYPE"], "startup": startup,
                     "irq_runtime": "Included by generic CRT selection" if values["HAVE_CSR"] == "YES" and not override
                     else "Not included by this startup selection"})
    return rows


def irq_support(root: Path) -> dict:
    source = (root / "crt/src/core/system_irq_handler.c").read_text(encoding="utf-8")
    enable = function_body(source, "rs_irq_enable_core")
    supported = re.findall(r"case\s+(IRQ_\w+)\s*:", enable)
    if supported != ["IRQ_M_SOFT", "IRQ_M_TIMER"] or "return RS_ENOTSUP;" not in enable:
        raise ValueError("core IRQ enable support changed")
    external = function_body(source, "rs_irq_register_external")
    if re.findall(r"return\s+(RS_\w+)\s*;", external) != ["RS_EINVAL", "RS_ENOTSUP"]:
        raise ValueError("external IRQ registration behavior changed")
    counts = dict(re.findall(r"^#define\s+(RS_(?:EXCEPTION|CORE_IRQ|EXTERNAL_IRQ)_COUNT)\s+(\d+)U", source, re.M))
    if set(counts) != {"RS_EXCEPTION_COUNT", "RS_CORE_IRQ_COUNT", "RS_EXTERNAL_IRQ_COUNT"}:
        raise ValueError("missing runtime handler-table limits")
    return {"enabled_core_causes": supported, "counts": {k: int(v) for k, v in counts.items()}}


def application_diagnostics(root: Path, app: dict) -> dict:
    body = function_body((root / app["source"]).read_text(encoding="utf-8"), "main")
    calls = list(re.finditer(r"rs_test_finish\(\s*(RS_TEST_FAILED|RS_TEST_PASSED)\s*,\s*(\d+)U\s*\)", body))
    outcomes = [(m.start(), "test-fail" if m[1] == "RS_TEST_FAILED" else "test-pass", int(m[2])) for m in calls]
    returns = list(re.finditer(r"\breturn\s+(\d+)\s*;", body))
    if len(re.findall(r"\breturn\s+", body)) != len(returns):
        raise ValueError("unsupported application return expression")
    if not calls or not returns or int(returns[-1][1]) != 0 or returns[-1].start() < calls[-1].end():
        raise ValueError("unexpected diagnostic terminal/return arrangement")
    outcomes += [(m.start(), "return", int(m[1])) for m in returns[:-1]]
    outcomes.sort()
    stages = app["stages"]
    if len({row["id"] for row in stages}) != len(stages):
        raise ValueError("duplicate diagnostic application stage")
    if [(kind, code) for _, kind, code in outcomes] != [(row["kind"], row["code"]) for row in stages]:
        raise ValueError(f"application result branches changed: {app['id']}")
    previous = 0
    rows = []
    for (position, kind, value), stage in zip(outcomes, stages, strict=True):
        segment = body[previous:position]
        if stage["trigger"] not in re.sub(r"\s+", "", segment):
            raise ValueError(f"application stage condition changed: {app['id']}/{stage['id']}")
        previous = position
        if not stage.get("coverage") or not stage.get("boundary"):
            raise ValueError("diagnostic application stage lacks coverage boundary")
        label = "C return" if kind == "return" else "TEST_STATUS pass" if kind == "test-pass" else "TEST_STATUS fail"
        rows.append({**stage, "result": f"{label}: {value}", "order": len(rows) + 1})
    # Keep repeated values as separate stages; they are not global hardware enums.
    return {**copy.deepcopy(app), "stages": rows}


def linux_platform(root: Path) -> dict:
    dts = (root / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8")
    platform = (root / "app/ports/linux/opensbi/retrosoc_hp/platform.c").read_text(encoding="utf-8")
    def dt_value(key: str) -> int:
        matches = re.findall(re.escape(key) + r"\s*=\s*<\s*(0x[\da-fA-F]+|\d+)\s*>", dts)
        if len(matches) != 1:
            raise ValueError(f"missing or ambiguous platform property: {key}")
        return int(matches[0], 0)
    harts = re.findall(r"cpu@([\da-fA-F]+)\s*\{", dts)
    hart_ids = re.findall(r"s_hart_index_to_id\[\]\s*=\s*\{\s*(\d+)U\s*\}", platform)
    cpu = re.findall(r"cpu@1\s*\{(.*?)hp_cpu_intc:", dts, re.S)
    if harts != ["1"] or hart_ids != ["1"] or len(cpu) != 1 or not re.search(r"\breg\s*=\s*<1>\s*;", cpu[0]):
        raise ValueError("Linux/OpenSBI hart identity changed")
    timebase = dt_value("timebase-frequency")
    mtimer = re.findall(r"\.mtime_freq\s*=\s*(\d+)UL", platform)
    if mtimer != [str(timebase)]:
        raise ValueError("Linux/OpenSBI timebase mismatch")
    profile = (root / "configs/ci/ihp130-hp.mk").read_text(encoding="utf-8")
    if timebase != int(assignment(profile, "CLINT_TIMEBASE_HZ")):
        raise ValueError("Linux timer declaration differs from the selected HP profile")
    memory = re.findall(r"memory@38000000\s*\{[^}]*reg\s*=\s*<(0x[\da-fA-F]+)\s+(0x[\da-fA-F]+)>", dts)
    if len(memory) != 1:
        raise ValueError("missing reviewed Linux memory envelope")
    bootargs = re.findall(r'bootargs\s*=\s*"([^"\n]+)"', dts)
    if len(bootargs) != 1:
        raise ValueError("missing Linux boot arguments")
    clocks = re.findall(r"clock-frequency\s*=\s*<(\d+)>", dts)
    if len(clocks) != 2 or len(set(clocks)) != 1:
        raise ValueError("CPU and UART device-tree clock declarations disagree")
    if dt_value("linux,initrd-start") != dt_value("linux,initrd-end"):
        raise ValueError("reviewed initrd template placeholder changed")
    ready = (root / "app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp").read_text(encoding="utf-8")
    writes = [(int(a, 0), int(v, 0)) for a, v in re.findall(r"^\s*devmem\s+(0x[\da-fA-F]+)\s+32\s+(0x[\da-fA-F]+)", ready, re.M)]
    expected = [(0x10019020, 1), (0x10019024, 0x4C4E5801), (0x10019028, 1), (0x1001902C, 1)]
    if writes != expected:
        raise ValueError("Linux ready mailbox sequence changed")
    if ready.find('echo "retroSoC HP Linux ready"') < 0 or ready.index('echo "retroSoC HP Linux ready"') > ready.index("devmem"):
        raise ValueError("Linux ready message/publication order changed")
    return {"hart_id": 1, "timebase_hz": timebase, "clock_hz": int(clocks[0]),
            "cbom_bytes": dt_value("riscv,cbom-block-size"), "memory_base": memory[0][0],
            "memory_bytes": int(memory[0][1], 0), "initrd_start": dt_value("linux,initrd-start"),
            "initrd_template_end": dt_value("linux,initrd-end"), "bootargs": bootargs[0],
            "ready_writes": [{"address": f"0x{a:08X}", "value": f"0x{v:08X}"} for a, v in writes]}


def collect_software(root: Path, spec: dict) -> dict:
    validate_bindings(root, spec)
    ids = [app["id"] for app in spec["applications"]]
    if ids != ["bringup", "ci_smoke"]:
        raise ValueError("software diagnostic application coverage changed")
    return {**copy.deepcopy(spec), "sources": sorted(dependencies(spec)), "profiles": runtime_profiles(root, spec),
            "irq": irq_support(root), "platform": linux_platform(root),
            "applications": [application_diagnostics(root, app) for app in spec["applications"]]}
