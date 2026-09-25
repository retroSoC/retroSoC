#!/usr/bin/env python3
"""CRYPTO-P0 evidence entry points; never modify production RTL or HAL."""

from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.crypto_constants import pack, validate  # noqa: E402


BASELINE = "92830d963da2f1e39bb219c0d377bc4889c07755"
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
CRYPTO = ROOT / "rtl/ip/security"
RTL = [ROOT / "rtl" / line.lstrip("/") for line in
       (ROOT / "rtl/mini/filelist/ip.fl").read_text().splitlines()
       if line.startswith("/ip/security/crypto_") or line == "/ip/security/apb4_crypto.sv"]
INTERFACES = [COMMON / "interface/apb4_if.sv", COMMON / "interface/axi4_stream_if.sv"]
UTILITIES = [COMMON / "utils/register.sv", COMMON / "utils/fifo.sv"]
V2_OFFSETS = {"MEM_STATUS": 0x28, "MEM_CONTROL": 0x2C, "TABLE_ID": 0x30,
              "TABLE_WORDS": 0x34, "TABLE_DATA": 0x38, "TABLE_CRC": 0x3C,
              "MEM_ERROR": 0x40, "MEM_CYCLES": 0x44}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def oracle():
    spec = importlib.util.spec_from_file_location("crypto_p0_reference", ROOT / "tests/crypto_reference.py")
    if spec is None or spec.loader is None:
        raise ValueError("independent oracle unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def identity(variant: Path) -> dict:
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["configuration"]["PDK"] != "IHP130" or manifest["profile"] != "ihp130":
        raise ValueError("CRYPTO-P0 baseline requires configs/ci/ihp130.mk")
    sources = [*RTL, *INTERFACES, *UTILITIES, ROOT / "rtl/tech/tc_sram.sv",
               ROOT / "crt/include/retrosoc/hal/crypto_regs.h", ROOT / "crt/src/hal/crypto.c"]
    production = {str(p.relative_to(ROOT)): digest(p) for p in sources}
    matching = all(hashlib.sha256(subprocess.check_output(
        ["git", "show", f"{BASELINE}:{p.relative_to(ROOT)}"], cwd=ROOT
    )).hexdigest() == digest(p) for p in RTL)
    return {"schema_version": 1, "baseline_revision": BASELINE,
            "production_rtl_matches_baseline": matching, "production_sha256": production,
            "manifest": manifest, "driver_sha256": digest(Path(__file__)),
            "constants_generator_sha256": digest(ROOT / "scripts/crypto_constants.py"),
            "oracle_sha256": digest(ROOT / "tests/crypto_reference.py")}


def execute(directory: Path, name: str, command: list[str], *, timeout: int = 1800,
            env: dict[str, str] | None = None, marker: str | None = None) -> dict:
    missing = shutil.which(command[0])
    if missing is None:
        raise FileNotFoundError(f"required tool missing: {command[0]}")
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / f"{name}.log"
    result = directory / f"{name}.json"
    flow = [sys.executable, str(ROOT / "scripts/run_flow.py"), "--tool", name,
            "--log", str(log), "--result", str(result), "--cwd", str(ROOT)]
    for key, value in (env or {}).items():
        flow += ["--env", f"{key}={value}"]
    flow += ["--", "timeout", "--foreground", "--kill-after=5s", f"{timeout}s", *command]
    run = subprocess.run(flow, cwd=ROOT, check=False)
    evidence = json.loads(result.read_text())
    if run.returncode or evidence["status"] != "passed":
        raise RuntimeError(f"{name}: see {result}")
    if marker:
        checked = subprocess.run([sys.executable, str(ROOT / "scripts/check_simulation.py"),
            "--log", str(log), "--result", str(directory / f"{name}-check.json"),
            "--require", marker], check=False)
        if checked.returncode:
            raise RuntimeError(f"{name}: simulation verdict rejected {log}")
    return {"result": str(result), "log": str(log), "marker": marker,
            "duration_seconds": evidence["duration_seconds"],
            "peak_rss_kib": evidence["peak_rss_kib"]}


def constants(variant: Path, output: Path) -> None:
    payload = pack(ROOT)
    mathematical = oracle().constant_image()
    if payload != mathematical or payload != pack(ROOT):
        raise ValueError("independent image/packing/reproducibility mismatch")
    data = validate(payload)
    # Exercise rejection of corruption in both used and padding regions.
    for index in (0, 1023, 2048, 4095, 4096, 8191):
        bad = bytearray(payload)
        bad[index] ^= 1
        try:
            validate(bytes(bad))
        except ValueError:
            continue
        raise ValueError(f"corruption accepted at byte {index}")
    output.mkdir(parents=True, exist_ok=True)
    (output / "crypto.cryc").write_bytes(payload)
    words = [int.from_bytes(payload[i:i + 4], "little") for i in range(0, 8192, 4)]
    (output / "crypto_constants.inc").write_text(
        "/* Generated public CRYC1 image. */\n" +
        "\n".join(f"UINT32_C(0x{value:08x})," for value in words) + "\n")
    dump(output / "constants.json", {**identity(variant), **data, "status": "passed",
         "independent_oracle": "GF(2^8) AES, exact integer prime-root SHA",
         "corruption_cases": 6, "expected_v2_offsets": V2_OFFSETS,
         "v2_implementation": "NOT_RUN (P1)", "planned_physical_banks": 6,
         "planned_physical_bytes": 24576, "allowed_inferred_fifo_bits": 1184,
         "v2_contract": {"ip_version": "0x00020000", "layout_id": "0x43525901",
             "mem_status_reset": 4, "status_reset": 8, "memory_irq_bit": 5,
             "memory_error_bit": 4, "scrub_max_cycles": 2056,
             "verify_max_cycles": 8192, "apb_max_wait_cycles": 4}})


def parity() -> dict:
    # Read-only V1 mirror validation, separate from Pytest execution.
    sv = (CRYPTO / "crypto_define.svh").read_text()
    header = (ROOT / "crt/include/retrosoc/hal/crypto_regs.h").read_text()
    offsets = dict(re.findall(r"`define\s+APB4_CRYPTO__(\w+)\s+12'h([0-9a-fA-F]+)", sv))
    checked = 0
    for name, value in offsets.items():
        match = re.search(r"#define\s+RS_CRYPTO_REG_" + name + r"\s+UINT32_C\((0x[0-9a-fA-F]+)\)", header)
        if match is None or int(match[1], 16) != int(value, 16):
            raise ValueError(f"V1 offset parity: {name}")
        checked += 1
    if checked < 40:
        raise ValueError("V1 offset inventory incomplete")
    # Read the existing handwritten mapping as data; do not invoke Pytest/tests.
    tree = ast.parse((ROOT / "tests/test_crypto_register_parity.py").read_text())
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and
                    n.name == "test_crypto_register_fields_match_rtl")
    literals = {n.targets[0].id: ast.literal_eval(n.value) for n in function.body
                if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                and n.targets[0].id in ("mapping", "shift_names")}
    for rtl_name, c_name in literals["mapping"].items():
        bit = re.search(r"`define\s+" + rtl_name + r"\s+(\d+)\s*$", sv, re.M)
        value = re.search(r"#define\s+" + c_name +
                          r"\s+(?:UINT32_C\((0x[0-9a-fA-F]+)\)|(\d+)U)", header)
        if bit is None or value is None:
            raise ValueError(f"missing parity field {rtl_name}/{c_name}")
        expected = int(bit[1]) if c_name in literals["shift_names"] else 1 << int(bit[1])
        actual = int(value[1], 16) if value[1] else int(value[2])
        if actual != expected:
            raise ValueError(f"V1 field parity: {rtl_name}/{c_name}")
    return {"offsets_checked": checked, "fields_checked": len(literals["mapping"]),
            "v2_offsets_reserved_in_spec": V2_OFFSETS}


