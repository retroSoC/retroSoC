#!/usr/bin/env python3
"""Source-bound Tiny ICS55 evidence and a fail-closed SAFE24 netlist audit."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import re
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as b  # noqa: E402
from scripts.config_key import variant_id  # noqa: E402
from scripts.tiny_r2_feasibility import timing_metrics, path_slack  # noqa: E402

PHASE = "TINY-ICS55-P1"
RAM = "ics55_ecos_sram_1024x32_m8"


def inspect_clock_source(leaves: list[dict], system: str, reference: str,
                         constants: dict) -> list[dict]:
    """Prove the supported SAFE24 pad/buffer path, rejecting unknown logic.

    This deliberately recognizes only the selected ICS55 input receiver and
    non-inverting clock buffer. A future clock mux/gate needs its own review.
    Inout drivers are included so a second driver on REF24 cannot be hidden.
    """
    drivers = {}
    for cell in leaves:
        for port, bits in cell["ports"].items():
            if cell["directions"].get(port) in ("output", "inout"):
                for bit in bits:
                    drivers.setdefault(bit, []).append((cell, port))

    def scalar(cell, port):
        bits = cell["ports"].get(port, [])
        if len(bits) != 1:
            raise ValueError(f"missing scalar clock-path pin: {cell['path']}/{port}")
        return bits[0]

    trace, seen = [], set()
    cursor = system
    while True:
        if cursor in constants or cursor in ("x", "z") or cursor in seen:
            raise ValueError("constant, unknown or cyclic SYS clock source")
        seen.add(cursor)
        candidates = drivers.get(cursor, [])
        if len(candidates) != 1:
            raise ValueError("SYS clock source has missing or multiple drivers")
        cell, port = candidates[0]
        trace.append({"path": cell["path"], "type": cell["type"], "output": port})
        if cell["type"] == "BUFX0P7H7R" and port == "Y":
            cursor = scalar(cell, "A")
        elif cell["type"] == "P65_1233_PBMUX" and port == "C":
            if scalar(cell, "PAD") != reference:
                raise ValueError("SYS input receiver is not connected to external REF24")
            if any(constants.get(scalar(cell, pin)) != value
                   for pin, value in (("IE", 1), ("OE", 0), ("CS", 1))):
                raise ValueError("REF24 pad is not a constant-enabled CMOS input")
            if drivers.get(reference) != [(cell, "PAD")]:
                raise ValueError("external REF24 has an additional internal driver")
            return trace
        else:
            raise ValueError(f"unsupported SYS clock source: {cell['type']}/{port}")


def verify_locked_views(root: Path) -> dict:
    """Check derived cache bytes against the unchanged locked archives."""
    lock = b.read_json(root / "dependencies/dependencies.lock.json")
    verified = {}
    for key in ("pdk_ics55_h7cr_liberty", "pdk_ics55_sram_1024x32_m8", "pdk_ics55_sram_4096x32_m8"):
        spec = lock["archives"][key]
        path = root / spec["destination"]
        if b.sha256(path) != spec["sha256"]:
            raise ValueError(f"locked archive changed: {key}")
        package = key.replace("pdk_ics55_sram_", "ics55_ecos_sram_")
        seen = set()
        with tarfile.open(path) as archive:
            for member in archive:
                if not member.isfile():
                    continue
                relative = Path(member.name)
                if relative.is_absolute() or ".." in relative.parts:
                    raise ValueError("unsafe archive view name")
                target = None
                if key == "pdk_ics55_h7cr_liberty":
                    for corner, tokens in (("tt", ("tt", "1p2", "25")), ("ss", ("ss", "1p08", "125"))):
                        if member.name.endswith(".lib") and all(t in member.name.lower() for t in tokens):
                            target = root / f".cache/retrosoc/pdk/ics55/ics55_h7cr_{corner}.lib"
                else:
                    if relative.parts[0] == package:
                        relative = Path(*relative.parts[1:])
                    if relative.parts and relative.parts[0] in ("lib", "verilog"):
                        target = root / ".cache/retrosoc/pdk/ics55/sram" / package / relative
                if target is not None:
                    if not target.is_file() or hashlib.sha256(archive.extractfile(member).read()).hexdigest() != b.sha256(target):
                        raise ValueError(f"cached view differs from locked archive: {target}")
                    seen.add(str(target))
        if len(seen) != (2 if key == "pdk_ics55_h7cr_liberty" else 11):
            raise ValueError(f"incomplete locked view set: {key}")
        verified[key] = {"archive": b.artifact(path), "views": sorted(seen)}
    from physical.pdk.prepare_ics55_sim_model import patch_muxi2_models, VERILATOR_LINT_OFF, VERILATOR_LINT_ON
    pdk = root / lock["sources"]["pdk_ics55"]["destination"]
    original = pdk / "IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CR/verilog/ics55_LLSC_H7CR.v"
    patched, _ = patch_muxi2_models(original.read_text())
    expected = VERILATOR_LINT_OFF + patched.rstrip() + "\n" + VERILATOR_LINT_ON
    model = root / ".cache/retrosoc/pdk/ics55/ics55_h7cr_functional.v"
    if model.read_text() != expected:
        raise ValueError("standard-cell functional model differs from the owned locked-source transform")
    verified["functional_cells"] = b.artifact(model)
    return verified


def inspect_netlist(document: dict) -> dict:
    modules = document["modules"]
    top = "retrosoc_tiny_asic"
    leaves = []
    aliases = {}

    def canonical(bit):
        if bit in aliases:
            aliases[bit] = canonical(aliases[bit])
            return aliases[bit]
        return bit

    def alias(a, other):
        a, other = canonical(a), canonical(other)
        if a == other:
            return
        if a in ("0", "1", "x", "z"):
            a, other = other, a
        if a in ("0", "1", "x", "z"):
            raise ValueError("conflicting constants at a hierarchy boundary")
        aliases[a] = other

    def visit(module_name, scope, bound):
        module = modules[module_name]
        mapping = {}
        for port, bits in bound.items():
            declaration = module["ports"][port]
            for local, external in zip(declaration["bits"], bits):
                if isinstance(local, str):
                    if declaration["direction"] == "output":
                        alias(external, local)
                elif local in mapping:
                    alias(external, mapping[local])
                else:
                    mapping[local] = external

        def net(bit):
            return bit if isinstance(bit, str) else mapping.get(bit, f"{scope}:{bit}")

        for name, cell in module.get("cells", {}).items():
            ports = {port: [net(bit) for bit in bits] for port, bits in cell["connections"].items()}
            kind = cell["type"]
            path = f"{scope}/{name}"
            attrs = modules.get(kind, {}).get("attributes", {})
            if kind in modules and not int(str(attrs.get("blackbox", "0")), 2):
                visit(kind, path, ports)
            else:
                directions = cell.get("port_directions", {
                    p: decl["direction"] for p, decl in modules.get(kind, {}).get("ports", {}).items()
                })
                leaves.append({"path": path, "type": kind, "ports": ports,
                               "directions": directions})

    visit(top, top, {})
    for c in leaves:
        for port, bits in c["ports"].items():
            c["ports"][port] = [canonical(bit) for bit in bits]
    clock = modules[top]["cells"]["u_clock_buffer"]["connections"]["clk_o"]
    if len(clock) != 1 or not isinstance(clock[0], int):
        raise ValueError("missing live SYS clock")
    system = canonical(f"{top}:{clock[0]}")
    if system in ("0", "1", "x", "z"):
        raise ValueError("SYS is not a live clock net")
    ram = [c for c in leaves if c["type"] == RAM]
    pll = [c for c in leaves if c["type"] == "PLL_TOP"]
    if any(c["type"] == "ics55_ecos_sram_4096x32_m8" for c in leaves):
        raise ValueError("Tiny instantiated the unsupported 16 KiB SRAM interface stub")
    if len(ram) != 32 or len(pll) != 1:
        raise ValueError("expected 32 main SRAM macros and one PLL")
    expected_ram = {f"u_soc.u_sram.gen_group[{g}].u_group.gen_bank[{n}].u_ram.u_mem"
                    for g in range(4) for n in range(8)}
    observed_ram = {next((name for name in expected_ram
                         if c["path"].replace("/", ".").endswith("." + name)), "") for c in ram}
    if observed_ram != expected_ram:
        raise ValueError("Tiny P4 SRAM group/macro hierarchy is missing or stale")
    if any(c["ports"].get("CLK") != [system] for c in ram):
        raise ValueError("main SRAM does not share direct SYS")
    constants = {"0": 0, "1": 1}
    for c in leaves:
        if c["type"] in ("TIELOH7R", "TIEHIH7R"):
            for bit in c["ports"]["Z"]:
                constants[bit] = int(c["type"] == "TIEHIH7R")
    ref_port = modules[top]["ports"].get("extclk_i_pad", {})
    ref_bits = ref_port.get("bits", [])
    if (ref_port.get("direction") not in ("input", "inout") or len(ref_bits) != 1
            or not isinstance(ref_bits[0], int)):
        raise ValueError("missing live external REF24 input port")
    reference = canonical(f"{top}:{ref_bits[0]}")
    if reference in constants or reference in ("x", "z"):
        raise ValueError("external REF24 input is tied off or unknown")
    clock_path = inspect_clock_source(leaves, system, reference, constants)
    enable = pll[0]["ports"].get("EN", [])
    if len(enable) != 1 or constants.get(enable[0]) != 0:
        raise ValueError("PLL enable is not proven constant zero")
    cpu = [c for c in leaves if "u_hazard3_cpu_2port" in c["path"]
           and ("CK" in c["ports"] or "CKN" in c["ports"])]
    if not cpu or any(c["ports"].get("CK", c["ports"].get("CKN")) != [system] for c in cpu):
        raise ValueError("CPU sequential clocks do not share direct SYS")
    pll_outputs = {bit for name in ("CKOUT1", "CKOUT2", "CKTST") for bit in pll[0]["ports"].get(name, [])}
    if system in pll_outputs:
        raise ValueError("PLL drives SYS")
    return {"system_net": system,
            "system_clock_source": {"port": "extclk_i_pad", "net": reference, "path": clock_path},
            "cpu_clocked_cells": len(cpu),
            "sram": [{"path": c["path"], "clock": c["ports"]["CLK"]} for c in ram],
            "pll": pll[0], "pll_enable": 0, "qualification": "SAFE24 digital connectivity only"}


def check_configuration(variant: Path, path: Path) -> None:
    manifest = b.configuration(variant)
    if manifest["configuration"]["PDK"] != "ICS55":
        raise ValueError("ICS55 platform evidence cannot consume another PDK")
    config = dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)
    for key, value in {"PDK": "ICS55", "SOC": "TINY", "HAVE_PLL": "YES",
                       "HAVE_SRAM_MACRO": "YES", "SRAM_SIZE_KIB": "128",
                       "TOP_DESIGN": "retrosoc_tiny_asic", "PERIOD_PS": "41667"}.items():
        if config.get(key) != value:
            raise ValueError(f"consumed netlist configuration mismatch: {key}")
    values = [f"{k}={v}" for k, v in manifest["configuration"].items()
              if k not in ("SIMU", "SYNTH", "SYNTH_RECIPE", "STA")]
    expected = variant_id(manifest["profile"], values, ROOT / "dependencies/dependencies.lock.json",
                          "2000-01-01-00-00").rsplit("-", 1)[1]
    if config.get("CONFIG_DIGEST") != expected or variant.name.rsplit("-", 1)[1] != expected:
        raise ValueError("consumed configuration digest mismatch")


def verify_netlist(variant: Path, netlist: Path, config: Path, output: Path) -> dict:
    check_configuration(variant, config)
    report = b.read_json(output)
    if report.get("status") != "passed" or report.get("phase") != PHASE:
        raise ValueError("missing successful structural audit")
    if report.get("audit_script") != b.artifact(Path(__file__)):
        raise ValueError("structural audit was produced by another script")
    expected = [netlist, Path(str(netlist) + ".json"), config]
    if report.get("inputs") != [b.artifact(path) for path in expected]:
        raise ValueError("missing or changed consumed netlist artifacts")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("action", choices=("capture", "audit-netlist", "verify-netlist", "report"))
    parser.add_argument("--netlist", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    parent = variant / "meta/tiny-ics55-p1"
    try:
        if args.action == "capture":
            directory = b.new_attempt(parent, "inputs-")
            b.dump(parent / "latest-inputs.json", {"path": str(directory / "identity.json")})
            b.dump(directory / "identity.json", {"phase": PHASE, "status": "capturing"})
            inputs = b.source_inputs(ROOT, "ICS55")
            for path in (ROOT / "tests").rglob("*"):
                if path.is_file() and path.suffix in (".py", ".sv", ".svh"):
                    inputs[str(path.relative_to(ROOT))] = b.sha256(path)
            views = verify_locked_views(ROOT)
            identity = {"phase": PHASE, "status": "captured", "created_at": datetime.now(timezone.utc).isoformat(), "views": views,
                        "source": b.snapshot(ROOT, directory, inputs), "tools": b.tools_identity(ROOT)}
            if any(b.sha256(ROOT / name) != digest for name, digest in inputs.items()):
                raise ValueError("source changed while capturing inputs")
            b.dump(directory / "identity.json", identity)
            b.dump(parent / "latest-inputs.json", {"path": str(directory / "identity.json")})
        elif args.action in ("audit-netlist", "verify-netlist"):
            if not all((args.netlist, args.config, args.output)):
                parser.error("netlist actions require --netlist, --config and --output")
            check_configuration(variant, args.config)
            if args.action == "audit-netlist":
                net_json = Path(str(args.netlist) + ".json")
                report = {"phase": PHASE, "status": "passed", "audit_script": b.artifact(Path(__file__)),
                          "binding": inspect_netlist(b.read_json(net_json)),
                          "inputs": [b.artifact(p) for p in (args.netlist, net_json, args.config)]}
                b.dump(args.output, report)
            else:
                verify_netlist(variant, args.netlist, args.config, args.output)
        else:
            b.dump(parent / "report.json", {"phase": PHASE, "status": "incomplete"})
            identity = b.read_json(Path(b.read_json(parent / "latest-inputs.json")["path"]))
            if identity.get("status") != "captured":
                raise ValueError("missing successful source capture")
            inputs = b.read_json(b.check_artifact(identity["source"]["inputs"]))
            if any(b.sha256(ROOT / name) != digest for name, digest in inputs.items()):
                raise ValueError("captured source changed")
            flows = {}
            for key in ("snapshot", "patch"):
                b.check_artifact(identity["source"][key])
            for tool in identity["tools"].values():
                b.check_artifact(tool["executable"])
                b.check_artifact(tool["archive"])
            for name in ("syn/yosys/result-synth.json", "sta/opensta/result-sta.json"):
                path = variant / name
                result = b.read_json(path)
                if result.get("status") != "passed" or result.get("exit_code") != 0:
                    raise ValueError(f"incomplete flow: {name}")
                if datetime.fromisoformat(result["started_at"]) < datetime.fromisoformat(identity["created_at"]):
                    raise ValueError(f"flow predates captured source: {name}")
                flows[name] = b.artifact(path)
            sta = variant / "sta/opensta"
            mapped = variant / "syn/yosys/out/retrosoc_tiny_asic_yosys.v"
            verify_netlist(variant, mapped, mapped.with_suffix(".config"),
                           variant / "syn/yosys/tiny-ics55-netlist.json")
            log = (sta / "opensta.log").read_text()
            if "TINY_ICS55_STA_AUDIT_PASS:" not in log or re.search(r"(?im)^Error:|\bFATAL\b|%Error", log):
                raise ValueError("incomplete or erroneous STA audit")
            metrics = timing_metrics(sta / "timing_metrics.rpt")
            report = {"phase": PHASE, "status": "completed", "source": identity,
                      "flows": flows, "qualification": "SAFE24 synthesis/STA observation only; functional acceptance is separate",
                      "timing": metrics,
                      "timing_status": "failed" if any(v < 0 for v in metrics.values()) else "nonnegative_reported_slack",
                      "sys_setup_slack_ns": path_slack(sta / "sys-setup.rpt"),
                      "sys_hold_slack_ns": path_slack(sta / "sys-hold.rpt"),
                      "sta_artifacts": {p.name: b.artifact(p) for p in sta.iterdir() if p.is_file()},
                      "macro_audit": b.artifact(variant / "syn/yosys/tiny-ics55-netlist.json")}
            b.dump(parent / "report.json", report)
        print(f"{PHASE} {args.action}: PASS (not physical qualification)")
        return 0
    except (OSError, ValueError, KeyError) as error:
        if args.action == "capture" and "directory" in locals():
            b.dump(directory / "identity.json", {"phase": PHASE, "status": "failed", "error": str(error)})
        print(f"{PHASE}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
