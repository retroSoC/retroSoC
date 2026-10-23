#!/usr/bin/env python3
"""Capture and check source-bound Tiny P6 acceptance without promoting a phase."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as b  # noqa: E402
from scripts import tiny_r2_p5 as previous  # noqa: E402
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402

PHASE = "TINY-R2-P6"
MODEL = "tests/rtl/sdio_native_model.sv"
VERIFICATION_UPDATE_PATHS = {MODEL, "scripts/tiny_r2_p6.py", "tests/test_tiny_r2_p6.py"}
CONSUMER_UPDATE_PATHS = {
    "publications/programming_reference.py", "tests/test_publication_programming.py",
    "physical/commercial/config/products/tiny.mk", "physical/commercial/tcl/common/products/tiny.tcl",
    "tests/test_commercial_flow.py", "scripts/tiny_r2_p6.py", "tests/test_tiny_r2_p6.py",
}
COLLECTION_UPDATE_PATHS = {"scripts/tiny_r2_p6.py", "tests/test_tiny_r2_p6.py"}
RECORDS = {
    "UART": {"pads": 1, "echo_bytes": 4, "flow_rejected": 1},
    "DMA": {"channels": 8, "rejected_requests": 5},
    "RNG": {"unqualified": 1, "diagnostic": 1, "irq": 1},
    "CRC": {"dma": 1, "tails": 4, "empty": 1},
    "CRYPTO": {"init": 1, "aes_sha": 1, "dma45": 1, "rsa_public": 1, "zeroize": 1},
    "RECOVERY": {"audio_stops": 2, "ws_underflow": 1, "ws_abort": 1},
    "SDIO": {"dma_bytes": 2048, "pio_bytes": 512, "width1": 1, "width4": 1, "irq": 1, "errors": 2},
}


def parse_log(content: str, flow: dict) -> dict:
    if (flow.get("status") != "passed" or flow.get("exit_code") != 0
            or not re.search(r"SIM_TEST_PASS Tiny cycles=[0-9]+(?:\r?\n|$)", content)
            or DEFAULT_FAILURE.search(content)):
        raise ValueError("P6 requires successful command, terminal marker and no forbidden errors")
    result = {}
    for name, expected in RECORDS.items():
        rows = [b.parse_fields(line, set(expected)) for line in content.splitlines()
                if line.startswith("R2_P6_" + name + " ")]
        if rows != [expected]:
            raise ValueError(f"missing, duplicate or invalid P6 {name} record")
        result[name.lower()] = rows[0]
    fields = {"bits", "frames", "ws_frames", "background_jobs", "tcd", "elapsed_us", "cycles", "instructions"}
    audio = [b.parse_fields(line, fields) for line in content.splitlines()
             if line.startswith("R2_P6_AUDIO ")]
    if [row["bits"] for row in audio] != [16, 24]:
        raise ValueError("P6 needs exactly both audio formats")
    for row in audio:
        if (row["frames"] != 256 or row["ws_frames"] != 2 or
                not 1 <= row["background_jobs"] <= 64 or
                row["tcd"] != int(row["bits"] == 24) or not 0 < row["elapsed_us"] < 50000 or
                not 0 < row["instructions"] <= row["cycles"]):
            raise ValueError("invalid P6 audio/contention observation")
    result["audio"] = audio
    wires = [b.parse_fields(line, {"bits", "samples"}) for line in content.splitlines()
             if line.startswith("R2_P6_I2S_WIRE ")]
    if wires != [{"bits": 16, "samples": 512}, {"bits": 24, "samples": 512}]:
        raise ValueError("missing or incorrect independent audio wire observations")
    result["audio_wires"] = wires
    fields = {"owner", "read_bytes", "write_bytes", "descriptor_bytes", "ar_stall_max",
              "aw_stall_max", "w_stall_max", "r_stall_max", "b_stall_max"}
    bus = sorted([b.parse_fields(line, fields) for line in content.splitlines()
                  if line.startswith("R2_P6_AXI ")], key=lambda row: row["owner"])
    if [row["owner"] for row in bus] != [0, 1, 2]:
        raise ValueError("P6 needs each actual AXI owner observation")
    for row in bus:
        if (any(v < 0 for v in row.values()) or row["read_bytes"] == 0 or row["write_bytes"] == 0
                or row["descriptor_bytes"] > row["read_bytes"]):
            raise ValueError("invalid P6 AXI payload/backpressure observation")
    if bus[1]["descriptor_bytes"] == 0:
        raise ValueError("no actual background descriptor fetch observed")
    result["bus"] = bus
    contention = [b.parse_fields(line, {"sdio_dma_cycles", "cpu_fetches"})
                  for line in content.splitlines() if line.startswith("R2_P6_CONTENTION ")]
    if len(contention) != 1 or any(value <= 0 for value in contention[0].values()):
        raise ValueError("missing actual SDIO/DMA overlap and CPU progress")
    result["contention"] = contention[0]
    fields = {"ws_frames", "ws_wait_max", "fifo_max", "underflows", "aborts", "clock_stops"}
    devices = [b.parse_fields(line, fields) for line in content.splitlines()
               if line.startswith("R2_P6_DEVICES ")]
    if len(devices) != 1:
        raise ValueError("missing or duplicate independent device observations")
    d = devices[0]
    if (d["ws_frames"] != 4 or not 0 <= d["ws_wait_max"] <= 4800 or
            not 1 <= d["fifo_max"] <= 16 or d["underflows"] != 1 or
            d["aborts"] != 1 or d["clock_stops"] != 2):
        raise ValueError("P6 device coverage/service budget failed")
    result["devices"] = d
    return result


def inputs(variants: list[Path]) -> dict:
    result = {}
    for variant in variants:
        config = b.configuration(variant)["configuration"]
        if config.get("APP") != "ci_smoke":
            raise ValueError("P6 qualification requires the ci_smoke composition")
        result.update(previous.inputs(ROOT, variant))
    for name in (".bake.toml", ".clang-format", "docs/misra-c-2012.md",
                 "quality/misra/deviations.md", "docs/ip/dma.md", "docs/ip/i2s.md",
                 "docs/ip/sdio.md", "docs/ip/crypto.md", "docs/ip/ws2812.md",
                 "physical/commercial/config/products/tiny.mk",
                 "physical/commercial/tcl/common/products/tiny.tcl"):
        result[name] = b.sha256(ROOT / name)
    return result


def current_tools() -> dict:
    tools = b.tools_identity(ROOT)
    tools["vvp"] = b.vvp_identity("vvp", tools["iverilog"])
    return tools


def checked_flow(path: Path, captured_at: str) -> dict:
    flow = b.read_json(path)
    if flow.get("status") != "passed" or flow.get("exit_code") != 0:
        raise ValueError(f"unsuccessful gate: {path}")
    if (not flow.get("started_at") or not flow.get("finished_at")
            or flow["started_at"] < captured_at or flow["finished_at"] < flow["started_at"]):
        raise ValueError(f"gate lacks successful post-capture chronology: {path}")
    return flow


def check_model_declaration_move(before: str, after: str) -> None:
    """Permit only relocation of one unchanged continuous net declaration.

    Verilator/sv2v accept its forward reference; native Icarus needs the integer
    first. Every other source byte, including all procedural behavior, must match.
    """
    pattern = re.compile(r"^  wire \[3:0\] s_token_lanes = [^;]+;\n", re.M)
    old, new = pattern.findall(before), pattern.findall(after)
    if (len(old) != 1 or old != new or pattern.sub("", before) != pattern.sub("", after)
            or after.index("  integer s_data_bytes;") > after.index(new[0])):
        raise ValueError("not the permitted SDIO model declaration-only relocation")


def snapshot_model(source: dict) -> str:
    with tarfile.open(b.check_artifact(source["snapshot"])) as archive:
        return archive.extractfile(MODEL).read().decode()


def check_update(directory: Path, saved: dict, update: dict, current: dict) -> dict:
    if (update.get("phase") != PHASE or update.get("kind") != "native_model_declaration_order"
            or update["original_source"] != b.artifact(directory / "source.json")):
        raise ValueError("verification update does not bind the original campaign")
    old = b.read_json(b.check_artifact(saved["source"]["inputs"]))
    new = b.read_json(b.check_artifact(update["source"]["inputs"]))
    changed = {name for name in old.keys() | new.keys() if old.get(name) != new.get(name)}
    if (MODEL not in changed or not changed <= VERIFICATION_UPDATE_PATHS
            or sorted(changed) != update["changed_inputs"] or new != current):
        raise ValueError("verification update changed DUT/firmware/constraints or unapproved inputs")
    check_model_declaration_move(snapshot_model(saved["source"]), snapshot_model(update["source"]))
    for source in (saved["source"], update["source"]):
        for name in ("inputs", "snapshot", "patch"):
            b.check_artifact(source[name])
    if update["tools"] != saved["tools"] or update["captured_at"] < saved["captured_at"]:
        raise ValueError("verification update changed tools or chronology")
    return old


def capture_verification_update(directory: Path, variants: list[Path]) -> None:
    path = directory / "verification-update.json"
    if path.exists():
        raise ValueError("never overwrite a verification update")
    saved = b.read_json(directory / "source.json")
    current = inputs(variants)
    old = b.read_json(b.check_artifact(saved["source"]["inputs"]))
    changed = sorted(name for name in old.keys() | current.keys() if old.get(name) != current.get(name))
    if MODEL not in changed or not set(changed) <= VERIFICATION_UPDATE_PATHS:
        raise ValueError("only the native model and its collector tests may change")
    check_model_declaration_move(snapshot_model(saved["source"]), (ROOT / MODEL).read_text())
    update = {"phase": PHASE, "kind": "native_model_declaration_order",
              "original_source": b.artifact(directory / "source.json"), "changed_inputs": changed,
              "source": b.snapshot(ROOT, directory / "inputs-native-model", current),
              "tools": current_tools(), "captured_at": datetime.now(timezone.utc).isoformat()}
    check_update(directory, saved, update, current)
    b.dump(path, update)


def check_consumer_update(directory: Path, previous_update: dict, update: dict, current: dict) -> None:
    """Permit only consumers not used by the running RTL/smoke flows."""
    if (update.get("phase") != PHASE or update.get("kind") != "publication_and_commercial_consumers"
            or update["previous_update"] != b.artifact(directory / "verification-update.json")):
        raise ValueError("consumer update does not bind the verified model snapshot")
    old = b.read_json(b.check_artifact(previous_update["source"]["inputs"]))
    new = b.read_json(b.check_artifact(update["source"]["inputs"]))
    changed = {name for name in old.keys() | new.keys() if old.get(name) != new.get(name)}
    if (not changed or not changed <= CONSUMER_UPDATE_PATHS or
            sorted(changed) != update["changed_inputs"] or new != current):
        raise ValueError("consumer update changed simulation, firmware, smoke constraints or unrelated inputs")
    for field in ("inputs", "snapshot", "patch"):
        b.check_artifact(update["source"][field])
    if (update["tools"] != previous_update["tools"] or
            update["captured_at"] < previous_update["captured_at"]):
        raise ValueError("consumer update changed tools or chronology")


def capture_consumer_update(directory: Path, variants: list[Path]) -> None:
    path = directory / "consumer-update.json"
    if path.exists():
        raise ValueError("never overwrite a consumer update")
    previous_update = b.read_json(directory / "verification-update.json")
    current = inputs(variants)
    old = b.read_json(b.check_artifact(previous_update["source"]["inputs"]))
    changed = sorted(name for name in old.keys() | current.keys() if old.get(name) != current.get(name))
    if not changed or not set(changed) <= CONSUMER_UPDATE_PATHS:
        raise ValueError("unexpected non-consumer source changes")
    update = {"phase": PHASE, "kind": "publication_and_commercial_consumers",
              "previous_update": b.artifact(directory / "verification-update.json"),
              "changed_inputs": changed,
              "source": b.snapshot(ROOT, directory / "inputs-consumers", current),
              "tools": current_tools(), "captured_at": datetime.now(timezone.utc).isoformat()}
    check_consumer_update(directory, previous_update, update, current)
    b.dump(path, update)


def check_collection_update(directory: Path, previous_update: dict, update: dict, current: dict) -> None:
    if (update.get("phase") != PHASE or update.get("kind") != "terminal_log_collection"
            or update["previous_update"] != b.artifact(directory / "consumer-update.json")):
        raise ValueError("collection update does not bind the consumer snapshot")
    old = b.read_json(b.check_artifact(previous_update["source"]["inputs"]))
    new = b.read_json(b.check_artifact(update["source"]["inputs"]))
    changed = {name for name in old.keys() | new.keys() if old.get(name) != new.get(name)}
    if (not changed or not changed <= COLLECTION_UPDATE_PATHS or
            sorted(changed) != update["changed_inputs"] or new != current):
        raise ValueError("collection update changed inputs outside the collector/tests")
    for field in ("inputs", "snapshot", "patch"):
        b.check_artifact(update["source"][field])
    if (update["tools"] != previous_update["tools"] or
            update["captured_at"] < previous_update["captured_at"]):
        raise ValueError("collection update changed tools or chronology")


def capture_collection_update(directory: Path, variants: list[Path]) -> None:
    path = directory / "collection-update.json"
    if path.exists():
        raise ValueError("never overwrite a collection update")
    previous_update = b.read_json(directory / "consumer-update.json")
    current = inputs(variants)
    old = b.read_json(b.check_artifact(previous_update["source"]["inputs"]))
    changed = sorted(name for name in old.keys() | current.keys() if old.get(name) != current.get(name))
    if not changed or not set(changed) <= COLLECTION_UPDATE_PATHS:
        raise ValueError("unexpected non-collector source changes")
    update = {"phase": PHASE, "kind": "terminal_log_collection",
              "previous_update": b.artifact(directory / "consumer-update.json"),
              "changed_inputs": changed,
              "source": b.snapshot(ROOT, directory / "inputs-collection", current),
              "tools": current_tools(), "captured_at": datetime.now(timezone.utc).isoformat()}
    check_collection_update(directory, previous_update, update, current)
    b.dump(path, update)


def capture(directory: Path, variants: list[Path]) -> None:
    if (directory / "source.json").exists():
        raise ValueError("capture needs a fresh evidence directory; never overwrite provenance")
    if {b.configuration(v)["configuration"]["PDK"] for v in variants} != {"ICS55", "IHP130"}:
        raise ValueError("capture both Tiny PDK input sets before validation")
    source = b.snapshot(ROOT, directory / "inputs", inputs(variants))
    tools = current_tools()
    b.dump(directory / "source.json", {"phase": PHASE, "source": source, "tools": tools,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "variants": [str(p.resolve()) for p in variants],
        "configurations": [b.configuration(p) for p in variants]})


def report(directory: Path, gates: list[Path], variants: list[Path]) -> None:
    saved = b.read_json(directory / "source.json")
    if saved.get("phase") != PHASE:
        raise ValueError("wrong evidence phase")
    if saved["tools"] != current_tools():
        raise ValueError("locked tool identity changed after capture")
    selected = [Path(p) for p in saved["variants"]]
    current = inputs(selected)
    original = b.read_json(b.check_artifact(saved["source"]["inputs"]))
    update_path = directory / "verification-update.json"
    update = b.read_json(update_path) if update_path.exists() else None
    consumer_path = directory / "consumer-update.json"
    consumer = b.read_json(consumer_path) if consumer_path.exists() else None
    collection_path = directory / "collection-update.json"
    collection = b.read_json(collection_path) if collection_path.exists() else None
    consumer_inputs = current
    if collection:
        if not consumer:
            raise ValueError("collection update requires the consumer snapshot")
        check_collection_update(directory, consumer, collection, current)
        consumer_inputs = b.read_json(b.check_artifact(consumer["source"]["inputs"]))
    verified_inputs = current
    if consumer:
        if not update:
            raise ValueError("consumer update requires the model snapshot")
        check_consumer_update(directory, update, consumer, consumer_inputs)
        verified_inputs = b.read_json(b.check_artifact(update["source"]["inputs"]))
    if update:
        original = check_update(directory, saved, update, verified_inputs)
    elif current != original:
        raise ValueError("P6 technical inputs changed after capture")
    for name in ("snapshot", "patch"):
        b.check_artifact(saved["source"][name])
    checked = {}
    for path in gates:
        gate = checked_flow(path, saved["captured_at"])
        checked[str(path)] = {"result": b.artifact(path), "log": b.artifact(Path(gate["log"]))}
    simulations = {}
    selections = [(variant, simulator) for variant in variants for simulator in ("iverilog", "verilator")
                  if (variant / "sim" / simulator / "result-sim.json").is_file()]
    for variant, simulator in selections:
        config = b.configuration(variant)
        if config["configuration"].get("APP") != "ci_smoke":
            raise ValueError("simulation must use the complete ci_smoke composition")
        pdk = config["configuration"]["PDK"]
        key = pdk + "/" + simulator
        if key in simulations or simulator not in ("iverilog", "verilator"):
            raise ValueError("duplicate or unsupported simulation variant")
        folder = variant / "sim" / simulator
        model_source = update if update and simulator == "iverilog" else saved
        flow = checked_flow(folder / "result-sim.json", model_source["captured_at"])
        compilation = checked_flow(folder / "result-compile.json", model_source["captured_at"])
        if flow["started_at"] < compilation["finished_at"]:
            raise ValueError("simulation predates completed model compilation")
        check = b.read_json(folder / "result-sim-check.json")
        if check.get("status") != "passed":
            raise ValueError("missing strict simulation verdict")
        samples = parse_log((folder / "sim.log").read_text(), flow)
        paths = [folder / name for name in ("result-sim.json", "result-sim-check.json", "sim.log",
                                            "result-compile.json", "compile.log")]
        paths += [folder / ("emu" if simulator == "verilator" else "simv"),
                  variant / "sw/firmware", variant / "sw/retrosoc_fw.hex", variant / "sw/retrosoc_fw.map",
                  variant / "sw/retrosoc_fw.bin", variant / "sw/ld2_all_sram.lds",
                  variant / "sw/memory_regions.ld",
                  variant / "meta/manifest.json"]
        paths += sorted(path for path in (variant / "sw/include").rglob("*") if path.is_file())
        runtime = b.runtime_inputs(ROOT, variant, simulator)
        if update and simulator == "verilator":
            if runtime.get(MODEL) != current[MODEL]:
                raise ValueError("missing native card model runtime input")
            runtime[MODEL] = original[MODEL]
        simulations[key] = {"configuration": config, "simulator": simulator, "samples": samples,
                            "source": model_source["source"], "runtime_inputs": runtime,
                            "artifacts": [b.artifact(path) for path in paths]}
    if set(simulations) != {p + "/" + s for p in ("ICS55", "IHP130") for s in ("iverilog", "verilator")}:
        raise ValueError("P6 needs both simulators on both Tiny PDKs")
    # Physical/quality reports remain independent gates; this status never
    # promotes functional collection into phase or physical qualification.
    b.dump(directory / "report.json", {"phase": PHASE, "status": "functional_evidence_collected",
        "tools": saved["tools"],
        "verification_update": b.artifact(update_path) if update else None,
        "consumer_update": b.artifact(consumer_path) if consumer else None,
        "collection_update": b.artifact(collection_path) if collection else None,
        "source": saved["source"], "source_inputs_rechecked": len(current), "gates": checked,
        "simulations": simulations, "limitations": ["human review pending", "timing observational",
        "no QFN64/package, routed/PVT/CDC/RDC or publication qualification"]})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "capture-verification-update", "capture-consumer-update",
                                           "capture-collection-update", "report"))
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--variant-root", action="append", type=Path, required=True)
    parser.add_argument("--gate", action="append", type=Path, default=[])
    args = parser.parse_args()
    directory = args.evidence_root.resolve()
    if not directory.is_relative_to(ROOT / "build"):
        parser.error("evidence must stay under the repository build root")
    if args.action == "capture":
        capture(directory, args.variant_root)
    elif args.action == "capture-verification-update":
        capture_verification_update(directory, args.variant_root)
    elif args.action == "capture-consumer-update":
        capture_consumer_update(directory, args.variant_root)
    elif args.action == "capture-collection-update":
        capture_collection_update(directory, args.variant_root)
    else:
        report(directory, args.gate, args.variant_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