def rtl(variant: Path, output: Path, jobs: int, selected: str | None = None) -> None:
    report = {**identity(variant), "status": "running", "cases": [], "parity": parity()}
    report_path = output / (f"functional-{selected}.json" if selected else "functional.json")
    dump(report_path, report)
    cases = [("crypto_primitive_tb", "Crypto AES and SHA primitive tests passed"),
             ("crypto_engine_tb", "Crypto streaming engine tests passed"),
             ("crypto_apb_tb", "Crypto APB register tests passed"),
             ("crypto_rsa_tb", "Crypto RSA Montgomery tests passed"),
             ("crypto_vectors_p0_tb", "CRYPTO_P0_VECTORS_PASS"),
             ("crypto_dma_p0_tb", "CRYPTO_P0_DMA_PASS"),
             ("crypto_rsa2048_tb", "CRYPTO_P0_RSA2048_PASS")]
    try:
        sha_vector = output / "sha-padding.hex"
        sha_vector.write_text("\n".join(
            ((hashlib.sha224(bytes(range(n))).hexdigest() + "00000000") if mode == 0 else
             hashlib.sha256(bytes(range(n))).hexdigest()) for mode in (0, 1)
            for n in (0, 1, 3, 55, 56, 63, 64, 65, 127, 128, 129)) + "\n")
        fixture = oracle().rsa_fixture()
        dump(output / "rsa2048-public-fixture.json", {k: hex(v) for k, v in fixture.items()})
        vector = output / "rsa2048.hex"
        vector.write_text("\n".join(f"{fixture[k]:0512x}" for k in
            ("modulus", "private", "message", "ciphertext", "n0_prime", "montgomery")) + "\n")
        for top, marker in cases:
            if selected is not None and top != selected:
                continue
            case = output / "rtl" / top
            case.mkdir(parents=True, exist_ok=True)
            sources = [*INTERFACES, *UTILITIES, *[p for p in RTL if p.suffix == ".sv"]]
            includes = [CRYPTO, COMMON, COMMON / "interface"]
            if top == "crypto_dma_p0_tb":
                generated = case / "memory_map"
                execute(case, "memory-map", [sys.executable, str(ROOT / "scripts/rtl/generate_memory_map.py"),
                        "--map", str(ROOT / "rtl/mini/address_map/memory_map.json"),
                        "--output-dir", str(generated), "--have-sram-if", "NO"])
                includes += [generated / "rtl", COMMON / "stream", COMMON / "utils"]
                sources = [COMMON / "interface/axi4_if.sv", *sources,
                           COMMON / "stream/round_robin_arbiter.sv"]
                sources += [ROOT / "rtl/ip/peripheral" / n for n in
                            ("dma_pkg.sv", "dma_req_if.sv", "dma_axi4_master.sv", "dma_core.sv")]
            sources.append(ROOT / "tests/rtl" / f"{top}.sv")
            if top == "crypto_rsa2048_tb":
                (case / "ccache-tmp").mkdir(exist_ok=True)
                execute(case, "compile", ["verilator", "--binary", "--timing", "-Wno-fatal",
                        "--top-module", top, "--Mdir", str(case / "obj"), "-j", str(jobs),
                        *[f"-I{p}" for p in includes], *map(str, sources)],
                        env={"CCACHE_DIR": str(case / "ccache"), "CCACHE_TEMPDIR": str(case / "ccache-tmp")})
                command = [str(case / "obj" / f"V{top}"), f"+vectors={vector}"]
            else:
                fl = case / "sources.fl"
                fl.write_text("+define+SV_ASSRT_DISABLE\n" +
                              "\n".join([*[f"+incdir+{p}" for p in includes], *map(str, sources)]) + "\n")
                converted = case / "test.v"
                execute(case, "convert", [sys.executable, str(ROOT / "scripts/rtl/convt_sv2v.py"),
                        "-f", str(fl), "--output", str(converted)])
                binary = case / "test.vvp"
                execute(case, "compile", ["iverilog", "-g2012", "-s", top,
                        "-o", str(binary), str(converted)])
                command = ["vvp", str(binary)]
                if top == "crypto_vectors_p0_tb":
                    command.append(f"+sha={sha_vector}")
            evidence = execute(case, "simulation", command, marker=marker)
            report["cases"].append({"top": top, "status": "passed",
                "testbench_sha256": digest(ROOT / "tests/rtl" / f"{top}.sv"), **evidence})
            dump(report_path, report)
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        dump(report_path, report)
        cycles = []
        for case in report["cases"]:
            cycles += [{"operation": op, "cycles": int(count), "log": case["log"]} for op, count in
                       re.findall(r"CRYPTO_CYCLES operation=(\w+) cycles=(\d+)", Path(case["log"]).read_text())]
        sha_cycles = []
        for case in report["cases"]:
            sha_cycles += [{"sha256": bool(int(mode)), "bytes": int(size), "cycles": int(count)}
                for mode, size, count in re.findall(r"CRYPTO_SHA_CASE mode=(\d) bytes=(\d+) cycles=(\d+)",
                                                    Path(case["log"]).read_text())]
        dump(output / (f"cycles-{selected}.json" if selected else "cycles.json"),
             {"status": report["status"], "measurements": cycles, "sha_padding": sha_cycles,
                                     "scope": "V1 baseline, not V2 latency qualification"})


