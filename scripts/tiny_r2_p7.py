#!/usr/bin/env python3
"""P7 structural clock/macro evidence; separate from the frozen P1 audit."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as b  # noqa: E402
from scripts.config_key import variant_id  # noqa: E402
from scripts.tiny_ics55_platform import expand_netlist, inspect_clock_source  # noqa: E402

PHASE = "TINY-R2-P7"
RAM_TYPES = {"ICS55": ("ics55_ecos_sram_1024x32_m8", "CLK"),
             "IHP130": ("RM_IHPSG13_1P_1024x32_c2_bm_bist", "A_CLK")}


def inspect_netlist(document: dict, pdk: str) -> dict:
    modules, top, leaves, canonical, boundaries = expand_netlist(document)

    def boundary(suffix: str, kind: str) -> dict:
        found = [cell for name, cell in boundaries.items()
                 if name.replace("/", ".").endswith("." + suffix)
                 and cell["type"].split("$")[0] == kind]
        if len(found) != 1:
            raise ValueError(f"missing or ambiguous P7 clock boundary: {suffix}")
        return found[0]

    def pin(cell: dict, name: str) -> str:
        bits = cell["ports"].get(name, [])
        if len(bits) != 1 or bits[0] in ("0", "1", "x", "z"):
            raise ValueError(f"missing/constant P7 clock: {cell['path']}/{name}")
        return bits[0]

    root = boundary("u_soc.u_clock_backend.u_sys_mux", "safe_clock_mux")
    memory = boundary("u_soc.u_clock_backend.u_mem_mux", "safe_clock_mux")
    peripheral = boundary("u_soc.u_clock_backend.u_pclk_mux", "safe_clock_mux")
    cpu_gate = boundary("u_soc.u_cpu.u_cpu_gate", "tiny_clock_gate")
    crypto_gate = boundary("u_soc.u_crypto_lifecycle", "tiny_peripheral_leaf")
    sys_clock = pin(root, "clk_o")
    pclk = pin(peripheral, "clk_o")
    if pin(cpu_gate, "clk_i") != sys_clock or pin(memory, "clk0_i") != sys_clock:
        raise ValueError("CPU gate/MEM source is not common SYS")
    if pin(crypto_gate, "clk_i") != pclk:
        raise ValueError("private Crypto storage gate is not sourced from PCLK")
    cpu_clock = pin(cpu_gate, "clk_o")
    crypto_clock = pin(crypto_gate, "clk_o")
    ram_type, ram_pin = RAM_TYPES[pdk]
    macros = [cell for cell in leaves if cell["type"] == ram_type]
    main_names = {f"u_soc.u_sram.gen_group[{g}].u_group.gen_bank[{n}].u_ram.u_mem"
                  for g in range(4) for n in range(8)}
    crypto_names = {f"u_soc.u_crypto.u_storage.gen_bank[{n}].gen_macro.u_sram.u_mem"
                    for n in range(6)}
    observed = set()
    for cell in macros:
        name = next((name for name in main_names | crypto_names
                     if cell["path"].replace("/", ".").endswith("." + name)), None)
        if name is None or name in observed:
            raise ValueError("extra, duplicated or renamed physical SRAM macro")
        observed.add(name)
        expected_clock = sys_clock if name in main_names else crypto_clock
        if pin(cell, ram_pin) != expected_clock:
            raise ValueError(f"physical SRAM clock mismatch: {name}")
    if len(macros) != 38 or observed != main_names | crypto_names:
        raise ValueError("P7 requires 32 main SRAM plus six private Crypto macros")
    cpu = [cell for cell in leaves if "u_hazard3_cpu_2port" in cell["path"]
           and ("CK" in cell["ports"] or "CKN" in cell["ports"] or "CLK" in cell["ports"])]
    if not cpu:
        raise ValueError("missing CPU clock endpoints")
    for cell in cpu:
        for name in ("CK", "CKN", "CLK"):
            if name in cell["ports"] and pin(cell, name) not in (sys_clock, cpu_clock):
                raise ValueError("CPU has an unapproved clock or a hidden divider")
    pll = [cell for cell in leaves if cell["type"] == "PLL_TOP"]
    if pdk == "ICS55":
        if len(pll) != 1 or pin(pll[0], "CKOUT1") != pin(root, "clk1_i"):
            raise ValueError("P7 requires one PLL CKOUT1 connected to the SYS mux")
        if pin(pll[0], "REFCLK") != pin(root, "clk0_i"):
            raise ValueError("PLL reference and safe SYS source differ")
        constants = {"0": 0, "1": 1}
        for cell in leaves:
            if cell["type"] in ("TIELOH7R", "TIEHIH7R"):
                for bit in cell["ports"]["Z"]:
                    constants[bit] = int(cell["type"] == "TIEHIH7R")
        if pll[0]["ports"].get("EN", ["x"])[0] in constants:
            raise ValueError("P7 PLL enable must be controlled, not tied on/off")
        external = modules[top]["ports"]["extclk_i_pad"]["bits"]
        if len(external) != 1:
            raise ValueError("missing external reference input")
        inspect_clock_source(leaves, pin(root, "clk0_i"),
                             canonical(f"{top}:{external[0]}"), constants)
    elif pll:
        raise ValueError("no-PLL compatibility instantiated a PLL")
    return {"system_clock": sys_clock, "memory_clock": pin(memory, "clk_o"),
            "peripheral_clock": pclk, "cpu_clock": cpu_clock,
            "main_macros": 32, "private_crypto_macros": 6, "pll_macros": len(pll),
            "cpu_clocked_cells": len(cpu), "macro_bindings": macros,
            "clock_boundaries": [root, memory, peripheral, cpu_gate, crypto_gate],
            "qualification": "structural domain binding only; no physical operating-point qualification"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("audit-netlist", "verify-netlist", "capture-source", "verify-source"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--netlist", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action in ("capture-source", "verify-source"):
            inputs = b.source_inputs(ROOT, "ICS55") | b.source_inputs(ROOT, "IHP130")
            for folder in ("tests", "configs/ci"):
                for path in (ROOT / folder).rglob("*"):
                    if path.is_file() and path.suffix in (".py", ".sv", ".svh", ".c", ".S", ".ld", ".mk"):
                        inputs[str(path.relative_to(ROOT))] = b.sha256(path)
            contract = b.artifact(ROOT / "docs/ip/tiny-soc.md")
            if args.action == "capture-source":
                if args.output.exists():
                    raise ValueError("source evidence already exists; use a new attempt instead of overwriting")
                b.dump(args.output, {"phase": PHASE, "repository": b.git_info(ROOT),
                                     "specification": contract, "source_inputs": inputs,
                                     "source_digest": b.digest_map(inputs), "tools": b.tools_identity(ROOT),
                                     "snapshot": b.snapshot(ROOT, args.output.parent / "source", inputs)})
            else:
                recorded = b.read_json(args.output)
                if (recorded.get("phase") != PHASE or recorded.get("source_inputs") != inputs or
                        recorded.get("specification") != contract):
                    raise ValueError("P7 sources changed after the retained source snapshot")
            print(f"{PHASE} {args.action}: PASS")
            return 0
        if args.netlist is None or args.config is None:
            raise ValueError("netlist actions require --netlist and --config")
        manifest = b.configuration(args.variant_root)
        pdk = manifest["configuration"]["PDK"]
        config = dict(line.split("=", 1) for line in args.config.read_text().splitlines() if "=" in line)
        for key, value in {"SOC": "TINY", "PDK": pdk,
                           "HAVE_PLL": "YES" if pdk == "ICS55" else "NO",
                           "HAVE_SRAM_MACRO": "YES", "SRAM_SIZE_KIB": "128",
                           "TOP_DESIGN": "retrosoc_tiny_asic", "PERIOD_PS": "41667"}.items():
            if config.get(key) != value:
                raise ValueError(f"P7 consumed configuration mismatch: {key}")
        values = [f"{k}={v}" for k, v in manifest["configuration"].items()
                  if k not in ("SIMU", "SYNTH", "SYNTH_RECIPE", "STA")]
        expected = variant_id(manifest["profile"], values,
                              ROOT / "dependencies/dependencies.lock.json",
                              "2000-01-01-00-00").rsplit("-", 1)[1]
        if config.get("CONFIG_DIGEST") != expected or args.variant_root.name.rsplit("-", 1)[1] != expected:
            raise ValueError("P7 consumed configuration digest mismatch")
        paths = (args.netlist, Path(str(args.netlist) + ".json"), args.config)
        if args.action == "audit-netlist" and not paths[1].is_file():
            # A mapped Verilog export is also a valid audit input. Serialize it
            # without optimization or remapping; retain the conversion result.
            # This supports the pre-P7 IHP130 recipe which did not emit JSON.
            flow = b.read_json(args.variant_root / "syn/yosys/result-synth.json")
            if flow.get("status") != "passed" or flow.get("exit_code") != 0:
                raise ValueError("cannot derive audit JSON from an unsuccessful synthesis")
            b.execute(ROOT, args.output.parent, "p7-netlist-json",
                      ["timeout", "--foreground", "120s", "yosys", "-Q", "-T", "-p",
                       f'read_verilog "{paths[0]}"; write_json "{paths[1]}"'], quiet=True)
        inputs = [b.artifact(path) for path in paths]
        auditors = [b.artifact(ROOT / "scripts" / name) for name in
                    ("tiny_r2_p7.py", "tiny_ics55_platform.py", "tiny_r2_baseline.py", "config_key.py")]
        if args.action == "audit-netlist":
            result = {"phase": PHASE, "status": "passed", "pdk": pdk,
                      "audit_scripts": auditors, "inputs": inputs,
                      "configuration": manifest["configuration"], "config_digest": expected,
                      "binding": inspect_netlist(json.loads(paths[1].read_text()), pdk)}
            b.dump(args.output, result)
        else:
            result = b.read_json(args.output)
            if (result.get("status") != "passed" or result.get("phase") != PHASE or
                    result.get("audit_scripts") != auditors or result.get("config_digest") != expected or
                    result.get("inputs") != inputs):
                raise ValueError("P7 structural evidence is missing, stale, or not passed")
    except (OSError, ValueError, KeyError) as error:
        print(f"{PHASE}: {error}", file=sys.stderr)
        return 1
    print(f"{PHASE} {args.action}: PASS (structural evidence only)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
