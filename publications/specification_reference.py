"""Typed publication-only specifications, provenance, geometry and reference models.

This module never changes hardware definitions. Canonical collectors supply design
facts; external and constructed numbers remain reference data through dependencies.
"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import csv
import hashlib
import json
import math
from pathlib import Path
import re

STATES = {"confirmed", "calculated", "reference", "tbd"}
LABELS = {"confirmed": "Confirmed design", "calculated": "Calculated",
          "reference": "Reference Only", "tbd": "TBD"}
SHARED = "publications/specifications"
BOOKS = {"tiny": "publications/datasheets/tiny/specifications",
         "mini": "publications/datasheets/specifications"}
MODEL_FILE = f"{SHARED}/models.json"
SOURCE_FILE = f"{SHARED}/sources.json"
REQUIRED = {"id", "product", "profiles", "meaning", "group", "unit", "value", "status",
            "conditions", "evidence", "sources", "assumptions", "replacement", "dependencies"}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def source_inputs(product: str) -> set[str]:
    return {SOURCE_FILE, MODEL_FILE, f"{BOOKS[product]}/parameters.json",
            "publications/specification_reference.py", "publications/specification_plots.py",
            "publications/specification_vectors.py",
            "publications/review_datasheet.py", "tests/test_publication_specifications.py",
            "publications/specifications/components.typ", "publications/specifications/figures.typ",
            "requirements/publication.txt"}


def validate_sources(sources: list[dict], root: Path) -> None:
    if len({s["id"] for s in sources}) != len(sources):
        raise ValueError("duplicate specification source")
    for s in sources:
        if not all(s.get(k) for k in ("id", "kind", "title", "version", "locator", "sha256")):
            raise ValueError("incomplete specification source")
        if not re.fullmatch(r"[a-f0-9]{64}", s["sha256"]):
            raise ValueError("source fingerprint must be SHA-256")
        if s["kind"] == "repository":
            if digest(root / s["path"]) != s["sha256"]:
                raise ValueError(f"specification source drift: {s['path']}")
            if not re.fullmatch(r"[a-f0-9]{40}", s.get("revision", "")):
                raise ValueError("repository source requires full revision")
        elif s["kind"] == "constructed" and digest(root / s["path"]) != s["sha256"]:
            raise ValueError("constructed model fingerprint drift")
        elif s["kind"] not in {"external", "constructed"}:
            raise ValueError("unknown specification source kind")
        if s["kind"] == "external" and not s.get("url", "").startswith("https://"):
            raise ValueError("external source needs an official HTTPS locator")


def validate_records(records: list[dict], sources: list[dict], product: str) -> None:
    """Reject unsupported promotion, missing context, wrong units and hidden nulls."""
    by_id = {r["id"]: r for r in records}
    source_map = {s["id"]: s for s in sources}
    if len(by_id) != len(records):
        raise ValueError("duplicate parameter ID")
    visiting, visited = set(), set()

    def check(pid: str):
        if pid in visiting:
            raise ValueError("cyclic specification dependency")
        if pid in visited:
            return
        r = by_id[pid]
        if not REQUIRED <= r.keys() or r["status"] not in STATES:
            raise ValueError(f"incomplete specification: {pid}")
        if r["product"] != product or not pid.startswith(product + "."):
            raise ValueError(f"cross-product specification: {pid}")
        if not isinstance(r["profiles"], list) or any(("tiny" in p) != (product == "tiny") for p in r["profiles"]):
            raise ValueError(f"cross-product profile: {pid}")
        for key in ("profiles", "meaning", "unit", "conditions", "evidence", "sources", "replacement"):
            if not r[key]:
                raise ValueError(f"missing {key}: {pid}")
        if not set(r["sources"]) <= source_map.keys():
            raise ValueError(f"missing source: {pid}")
        if r["status"] == "tbd":
            if r["value"] is not None:
                raise ValueError("TBD must have explicit null value")
        elif r["value"] is None:
            raise ValueError("unknown value cannot be a numeric specification")
        if isinstance(r["value"], (float, int)) and (isinstance(r["value"], bool) or not math.isfinite(r["value"])):
            raise ValueError("invalid numeric specification")
        if isinstance(r["value"], dict):
            if set(r["value"]) != {"min", "typ", "max"}:
                raise ValueError("range requires explicit Min/Typ/Max")
            vals = [r["value"][k] for k in ("min", "typ", "max") if r["value"][k] is not None]
            if any(not isinstance(x, (float, int)) or not math.isfinite(x) for x in vals) or vals != sorted(vals):
                raise ValueError("invalid specification range")
        kinds = {source_map[s]["kind"] for s in r["sources"]}
        if any(source_map[s].get("path", "").startswith("rtl/" + ("mini/" if product == "tiny" else "tiny/")) for s in r["sources"]):
            raise ValueError(f"cross-product source: {pid}")
        if kinds & {"external", "constructed"} and r["status"] not in {"reference", "tbd"}:
            raise ValueError("external/model input cannot be confirmed or calculated")
        if r["status"] == "confirmed" and r["evidence"] not in {"product-target", "rtl", "profile", "simulation", "physical"}:
            raise ValueError("confirmed specification requires scoped evidence")
        if r["status"] == "confirmed" and r["evidence"] in {"simulation", "physical"}:
            evidence = r.get("evidence_record", {})
            if not all(evidence.get(k) for k in ("source_id", "report_sha256", "revision", "profile", "method", "conditions")):
                raise ValueError("simulation or physical promotion requires an identified evidence record")
            report = source_map.get(evidence["source_id"], {})
            if (report.get("kind") != "repository" or report.get("sha256") != evidence["report_sha256"]
                    or report.get("revision") != evidence["revision"] or evidence["profile"] not in r["profiles"]):
                raise ValueError("promotion evidence does not match source/profile")
        if r["status"] == "reference" and not r["assumptions"]:
            raise ValueError("reference data requires explicit assumptions")
        if r["status"] in {"calculated"} or r.get("formula"):
            if not r.get("formula") or not r["dependencies"]:
                raise ValueError("calculation requires formula and dependencies")
        visiting.add(pid)
        dep_states = set()
        for dep in r["dependencies"]:
            if dep["id"] not in by_id:
                raise ValueError(f"unknown or cross-product dependency: {dep['id']}")
            check(dep["id"])
            if by_id[dep["id"]]["unit"] != dep["unit"]:
                raise ValueError(f"unit conflict: {pid}")
            dep_states.add(by_id[dep["id"]]["status"])
        if "reference" in dep_states and r["status"] != "reference":
            raise ValueError("reference input must propagate Reference Only")
        if "tbd" in dep_states and r["status"] != "tbd":
            raise ValueError("TBD input cannot become a number")
        if r["status"] == "confirmed" and dep_states & {"calculated"}:
            raise ValueError("formula result cannot become confirmed without new evidence")
        visiting.remove(pid)
        visited.add(pid)
    for pid in by_id:
        check(pid)


def half_period_clock(input_hz: float, divider: int, *, zero_clamps: bool = False) -> float:
    if not 0 <= divider <= 65535 or (divider == 0 and not zero_clamps) or input_hz <= 0:
        raise ValueError("invalid half-period divider")
    return input_hz / (2 * max(1, divider))


def ideal_bandwidth(width_bits: int, clock_hz: float) -> float:
    if width_bits <= 0 or width_bits % 8 or clock_hz <= 0:
        raise ValueError("invalid lane geometry")
    return width_bits / 8 * clock_hz


def reference_current(f_mhz: float, v: float, t: float, k: float) -> float:
    if min(f_mhz, v, k) < 0 or v == 0:
        raise ValueError("invalid model input")
    return 0.2 * 2 ** ((t - 25) / 25) + k * f_mhz * v / 1.2


def transfer_model(length: int, bus_hz: float, bandwidth: float, cycles: float, efficiency: float) -> tuple[float, float]:
    if min(length, bus_hz, bandwidth, efficiency) <= 0 or cycles < 0 or efficiency > 1:
        raise ValueError("invalid transfer model")
    seconds = cycles / bus_hz + length / (efficiency * bandwidth)
    return seconds, length / seconds


def qfn_geometry(parameters: dict[str, float], pins: list[dict]) -> dict:
    """Top view: pin 1 upper left; bottom mirrors x only; PCB is top view."""
    if len(pins) != 64 or {r["pin"] for r in pins} != set(range(1, 65)):
        raise ValueError("QFN64 must have exactly 64 unique perimeter pins")
    pitch, body = parameters["pitch"], parameters["body"]
    result = []
    for p in sorted(pins, key=lambda p: p["pin"]):
        side, n = divmod(p["pin"] - 1, 16)
        offset = (n - 7.5) * pitch
        x, y = [(-body / 2, -offset), (offset, -body / 2),
                (body / 2, offset), (-offset, body / 2)][side]
        result.append({**p, "side": side, "top": [x, y], "bottom": [-x, y], "pcb": [x, y]})
    if parameters["ep"] >= body - 2 * parameters["lead_length"]:
        raise ValueError("EP overlaps perimeter terminals")
    if parameters["pad_width"] >= pitch or not math.isclose(
            parameters["pad_outer"] - parameters["pad_inner"], 2 * parameters["pad_length"], abs_tol=1e-9):
        raise ValueError("inconsistent copper pad geometry")
    return {"pins": result, "ep": {"name": "EP", "pin": None, "top": [0, 0], "bottom": [0, 0]},
            "dimensions": parameters, "units": "mm", "status": "reference"}


def _record(product, profiles, key, meaning, group, unit, value, status, evidence, sources,
            conditions, *, assumptions=None, dependencies=None, formula=None, replacement=None):
    result = dict(id=product + "." + key, product=product, profiles=profiles, meaning=meaning,
                  group=group, unit=unit, value=value, status=status, evidence=evidence, sources=sources,
                  conditions=conditions, assumptions=assumptions or [], dependencies=dependencies or [],
                  replacement=replacement or "Replace with reviewed revision/profile-matched implementation or characterization evidence.")
    if formula:
        result["formula"] = formula
    return result


def _rtl_source(root, product, config, path, locator):
    return dict(id=product + ":" + path, kind="repository", title=path, version=config["source_revision"],
                revision=config["source_revision"], path=path, locator=locator, sha256=digest(root / path))


def collect(root: Path, product: str, base: dict) -> dict:
    config = base["document"]
    parameters = read(root / BOOKS[product] / "parameters.json")
    models = read(root / MODEL_FILE)
    sources = read(root / SOURCE_FILE)
    authored_id, payload_id = product + ":authored-examples", product + ":payload-model"
    for sid, path, title, locator in (
        (authored_id, f"{BOOKS[product]}/parameters.json", "Authored electrical examples", "absolute, operating, DC and AC record values/conditions"),
        (payload_id, "publications/specification_reference.py", "Constructed application payload model", "resource scenario formulas and assumptions"),
    ):
        sources.append(dict(id=sid, kind="constructed", title=title, path=path,
                            version="Publication schema 1 / " + config["date"], locator=locator, sha256=digest(root / path)))
    records = deepcopy(parameters["records"])
    for r in records:
        r["sources"] = [authored_id if s == "scenario-model" else s for s in r["sources"]]
        if r.get("model") == "board":
            r["sources"] = ["board-model"]
        if "model" in r:
            r["value"] = json.dumps(models[r["model"]], separators=(",", ":"))
    profiles = [config["profile"]]
    clock_path = ("rtl/tiny/top/tiny_clock_reset_subsystem.sv" if product == "tiny"
                  else "rtl/mini/top/soc_clock_reset_subsystem.sv")
    topology = f"rtl/{product}/integration/soc_topology.json"
    paths = [config["profile"], clock_path, topology, "rtl/ip/serial/i2s_clkgen.sv",
             "rtl/ip/serial/i2s_pkg.sv", "rtl/ip/storage/sdio_clock.sv",
             "crt/include/retrosoc/hal/dma.h", "rtl/ip/peripheral/gpio_reg.sv"]
    fabric_source = "rtl/tiny/top/retrosoc_tiny.sv" if product == "tiny" else "rtl/mini/top/soc_data_plane.sv"
    paths.append(fabric_source)
    if product == "tiny":
        paths += ["docs/ip/tiny-soc.md", "crt/src/hal/spi_math.c", "rtl/ip/serial/spi_phase_ctrl.sv"]
    for p in paths:
        sources.append(_rtl_source(root, product, config, p, "selected profile / named clock, route, divider or reset implementation"))
    def fact(key, meaning, unit, value, path, conditions, evidence="rtl", group="quick"):
        r = _record(product, profiles, key, meaning, group, unit, value, "confirmed", evidence,
                    [product + ":" + path], conditions)
        records.append(r)
        return r["id"]
    def calc(key, meaning, unit, value, deps, formula, conditions, group="performance", sources_override=None):
        r = _record(product, profiles, key, meaning, group, unit, value, "calculated", "formula",
                    sources_override or [product + ":" + clock_path], conditions,
                    dependencies=[{"id": k, "unit": u} for k, u in deps], formula=formula)
        records.append(r)
        return r["id"]
    profile = base["facts"]["profile"] if product == "tiny" else base["profiles"]["profile"]
    sram = int(profile["SRAM_SIZE_KIB"]) * 1024
    fact("sram.bytes", "On-chip SRAM", "B", sram, config["profile"], "Selected main reference profile.", "profile")
    fact("gpio.count", "User GPIO", "1", len(base["gpio"]), topology, "GPIO0-31; routes share physical pads.")
    fact("dma.channels", "Central DMA channels", "1",
         base["facts"]["dma"]["NumChannels"] if product == "tiny" else base["mini_bindings"]["dma"]["NumChannels"],
         config["profile"], "Instance-selected central DMA; does not describe dedicated media DMA.", "profile")
    if product == "tiny":
        fact("package.family", "Product package family", "1", "QFN64", "docs/ip/tiny-soc.md",
             "Confirmed product target; final outline/bond map/qualification not released.", "product-target")
        fact("clock.audio", "Audio input in main profile", "Hz", int(profile["AUD_CLK_HZ"]), config["profile"],
             "AUDIO reference on GPIO17 ALT0; profile frequency, not a characterized pad limit.", "profile")
        # Source binding protects the reviewed R2 profiles; these are selectable design points, not ratings.
        clock_text = (root / clock_path).read_text(encoding="utf-8")
        if ".Ics55Parked(1'b0)" not in re.sub(r"\s+", "", clock_text):
            raise ValueError("Tiny runtime PLL backend policy changed; review boot versus functional capability")
        for snippet in ("192_000_000", "240_000_000"):
            if snippet not in clock_text:
                raise ValueError("Tiny clock profile binding changed")
        clock_sets = [("SAFE24", 24e6, 24e6, 24e6), ("PLL192", 192e6, 96e6, 48e6),
                      ("PLL240", 240e6, 120e6, 60e6)]
    else:
        fact("clock.audio", "Audio reference input", "Hz", int(profile["AUD_CLK_HZ"]), config["profile"],
             "Main IHP130 PRODUCT external audio input.", "profile")
        ext = int(profile["EXT_CLK_HZ"])
        hp_id = fact("clock.hp", "HP fabric reference root", "Hz", ext, config["profile"],
                     "Main no-PLL external performance input; independent of LP divider; not a qualified speed grade.", "profile")
        # Performance root selection and divide-by-two/four are actual RTL alternatives.
        clock_sets = [("REF24", 24e6, ext / 2, 24e6), ("PERF_DIV4", ext / 4, ext / 2, ext / 4),
                      ("PERF_DIV2", ext / 2, ext / 2, ext / 2), ("PERF", ext, ext / 2, ext)]
    clocks = []
    for name, cpu, mem, pclk in clock_sets:
        ids = {}
        clock_condition = ("Current external SAFE24 boot; unqualified rate." if name == "SAFE24" else
                           "R2-P7 selectable profile; backend capability and digital lock required; rate unqualified.") if product == "tiny" else (
                           "LP selection at EXT72; PCLK /1 candidate. Independent HP root; rates unqualified.")
        for domain, value in (("cpu", cpu), ("memory", mem), ("pclk", pclk)):
            ids[domain] = fact(f"clock.{name.lower()}.{domain}", f"{name} / {domain} clock", "Hz", value,
                               clock_path, clock_condition,
                               group="clocks")
        rid = calc(f"relative.{name.lower()}", f"{name} / ideal relative CPU throughput", "1", cpu / 24e6,
                   [(ids["cpu"], "Hz"), (product + ".clock.ref", "Hz")], "f_cpu / f_ref",
                   "Identical instruction mix, fixed IPC, no stalls; not CoreMark, DMIPS or a qualified operating point.")
        wid = fact(f"lane.{name.lower()}", f"{name} / shared data lane width", "bit", 32 if product == "tiny" else 64,
                   fabric_source, "Ungated SYS AXI32 fabric data stage." if product == "tiny" else "HP AXI64 fabric data stage; backend clocks/adapters are separate.", group="performance")
        bus_hz, bus_id = (cpu, ids["cpu"]) if product == "tiny" else (ext, hp_id)
        bid = calc(f"bandwidth.{name.lower()}", f"{name} / ideal data-stage bandwidth", "B/s",
                   ideal_bandwidth(32 if product == "tiny" else 64, bus_hz),
                   [(wid, "bit"), (bus_id, "Hz")], "width_bits / 8 * f_fabric",
                   "Fabric lane only; excludes CDC, backend/device waits, arbitration and competing traffic. Not SRAM/device throughput.")
        clocks.append(dict(name=name, cpu_hz=cpu, memory_hz=mem, pclk_hz=pclk, ids=ids,
                           bus_hz=bus_hz, relative_id=rid, bandwidth_id=bid))
    fact("clock.ref", "Always-on reference input", "Hz", 24e6, clock_path,
         "External input / digital reference; oscillator electrical limits remain TBD.")
    # Actual divider arithmetic; illustrative divider choices remain distinct from pad-rate qualification.
    audio = int(profile["AUD_CLK_HZ"])
    peripheral = []
    for bits, sd, ld in ((16, 5, 15), (16, 2, 15), (24, 3, 23), (24, 1, 23)):
        sck = audio / (2 * (sd + 1))
        fs = sck / (2 * (ld + 1))
        deps = [(product + ".clock.audio", "Hz")]
        key = f"i2s.{bits}.{sd}"
        pid = calc(key, f"I2S {bits}-bit stereo / SCLK_DIV={sd}, LRCK_DIV={ld}", "B/s", fs * 2 * bits / 8,
                   deps, f"f_audio / (2*({sd}+1)) / (2*({ld}+1)) * 2*{bits}/8",
                   "Source preset divisors; one direction, packed useful samples. Actual sample rate depends on this product's audio input.",
                   group="wire-rates",
                   sources_override=[product + ":rtl/ip/serial/i2s_clkgen.sv", product + ":rtl/ip/serial/i2s_pkg.sv"])
        peripheral.append(dict(interface="I2S", config=f"{bits}-bit stereo; d={sd}; lr={ld}",
                               clock_hz=sck, payload_bps=fs * bits * 2 / 8, sample_hz=fs, record_id=pid))
    for clock in clocks:
        for divider in (1, 2, 4, 16):
            for interface, lanes in ([("SPI0", 1), ("SDIO0", 4)] if product == "tiny" else [("SDIO0/1", 4)]):
                rate = half_period_clock(clock["pclk_hz"], divider)
                key = f"{interface.lower().replace('/', '-')}.{clock['name'].lower()}.{divider}"
                pid = calc(key, f"{interface} / {clock['name']} / half-period {divider}", "B/s", rate * lanes / 8,
                           [(clock["ids"]["pclk"], "Hz")], f"f_pclk/(2*{divider}) * {lanes}/8",
                           "Uninterrupted SDR wire payload; command/CRC/CS gaps, framing and software excluded. SDIO half-period zero clamps to 1; SPI legal 1..65535.",
                           group="wire-rates",
                           sources_override=[product + (":crt/src/hal/spi_math.c" if interface == "SPI0" else ":rtl/ip/storage/sdio_clock.sv")])
                peripheral.append(dict(interface=interface, config=f"{clock['name']}; half-period={divider}",
                                       clock_hz=rate, payload_bps=rate * lanes / 8, sample_hz=None, record_id=pid))
    # Resource arithmetic is a scenario, never a firmware static-memory measurement.
    for key, meaning, value, formula in [
        ("image.rgb565", "320 x 240 RGB565 / one frame", 320 * 240 * 2, "320*240*2"),
        ("image.double", "320 x 240 RGB565 / double buffer", 320 * 240 * 2 * 2, "320*240*2*2"),
        ("audio.block", "48 ksample/s stereo 16-bit / 10 ms", 48000 * 2 * 2 // 100, "48000*2*2*0.010"),
        ("dma.tcd", "Eight central-DMA TCDs / HAL structure", 8 * 64, "8*64")]:
        ref = key != "dma.tcd"
        r = _record(product, profiles, key, meaning, "resources", "B", value,
                    "reference" if ref else "calculated", "formula",
                    [payload_id] if ref else [product + ":crt/include/retrosoc/hal/dma.h"],
                    "Payload only; alignment, pitch, code, stacks and allocator overhead excluded.",
                    assumptions=["Constructed application geometry, not a shipped application footprint."] if ref else [],
                    dependencies=[{"id": product + ".dma.channels", "unit": "1"}] if not ref else [],
                    formula=formula if not ref else None)
        records.append(r)
    fact("bus.width", "Control AXI/APB data width", "bit", 32, topology,
         "LP/control register transactions; HP native/data widths are separately described.")
    validate_sources(sources, root)
    validate_records(records, sources, product)
    spec = dict(product=product, source_revision=config["source_revision"], profiles=profiles,
                records=records, sources=sources, models=models, clocks=clocks, peripheral=peripheral,
                groups=parameters["groups"], source_paths=sorted(source_inputs(product) | set(paths)))
    spec["pins"] = pin_reference(product, base)
    spec["errata"] = deepcopy(parameters.get("errata", []))
    for item in spec["errata"]:
        if not all(item.get(k) for k in ("id", "title", "applies_to", "trigger", "impact", "workaround", "evidence", "sources")):
            raise ValueError("incomplete implementation erratum")
        if any(not (root / p).is_file() for p in item["sources"]):
            raise ValueError("missing erratum evidence source")
        item["source_revision"] = config["source_revision"]
    spec["source_paths"] = sorted(set(spec["source_paths"]) | {p for e in spec["errata"] for p in e["sources"]})
    if product == "tiny":
        values = {r["id"].removeprefix("tiny.package."): r["value"] for r in records if r["group"] == "mechanical"}
        perimeter = [dict(pin=int(row[i]), name=row[i + 1]) for row in base["package"] for i in (0, 2)]
        for pin in perimeter:
            name = pin["name"]
            pin.update(function=name, gpio_mode="-", direction="TBD", reset="TBD", bias="TBD",
                       limitation="Frozen target; physical binding TBD")
            match = re.fullmatch(r"GPIO(\d+)", name)
            if match:
                number = int(match[1])
                routes = [r for r in spec["pins"] if r["gpio"] == number and r["function"] != "Not routed"]
                pin.update(function=name + "; " + "; ".join(r["mode"] + ": " + r["function"] for r in routes),
                           gpio_mode=" / ".join(["GPIO"] + [r["mode"] + " " + r["direction"] for r in routes]), direction="I/O", reset="Input; OE off",
                           bias="Pull controls off; PDK conditional", limitation="One active owner; bond map TBD")
            elif name.startswith(("VDD", "VSS", "AVDD", "AVSS")):
                pin.update(direction="Supply", reset="N/A", bias="N/A", limitation="Rail / return target; electrical and bond approval pending")
            elif name in {"XPI_SCK", "XPI_CS0_N", "JTAG_TDO"}:
                pin.update(direction="O", limitation="Digital controller output; pad/bond limits TBD")
            elif name.startswith("XPI_D"):
                pin.update(direction="I/O", limitation="Boot-XPI data; direction changes by phase; bonding TBD")
            elif name in {"XIN", "RESET_N", "JTAG_TCK", "JTAG_TMS", "JTAG_TDI", "JTAG_TRST_N"}:
                pin.update(direction="I", reset="External input", limitation="Digital input role; electrical bias and bonding TBD")
        spec["qfn"] = qfn_geometry(values, perimeter)
        paste_area = models["paste"]["count_x"] * models["paste"]["count_y"] * models["paste"]["aperture_mm"] ** 2
        spec["paste_coverage_percent"] = paste_area / values["ep"] ** 2 * 100
    spec["datasets"] = datasets(spec)
    for r in spec["records"]:
        if r["id"].endswith(".model.current"):
            r["display_value"] = (models["current"]["formula"] + "; k [mA/MHz]: "
                + ", ".join(f"{k} = {v}" for k, v in models["current"]["k"].items())
                + f"; core V scan {models['current']['voltages_v']}; temperature scan {models['current']['temperatures_c']} deg C.")
        elif r["id"].endswith(".model.transfer"):
            m = models["transfer"]
            r["display_value"] = (m["formula"] + f"; setup = {m['setup_cycles']} bus cycles; "
                f"efficiency = {m['efficiency']}; payload lengths = {m['length_bytes']} B.")
        elif r["id"].endswith(".model.gpio"):
            r["display_value"] = (f"VOH=VIO-I*R; VOL=I*R. VIO={models['gpio']['vio_v']} V; "
                f"R={models['gpio']['resistance_ohm']} ohm; load scan {models['gpio']['current_ma']} mA.")
        elif r["id"].endswith(".board.values"):
            b = models["board"]
            r["display_value"] = (f"Local bypass {b['local_cap_nf']} nF; domain reservoir {b['domain_cap_uf']} uF; "
                f"bulk {b['bulk_cap_uf']} uF; reset pull-up {b['reset_pull_kohm']} kohm / capacitor {b['reset_cap_nf']} nF; "
                f"optional JTAG series damping {b['jtag_series_ohm']} ohm; NOR CS pull-up {b['nor_cs_pull_kohm']} kohm.")
        elif r["id"].endswith((".assembly.paste", ".assembly.pcb")):
            key = "paste" if r["id"].endswith("paste") else "pcb"
            r["display_value"] = "; ".join(k.replace("_", " ") + " = " + str(v) for k, v in models[key].items())
    return spec


def pin_reference(product: str, base: dict) -> list[dict]:
    reset_names = {"OUTPUT_ENABLE", "ALT_ENABLE", "PULL_UP", "PULL_DOWN"}
    resets = {r["name"]: r["reset"] for r in base["registers"]["gpio"]["registers"] if r["name"] in reset_names}
    if set(resets) != reset_names or any(v not in {"0", "0x00000000"} for v in resets.values()):
        raise ValueError("GPIO reset/bias source contract changed")
    rows = []
    for gpio in base["gpio"]:
        for mode in ("alt0", "alt1"):
            g = gpio[mode]
            outputs = [] if "'" in g["do"] else [g["do"]]
            signals = list(dict.fromkeys(list(g["inputs"]) + outputs))
            names = []
            for signal in signals:
                name = signal.replace("u_", "").replace("_if.", ".")
                for _ in range(2):
                    name = re.sub(r"_(?:di|do|i|o)(?=\[|$)", "", name)
                name = name.upper()
                if product == "tiny":
                    name = {"S_AUDIO_PAD_CLK": "AUDIO.CLKIN", "S_CLKOUT": "CLKOUT",
                            "S_SPI_SCK": "SPI0.SCK", "S_SPI_MOSI": "SPI0.MOSI",
                            "S_SPI_MISO": "SPI0.MISO", "S_SPI_CS_N": "SPI0.CS_N"}.get(name, name)
                    name = re.sub(r"^(SDIO|UART|I2C)\.", r"\g<1>0.", name)
                names.append(name)
            label = " / ".join(dict.fromkeys(names)) or "Not routed"
            rows.append(dict(gpio=gpio["pin"], function=label, mode=mode.upper(),
                             direction="I/O" if outputs and g["inputs"] else "O" if outputs else "I" if signals else "-",
                             reset="GPIO input / OE disabled", pull="Pull bits reset off; PDK capability conditional",
                             restriction=("Shared QPI/OPI group; one protocol owner" if product == "mini" and gpio["pin"] >= 21
                                          else "Quiesce previous owner; ALT disabled at reset"),
                             state="RTL route", rtl="; ".join(signals) or "-"))
    return rows


def datasets(spec: dict) -> list[dict]:
    product = spec["product"]
    m = spec["models"]
    currents, modes, voltage, temperature, transfer, gpio, relative = [], [], [], [], [], [], []
    def point(series, x, y, ids):
        return dict(series=series, x=x, y=y, record_ids=ids)
    for c in spec["clocks"]:
        f = c["cpu_hz"] / 1e6
        for mode, k in m["current"]["k"].items():
            currents.append(point(mode, f, reference_current(f, 1.2, 25, k), [c["ids"]["cpu"], product + ".model.current"]))
        modes.extend([point(c["name"], i, reference_current(f, 1.2, 25, k), [c["ids"]["cpu"], product + ".model.current"])
                      for i, k in enumerate(m["current"]["k"].values())])
        relative.append(point("Fixed IPC", f, c["cpu_hz"] / 24e6, [c["relative_id"]]))
    last = spec["clocks"][-1]
    f = last["cpu_hz"] / 1e6
    for t in m["current"]["temperatures_c"]:
        for v in m["current"]["voltages_v"]:
            voltage.append(point(f"{t} C", v, reference_current(f, v, t, m["current"]["k"]["Run"]),
                                 [last["ids"]["cpu"], product + ".model.current"]))
    for v in m["current"]["voltages_v"]:
        for t in m["current"]["temperatures_c"]:
            temperature.append(point(f"{v} V", t, reference_current(f, v, t, m["current"]["k"]["Run"]),
                                     [last["ids"]["cpu"], product + ".model.current"]))
    bandwidth = next(r["value"] for r in spec["records"] if r["id"] == last["bandwidth_id"])
    for n in m["transfer"]["length_bytes"]:
        seconds, bps = transfer_model(n, last["bus_hz"], bandwidth,
                                     m["transfer"]["setup_cycles"], m["transfer"]["efficiency"])
        transfer.append({**point("Effective payload", n, bps / 1e6,
                                [last["bandwidth_id"], product + ".model.transfer"]), "seconds": seconds})
    for i in m["gpio"]["current_ma"]:
        gpio += [point("VOH", i, m["gpio"]["vio_v"] - i / 1000 * m["gpio"]["resistance_ohm"], [product + ".model.gpio"]),
                 point("VOL", i, i / 1000 * m["gpio"]["resistance_ohm"], [product + ".model.gpio"])]
    return [dict(id=key, title=title, x_label=x, y_label=y, status=status, conditions=condition,
                 points=points) for key, title, x, y, status, condition, points in [
        ("cpu-relative", "Ideal CPU throughput at fixed IPC", "CPU clock (MHz)" if product == "tiny" else "LP clock (MHz)", "Relative throughput (x)", "calculated",
         "Same workload/IPC; no stalls; reference = 24 MHz; no benchmark or timing qualification.", relative),
        ("current-frequency", "Core current versus frequency", "CPU clock (MHz)", "Core current (mA)", "reference",
         "Constructed Hazard3 core model; 1.2 V, 25 C; HP/fabric/SRAM/I/O and other rails excluded.", currents),
        ("current-modes", "Core current by digital activity scenario", "Activity scenario", "Core current (mA)", "reference",
         "Run / WFI / WFI + idle leaf gates; no power isolation, retention or deep-sleep current inferred.", modes),
        ("current-voltage", "Core current versus supply", "Model core supply (V)", "Core current (mA)", "reference",
         f"Constructed Run model; {f:g} MHz; scan is not an approved operating envelope.", voltage),
        ("current-temperature", "Core current versus temperature", "Model temperature (C)", "Core current (mA)", "reference",
         f"Constructed Run model; {f:g} MHz; scan is not a temperature grade.", temperature),
        ("transfer", "Effective transfer bandwidth model", "Payload length (B)", "Effective bandwidth (MB/s)", "reference",
         f"Fabric lane at {last['bus_hz']/1e6:g} MHz; 16 setup cycles, 60% efficiency; not SRAM/device bandwidth.", transfer),
        ("gpio-load", "GPIO resistive output model", "Load current (mA)", "Output voltage (V)", "reference",
         "VIO = 3.3 V; Rout = 40 ohm; 0..12 mA. Not a drive rating or valid linear pad model.", gpio)]]


def export_audits(out: Path, spec: dict, items: list[dict]) -> dict:
    """Bind data to actual rendered locations; keep replacement dependencies explicit."""
    usage = [r for r in items if isinstance(r, dict) and r.get("kind") == "specification-use"]
    figures = [r for r in items if isinstance(r, dict) and r.get("kind") == "specification-figure"]
    known = {r["id"] for r in spec["records"]}
    if any(r["id"] not in known for r in usage):
        raise ValueError("rendered unknown specification")
    states = {r["id"]: r["status"] for r in spec["records"]}
    if any(r["status"] != states[r["id"]] for r in usage):
        raise ValueError("rendered specification status differs from its record")
    used = {r["id"] for r in usage}
    if used != known:
        raise ValueError("unpublished specification records: " + ", ".join(sorted(known - used)))
    expected = {r["id"] for r in spec["datasets"]}
    actual = [r["id"] for r in figures if r.get("category") == "curve"]
    if len(actual) != len(set(actual)) or set(actual) != expected:
        raise ValueError("missing or duplicated specification curve")
    index = {r["id"]: [u for u in usage if u["id"] == r["id"]] for r in spec["records"]}
    replacement = [dict(id=r["id"], status=r["status"], evidence=r["evidence"], sources=r["sources"],
                        assumptions=r["assumptions"], conditions=r["conditions"], replacement=r["replacement"],
                        dependencies=r["dependencies"], uses=index[r["id"]])
                   for r in spec["records"]]
    report = dict(product=spec["product"], source_revision=spec["source_revision"],
                  counts=dict(sorted(Counter(r["status"] for r in spec["records"]).items())),
                  parameters=len(known), rendered_uses=len(usage), figures=figures,
                  result="passed", qualification="Publication consistency only; no new hardware qualification.")
    files = {"specification-data.json": spec, "specification-status.json": report,
             "specification-usage.json": index, "specification-replacement.json": replacement}
    for name, value in files.items():
        write(out / name, value)
    return {name: digest(out / name) for name in files}


def verify_audits(out: Path, expected: dict) -> None:
    for name, sha in expected.items():
        if digest(out / name) != sha:
            raise ValueError("specification audit integrity failure: " + name)


def export_csv(path: Path, dataset: dict) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["status", "series", "x", "y", "seconds", "record_ids"])
        for p in dataset["points"]:
            writer.writerow([dataset["status"], p["series"], format(p["x"], ".12g"), format(p["y"], ".12g"),
                             format(p["seconds"], ".12g") if "seconds" in p else "", ";".join(p["record_ids"])])