def number(value: int | str) -> int:
    return value if isinstance(value, int) else int(value, 2)


def synthesis_metrics(report_dir: Path) -> dict:
    work = report_dir.parent
    area_path = report_dir / "apb4_crypto_area.json"
    # Yosys -t also prefixes tee/stat JSON. Keep the original and normalize
    # only for parsing; write_json checkpoints themselves have no log prefix.
    area = json.loads(re.sub(r"^\[\d+\.\d+\] ", "", area_path.read_text(), flags=re.M))
    perf_path = work / "yosys-perf.json"
    perf = json.loads(perf_path.read_text())
    log = (work / "yosys.log").read_text()
    headers = [(float(t), name) for t, name in re.findall(
        r"^\[(\d+\.\d+)\] \d+\. Executing (\w+)", log, re.M)]
    timings = {}
    for (start, name), (end, _) in zip(headers, headers[1:]):
        if name in ("MEMORY", "OPT_DFF", "TECHMAP", "ABC"):
            timings[name.lower()] = round(end - start, 6)
    design = area["design"]
    return {"mapped_cells": design["num_cells"], "area_um2": design["area"],
            "sequential_area_um2": design["sequential_area"],
            "cell_types": design["num_cells_by_type"], "phase_wall_seconds": timings,
            "yosys_exclusive_pass_seconds": {k: v["runtime_ns"] / 1e9 for k, v in perf["passes"].items()},
            "timing_note": "MEMORY command exclusive time excludes its child passes; use phase_wall_seconds",
            "raw_area": str(area_path), "raw_perf": str(perf_path),
            "yosys_result": json.loads((work / "yosys.json").read_text()),
            "warnings": [line for line in log.splitlines() if "Warning:" in line]}


def inventory(path: Path) -> dict:
    design = json.loads(path.read_text())
    modules = design["modules"]
    rows = []
    macros: dict[str, int] = {}

    def visit(name: str, instance: str, ancestors: tuple[str, ...]) -> None:
        if name in ancestors:
            raise ValueError("recursive synthesis hierarchy")
        module = modules[name]
        cells = module.get("cells", {})
        writes = {c["parameters"]["MEMID"].lstrip("\\") for c in cells.values()
                  if c["type"].startswith("$memwr")}
        memories = []
        for mem_name, mem in module.get("memories", {}).items():
            ports = [c for c in cells.values() if c["type"].startswith("$mem") and
                     c.get("parameters", {}).get("MEMID", "").lstrip("\\") == mem_name.lstrip("\\")]
            memories.append({"name": mem_name, "width": mem["width"], "depth": mem["size"],
                "bits": mem["width"] * mem["size"],
                "read_ports": sum(c["type"].startswith("$memrd") for c in ports),
                "write_ports": sum(c["type"].startswith("$memwr") for c in ports),
                "source": mem.get("attributes", {}).get("src"),
                "kind": "ram" if mem_name.lstrip("\\") in writes else "rom"})
        for cell_name, cell in cells.items():
            if cell["type"] in ("$mem", "$mem_v2"):
                p = cell["parameters"]
                memories.append({"name": cell_name, "width": number(p["WIDTH"]),
                    "depth": number(p["SIZE"]), "bits": number(p["WIDTH"]) * number(p["SIZE"]),
                    "read_ports": number(p["RD_PORTS"]), "write_ports": number(p["WR_PORTS"]),
                    "kind": "ram" if number(p["WR_PORTS"]) else "rom"})
        register_bits = sum(number(c["parameters"]["WIDTH"]) for c in cells.values()
                            if re.match(r"\$(?:a|s|al)?dff", c["type"]) and "WIDTH" in c["parameters"])
        rows.append({"instance": instance, "module": name, "memories": memories,
                     "inferred_bits": sum(m["bits"] for m in memories),
                     "register_bits": register_bits, "local_cells": len(cells),
                     "registers": [{"cell": n, "type": c["type"], "bits": number(c["parameters"]["WIDTH"]),
                                    "source": c.get("attributes", {}).get("src")}
                                   for n, c in cells.items() if re.match(r"\$(?:a|s|al)?dff", c["type"])
                                   and "WIDTH" in c["parameters"]],
                     "mux_cells": sum("mux" in c["type"].lower() for c in cells.values())})
        for child, cell in cells.items():
            cell_type = cell["type"]
            if cell_type.startswith("RM_IHPSG13_"):
                macros[cell_type] = macros.get(cell_type, 0) + 1
            elif cell_type in modules and not number(modules[cell_type].get("attributes", {}).get("blackbox", 0)):
                visit(cell_type, instance + "." + child, (*ancestors, name))
    visit("apb4_crypto", "apb4_crypto", ())
    return {"path": str(path), "sha256": digest(path), "rows": rows, "macros": macros,
            "inferred_bits": sum(r["inferred_bits"] for r in rows),
            "register_bits": sum(r["register_bits"] for r in rows),
            "ram_bits": sum(m["bits"] for row in rows for m in row["memories"] if m["kind"] == "ram"),
            "rom_bits": sum(m["bits"] for row in rows for m in row["memories"] if m["kind"] == "rom"),
            "register_bits_scope": "generic RTLIL FFs before library mapping; not mapped standard cells"}


def synth(variant: Path, output: Path) -> None:
    ident = identity(variant)
    cfg = ident["manifest"]["configuration"]
    if not ident["production_rtl_matches_baseline"]:
        raise ValueError("P0 baseline RTL differs from the frozen baseline revision")
    if (cfg["HAVE_SRAM_MACRO"] != "YES" or cfg["PDK_BEHAV"] != "NO" or
            cfg["SYNTH"] != "YOSYS" or cfg["SYNTH_RECIPE"] != "balanced"):
        raise ValueError("baseline requires macros YES, PDK_BEHAV NO, SYNTH YOSYS, balanced recipe")
    # Every attempt gets fresh outputs: a new timeout must never inherit an
    # older successful netlist/checkpoint. The report records the exact paths.
    work = Path(tempfile.mkdtemp(prefix="synth-", dir=output))
    for name in ("out", "tmp", "rpt"):
        (work / name).mkdir(parents=True, exist_ok=True)
    fl = work / "crypto.fl"
    fl.write_text("+define+PDK_IHP130\n+define+HAVE_SRAM_MACRO\n+define+SYNTHESIS\n+define+SV_ASSRT_DISABLE\n" +
                  f"+incdir+{CRYPTO}\n+incdir+{COMMON}\n" + f"+incdir+{COMMON / 'interface'}\n" +
                  "\n".join(map(str, [*INTERFACES, *UTILITIES, ROOT / "rtl/tech/tc_sram.sv",
                                     *[p for p in RTL if p.suffix == ".sv"]])) + "\n")
    directory = ROOT / "physical/smoke/syn/yosys/script"
    period = subprocess.check_output([sys.executable, str(ROOT / "scripts/yosys_period.py"),
        "--domains", str(ROOT / "rtl/mini/integration/clock_reset_domains.json"), "--domain", "pclk"], text=True).strip()
    env = {"PDK": "IHP130", "SOC": "MINI", "SYNTH_RECIPE": "balanced", "HAVE_SRAM_MACRO": "YES",
           "SRAM_SIZE_KIB": "32", "SV_FLIST": str(fl), "TOP_DESIGN": "apb4_crypto",
           "PROJ_NAME": "apb4_crypto", "WORK": str(work / "tmp"), "BUILD": str(work / "out"),
           "REPORTS": str(work / "rpt"), "NETLIST": str(work / "out/crypto.v"),
           "CONFIG": str(work / "out/crypto.config"), "YOSYS_TARGET_PERIOD_PS": period,
           "YOSYS_FLATTEN_HIER": "1", "YOSYS_KEEP_HIER_INST": '"t:tc_sram*$*"',
           "YOSYS_REPORT_INSTS": ""}
    report = {**ident, "status": "running", "scope": "crypto_block", "environment": env,
              "recipe_sha256": {p.name: digest(p) for p in
                  (directory / "synth.tcl", directory / "abc_balanced.script", directory / "crypto_block_synth.tcl")}}
    dump(output / "baseline-synthesis.json", report)
    try:
        report["flow"] = execute(work, "yosys", ["yosys", "-t", "--perffile", str(work / "yosys-perf.json"),
            "-c", str(directory / "crypto_block_synth.tcl")], timeout=10800, env=env)
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        dump(output / "baseline-synthesis.json", report)
        inventories = {p.stem: inventory(p) for p in (work / "rpt").glob("*_design.json")}
        dump(output / "storage-inventory.json", {**ident, "status": report["status"],
              "checkpoints": inventories, "candidate": "NOT_RUN (P1)", "whole_soc": "NOT_RUN"})


def report_all(variant: Path, output: Path) -> None:
    current = identity(variant)
    stages = {}
    for name in ("constants", "functional", "cycles", "baseline-synthesis", "storage-inventory"):
        path = output / f"{name}.json"
        stages[name] = json.loads(path.read_text()) if path.exists() else {"status": "NOT_RUN"}
    for name in ("constants", "functional", "baseline-synthesis", "storage-inventory"):
        if stages[name].get("status") == "passed" and (
            stages[name].get("production_sha256") != current["production_sha256"] or
            stages[name].get("manifest", {}).get("configuration") != current["manifest"]["configuration"]
        ):
            stages[name] = {"status": "stale", "reason": "source/config identity mismatch"}
    if stages["functional"].get("status") == "passed":
        cases = stages["functional"].get("cases", [])
        if len(cases) != 7:
            stages["functional"]["status"] = "incomplete"
        for case in cases:
            source = ROOT / "tests/rtl" / f"{case['top']}.sv"
            if case.get("testbench_sha256") != digest(source):
                stages["functional"]["status"] = "stale"
    # Refresh inventory from this attempt's checkpoints, without rerunning
    # synthesis. Partial data is useful but can never pass the aggregate gate.
    baseline = stages["baseline-synthesis"]
    if baseline.get("environment"):
        required = ("initial_design", "pre_memory_design", "pre_sat_design", "post_sat_design", "mapped_design")
        files = [Path(baseline["environment"]["REPORTS"]) / f"{name}.json" for name in required]
        complete = baseline.get("status") == "passed" and all(p.is_file() for p in files)
        stages["storage-inventory"] = {**current, "status": "passed" if complete else "incomplete",
            "checkpoints": {p.stem: inventory(p) for p in files if p.is_file()},
            "missing_checkpoints": [p.stem for p in files if not p.is_file()],
            "candidate": "NOT_RUN (P1)", "whole_soc": "NOT_RUN"}
        dump(output / "storage-inventory.json", stages["storage-inventory"])
        if complete:
            baseline["metrics"] = synthesis_metrics(Path(baseline["environment"]["REPORTS"]))
            dump(output / "baseline-synthesis.json", baseline)
    passed = all(r.get("status") == "passed" for r in stages.values())
    dump(output / "p0-report.json", {**current, "status": "passed" if passed else "incomplete",
         "stages": stages, "pytest": "NOT_RUN (maintainer instruction)",
         "v2_lifecycle_and_hardware": "NOT_RUN (P1)", "physical_qualification": "NOT_RUN (P2)",
         "known_v1_limitations": ["ZEROIZED is command acknowledgement, not SRAM erase completion",
             "HAL AES_KEY_STATUS check uses the AES_STATUS mask", "Common FIFO flush retains payload"]})
    if not passed:
        raise ValueError("P0 evidence incomplete; see p0-report.json")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("constants", "rtl", "synth", "report"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--case", choices=("crypto_vectors_p0_tb", "crypto_rsa2048_tb", "crypto_dma_p0_tb"))
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    output = variant / "crypto/p0"
    output.mkdir(parents=True, exist_ok=True)
    try:
        if args.stage == "rtl":
            rtl(variant, output, args.jobs, args.case)
        else:
            {"constants": constants, "synth": synth, "report": report_all}[args.stage](variant, output)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"CRYPTO-P0 {args.stage}: {error}\n")


if __name__ == "__main__":
    main()
