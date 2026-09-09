#!/usr/bin/env python3
"""Manually prepare, build and check the Mini Typst datasheet. No EDA tools required."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import load_lock  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file, ensure_git_repo, sha256  # noqa: E402
from scripts.check_clock_reset_domains import validate as validate_clocks  # noqa: E402
from publications.register_reference import collect_registers  # noqa: E402
from publications.chapter_reference import collect_chapters  # noqa: E402
from publications.waveform_reference import collect_waveforms, source_paths as waveform_source_paths  # noqa: E402
from publications.system_reference import collect_system_reference, source_paths as system_source_paths  # noqa: E402
from publications.retrieval_reference import collect_retrieval  # noqa: E402
from publications.report_changes import page_ranges  # noqa: E402
from publications.structure_reference import validate_structure  # noqa: E402
from publications.diagram_reference import collect_diagrams  # noqa: E402
from publications.package_reference import (  # noqa: E402
    directory_hashes, package_records, validate_imports, validate_package_closure,
)

CONFIG = ROOT / "publications/datasheets/mini.json"
CACHE = ROOT / ".cache/retrosoc/publications"
MAP = "rtl/mini/address_map/memory_map.json"
TOPOLOGY = "rtl/mini/integration/soc_topology.json"
PINS = "rtl/mini/pin_map/pin_map.json"
CLOCKS = "rtl/mini/integration/clock_reset_domains.json"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    atomic_write(path, json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def git(*args: str, root: Path = ROOT) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True, encoding="utf-8"
    ).strip()


def load_generator(name: str, relative: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def profile_values(path: Path) -> dict[str, str]:
    """These committed profiles deliberately use only literal Make assignments."""
    result: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)\s*:?=\s*([A-Za-z0-9_.+-]+)", line)
        if not match:
            raise ValueError(f"unsupported profile expression at {path}:{number}")
        if match[1] in result:
            raise ValueError(f"duplicate profile assignment: {match[1]}")
        result[match[1]] = match[2]
    return result


def validate_source(config: dict[str, Any]) -> None:
    revision = config["source_revision"]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("source_revision must be a full reviewed Git commit")
    # Documentation commits may follow the hardware snapshot, but changed technical
    # inputs must be reviewed before advertising them in this datasheet.
    changed = git("diff", "--name-only", revision, "--", "rtl", "crt", "app", "configs", "docs")
    if changed:
        raise ValueError("technical sources differ from the reviewed snapshot:\n" + changed)
    for name, dependency in load_lock()["sources"].items():
        if name.startswith("cluster_") or name in {"hazard3", "mpw"}:
            checkout = ROOT / dependency["destination"]
            if not (checkout / ".git").exists():
                raise ValueError(f"managed source {name} missing; run setup")
            if git("rev-parse", "HEAD", root=checkout) != dependency["revision"] or git(
                "status", "--porcelain", root=checkout
            ):
                raise ValueError(f"managed source {name} differs from its lock; run setup --update")


def validate_catalog(catalog: list[dict], regions: list[dict], irqs: list[dict]) -> None:
    symbols = {r["symbol"] for r in regions}
    irq_names = {i["name"] for i in irqs}
    assigned: set[str] = set()
    assigned_irqs: set[str] = set()
    ids: set[str] = set()
    for entry in catalog:
        if entry["id"] in ids:
            raise ValueError(f"duplicate catalog IP: {entry['id']}")
        ids.add(entry["id"])
        for symbol in entry["regions"]:
            if symbol not in symbols or symbol in assigned:
                raise ValueError(f"unknown or duplicate catalog region: {symbol}")
            assigned.add(symbol)
        for name in entry["irqs"]:
            if name not in irq_names or name in assigned_irqs:
                raise ValueError(f"unknown or duplicate catalog IRQ: {name}")
            assigned_irqs.add(name)
        for path in entry["sources"]:
            if not (ROOT / path).is_file():
                raise ValueError(f"missing IP reference: {path}")
    if assigned != symbols:
        raise ValueError(f"undocumented regions: {sorted(symbols - assigned)}")
    if assigned_irqs != irq_names:
        raise ValueError(f"undocumented IRQs: {sorted(irq_names - assigned_irqs)}")


def collect_data(config: dict[str, Any], *, check_snapshot: bool = True) -> dict:
    if check_snapshot:
        validate_source(config)
    profiles = {
        key: profile_values(ROOT / config[key]) for key in ("profile", "hp_profile", "mpw_profile")
    }
    product = profiles["profile"]
    if product.get("MINI_MODE") != "PRODUCT" or product.get("HAVE_HP") != "YES":
        raise ValueError("datasheet requires the reviewed dual-hart PRODUCT profile")
    address = load_generator("datasheet_memory", "rtl/mini/address_map/generate_memory_map.py")
    topology = load_generator("datasheet_topology", "rtl/mini/integration/generate_soc_topology.py")
    pinmap = load_generator("datasheet_pins", "rtl/mini/pin_map/generate_pin_map.py")
    reset, regions, _ = address.read_map(ROOT / MAP, int(product["SRAM_SIZE_KIB"]))
    _, _, _, gpio, _, _, irqs, policies = topology.read_topology(ROOT / TOPOLOGY, ROOT / MAP)
    pads, _ = pinmap.read_map(ROOT / PINS)
    validate_clocks(ROOT / CLOCKS, ROOT)
    catalog = read_json(ROOT / "publications/datasheets/ip-catalog.json")
    irq_data = [dataclasses.asdict(i) for i in sorted(irqs, key=lambda i: i.core_bit)]
    validate_catalog(catalog, regions, irq_data)
    register_data = collect_registers()
    system_reference = collect_system_reference(ROOT, config["source_revision"])
    waveforms, waveform_audit = collect_waveforms(ROOT)
    for region in regions:
        region["base_hex"] = f"0x{region['base']:08X}"
        region["end_hex"] = f"0x{region['end']:08X}"
        region["size_label"] = size_label(region["size"])
        region["availability"] = "Reserved" if region["kind"] == "reserved" else "Integrated"
        if region["symbol"] == "APB4_USER_IP":
            region["availability"] = "Compatibility window; no PRODUCT user IP"
        if region["symbol"] == "SRAM" and product["HAVE_SRAM_IF"] != "YES":
            region["availability"] = "Disabled in selected profile"
    system_reference["retrieval"] = collect_retrieval(
        ROOT, system_reference["retrieval"], register_data, regions, catalog,
        read_json(ROOT / "rtl/mini/integration/user_extensions_legacy.json"),
        config["source_revision"], system_reference["support"],
    )
    system_reference["illustrations"] = collect_diagrams(ROOT, system_reference["illustrations"], regions)
    return {
        "document": config,
        "profiles": profiles,
        "reset_address": f"0x{reset:08X}",
        "regions": sorted(regions, key=lambda r: r["base"]),
        "interrupts": irq_data,
        "policies": [dataclasses.asdict(p) for p in policies],
        "targets": list(topology.DATA_TARGET_NAMES),
        "gpio": [
            {
                **dataclasses.asdict(g),
                "alt0_label": gpio_label(g.alt0),
                "alt1_label": gpio_label(g.alt1),
            }
            for g in gpio
        ],
        "pads": [
            dataclasses.asdict(p)
            for p in pads
            if p.feature is None or product.get(p.feature) == "YES"
        ],
        "clocks": read_json(ROOT / CLOCKS)["domains"],
        "catalog": catalog,
        "extensions": read_json(ROOT / "rtl/mini/integration/user_extensions.json"),
        "mpw": read_json(ROOT / "rtl/mini/integration/user_extensions_legacy.json"),
        "managed_sources": [
            d for n, d in load_lock()["sources"].items() if n.startswith("cluster_") or n == "mpw"
        ],
        "registers": register_data,
        "chapters": collect_chapters(register_data),
        "waveforms": waveforms,
        "waveform_audit": waveform_audit,
        "overview_groups": read_json(ROOT / "publications/datasheets/overview-groups.json"),
        "system_reference": system_reference,
        "wave_renderer": "/" + load_lock()["archives"]["typst_wavy"]["destination"] + "/wavy.js",
    }


def size_label(size: int) -> str:
    for unit, divisor in (("MiB", 1 << 20), ("KiB", 1 << 10)):
        if size % divisor == 0:
            return f"{size // divisor} {unit}"
    return f"{size} B"


def gpio_label(mode: Any) -> str:
    signals = list(mode.inputs) + ([] if "'" in mode.do else [mode.do])
    names = []
    for signal in signals:
        name = re.sub(r"^u_", "", signal).replace("_if.", ".")
        name = re.sub(r"_(di_i|do_o|oe_o|i|o)(?=\[|$)", "", name).upper()
        if name not in names:
            names.append(name)
    return " / ".join(names) or "-"


def prepare(lock: dict, update: bool) -> None:
    for name, dependency in lock["sources"].items():
        if name.startswith("cluster_") or name in {"hazard3", "mpw"}:
            ensure_git_repo(
                dependency["url"],
                ROOT / dependency["destination"],
                dependency["revision"],
                update=update,
            )
    media = lock["sources"]["publication_media"]
    ensure_git_repo(media["url"], ROOT / media["destination"], media["revision"], update=update)
    for package in package_records(lock):
        name = package["name"]
        archive = CACHE / "downloads" / f"{name}-{package['version']}.tar.gz"
        download_file(package["url"], archive, package["sha256"], update=update)
        destination = ROOT / package["destination"]
        manifest = destination / ".manifest.json"
        if manifest.is_file():
            saved = read_json(manifest)
            if saved == {"archive": package["sha256"], "files": directory_hashes(destination)}:
                continue
        if destination.exists():
            if not update:
                raise ValueError(f"modified package cache: {destination}; use setup --update")
            resolved = destination.resolve()
            if not resolved.is_relative_to((CACHE / "packages").resolve()):
                raise ValueError("package destination escapes the publication cache")
            shutil.rmtree(resolved)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
            unpacked = Path(temp) / "content"
            unpacked.mkdir()
            safe_extract(archive, unpacked)
            write_json(
                unpacked / ".manifest.json",
                {"archive": package["sha256"], "files": directory_hashes(unpacked)},
            )
            unpacked.rename(destination)
    check_assets(lock)


def check_assets(lock: dict) -> dict:
    media = lock["sources"]["publication_media"]
    location = ROOT / media["destination"]
    if not (location / ".git").exists():
        raise ValueError("media repository missing; run setup")
    if git("rev-parse", "HEAD", root=location) != media["revision"]:
        raise ValueError("media revision differs from dependency lock; run setup --update")
    if git("status", "--porcelain", root=location):
        raise ValueError("media has local changes; commit and review them before updating the lock")
    manifest = read_json(location / "assets.json")
    for relative, expected in manifest["files"].items():
        path = location / relative
        if not path.is_file() or sha256(path) != expected:
            raise ValueError(f"missing or modified media asset: {relative}")
    validate_package_closure(ROOT, package_records(lock))
    return manifest


def resolve_typst(explicit: str | None, lock: dict) -> str:
    executable = explicit or os.environ.get("TYPST") or shutil.which("typst")
    if not executable:
        raise ValueError("Typst not found; pass --typst PATH or set TYPST")
    version = subprocess.check_output([executable, "--version"], text=True).strip()
    expected = lock["publication_tools"]["typst"]["version"]
    if not version.startswith(f"typst {expected} "):
        raise ValueError(f"expected Typst {expected}, found {version}")
    return str(executable)


def source_hashes(
    config: dict, catalog: list[dict], registers: dict | None = None
) -> dict[str, str]:
    paths = {
        MAP,
        TOPOLOGY,
        PINS,
        CLOCKS,
        config["profile"],
        config["hp_profile"],
        config["mpw_profile"],
        "rtl/mini/integration/user_extensions.json",
        "rtl/mini/integration/user_extensions_legacy.json",
        "dependencies/dependencies.lock.json",
    }
    for entry in catalog:
        paths.update(entry["sources"])
    paths.update(waveform_source_paths(read_json(ROOT / "publications/datasheets/waveforms.json")))
    paths.update(system_source_paths(read_json(ROOT / "publications/datasheets/system-reference.json")))
    paths.update(
        p.relative_to(ROOT).as_posix()
        for p in (ROOT / "publications").rglob("*")
        if p.is_file()
        and p.suffix in {".typ", ".json", ".py", ".c"}
        and "media" not in p.relative_to(ROOT / "publications").parts
    )
    for spec in read_json(ROOT / "publications/datasheets/register-profiles.json").values():
        paths.update(spec.get("defines", []) + spec["rtl"] + spec.get("support", []))
        paths.add(spec["document"])
    if registers is not None:
        for reference in registers.values():
            paths.update(reference["sources"])
    return {p: sha256(ROOT / p) for p in sorted(paths)}


def build(config: dict, lock: dict, executable: str, out: Path | None) -> Path:
    assets = check_assets(lock)
    data = collect_data(config)
    check_document_sources(config, data)
    inputs = source_hashes(config, data["catalog"], data["registers"])
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()[:12]
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H-%M")
    out = (out or ROOT / "build" / f"datasheet-mini-{stamp}-{digest}").resolve()
    if not out.is_relative_to((ROOT / "build").resolve()):
        raise ValueError("--output-dir must be below the repository build directory")
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / "data.json", data)
    write_json(out / "waveform-audit.json", data["waveform_audit"])
    pdf = out / config["filename"]
    epoch = int(datetime.fromisoformat(config["date"]).replace(tzinfo=timezone.utc).timestamp())
    command = [
        executable,
        "compile",
        config["entrypoint"],
        str(pdf),
        "--root",
        str(ROOT),
        "--font-path",
        "publications/media/fonts",
        "--ignore-system-fonts",
        "--package-path",
        str(CACHE / "packages"),
        "--package-cache-path",
        str(CACHE / "packages"),
        "--input",
        f"data=/{(out / 'data.json').relative_to(ROOT).as_posix()}",
        "--creation-timestamp",
        str(epoch),
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, encoding="utf-8")
    atomic_write(out / "typst.log", result.stdout + result.stderr)
    if result.returncode or "warning:" in result.stderr:
        raise ValueError("Typst build failed or warned:\n" + result.stderr)
    query_command = [
        executable,
        "eval",
        '(items:query(metadata).map(it=>it.value), '
        'headings:query(heading).map(h=>(level:h.level,outlined:h.outlined,title:h.body,'
        'label:repr(h.at("label",default:none)),page:h.location().page())), '
        'regions:query(<table-continuation-region>).map(region=>{'
        'let pos=region.location().position(); '
        '(kind:"table-continuation",page:pos.page,x:pos.x.pt(),y:pos.y.pt(),'
        'width:region.width.length.pt(),height:region.height.length.pt())}))',
        "--in",
        config["entrypoint"],
        *command[4:],
    ]
    queried = subprocess.run(
        query_command, cwd=ROOT, text=True, capture_output=True, encoding="utf-8"
    )
    if queried.returncode or "warning:" in queried.stderr:
        raise ValueError("Typst page-map query failed:\n" + queried.stderr)
    layout_report = json.loads(queried.stdout)
    validate_structure(read_json(ROOT / "publications/datasheets/structure-contract.json"),
                       layout_report["headings"], read_json(ROOT / "publications/datasheets/chapter-index.json"))
    write_json(out / "document-structure.json", layout_report["headings"])
    layout_items = layout_report["items"]
    page_map = [
        item
        for item in layout_items
        if isinstance(item, dict) and item.get("kind") in {"ip-start", "ip-end"}
    ]
    write_json(out / "ip-pages.json", page_map)
    # Read final labeled rectangles without feeding positions back into layout.
    write_json(out / "layout-regions.json", layout_report["regions"])
    change_markers = [item for item in layout_items if isinstance(item, dict)
                      and item.get("kind") in {"publication-change-start", "publication-change-end"}]
    # Pair/validate here; the final report also checks actual PDF pages and printed footers.
    page_ranges(change_markers, max(item["page"] for item in change_markers))
    write_json(out / "change-markers.json", change_markers)
    manifest = {
        "document": config,
        "inputs": inputs,
        "media_revision": lock["sources"]["publication_media"]["revision"],
        "assets": assets,
        "typst": lock["publication_tools"]["typst"]["version"],
        "packages": {p["identity"]: p["sha256"] for p in package_records(lock)},
        "package_runtime_imports": validate_package_closure(ROOT, package_records(lock)),
        "pdf_sha256": sha256(pdf),
        "layout_regions_sha256": sha256(out / "layout-regions.json"),
        "change_markers_sha256": sha256(out / "change-markers.json"),
        "document_structure_sha256": sha256(out / "document-structure.json"),
    }
    write_json(out / "manifest.json", manifest)
    atomic_write(CACHE / "latest", str(out) + "\n")
    print(f"Built {pdf}")
    return pdf


def check_document_sources(config: dict, data: dict) -> None:
    sources = list((ROOT / "publications/datasheets").rglob("*.typ"))
    combined = "\n".join(p.read_text(encoding="utf-8") for p in sources)
    validate_imports(combined, package_records(load_lock()))
    if re.search(r"#lorem\(|Lorem ipsum|balba|TO BE COMPLETED", combined):
        raise ValueError("unstructured placeholder remains in Typst source")
    for entry in data["catalog"]:
        if f"<{entry['id']}>" not in combined:
            raise ValueError(f"missing IP section label: {entry['id']}")
    aliases = {
        "psram": "QPI PSRAM",
        "spisd": "SPI-SD",
        "opipsram": "OPI PSRAM",
        "dma": "Central DMA",
        "clint": "LP CLINT",
        "hp_aclint": "HP ACLINT",
        "hp_plic": "HP PLIC",
        "hp_mailbox": "LP/HP Mailbox",
        "ps2": "PS/2",
        "resource_ctrl": "Resource Controller",
        "fabric_monitor": "Fabric Monitor",
        "crypto": "Crypto",
        "ext_l": "EXT-L",
        "ext_h": "EXT-H",
    }
    topology = read_json(ROOT / TOPOLOGY)
    names = [
        t["name"]
        for key in ("apb4_periph_targets", "apb4_system_targets")
        for t in topology[key]
        if not t.get("disabled", False) and t["name"] != "user_ip"
    ]
    expected = {aliases.get(name, name.upper()) for name in names} | {
        "Hazard3",
        "VexiiRiscv",
        "JTAG",
        "RCU",
    }
    actual = [name for group in data["overview_groups"] for name in group["items"]]
    if len(actual) != len(set(actual)) or set(actual) != expected:
        raise ValueError(
            f"Overview inventory mismatch: missing {sorted(expected - set(actual))}, extra {sorted(set(actual) - expected)}"
        )
    for path in sources:
        for target in re.findall(
            r'(?:include|import)\s+"([^"@][^"]+)"', path.read_text(encoding="utf-8")
        ):
            if not (path.parent / target).is_file():
                raise ValueError(f"broken Typst include: {path}: {target}")


def validate_page_map(items: list[dict], index: list[dict]) -> None:
    starts = {item["id"]: item["page"] for item in items if item["kind"] == "ip-start"}
    ends = {item["id"]: item["page"] for item in items if item["kind"] == "ip-end"}
    expected = {item["id"] for item in index}
    if set(starts) != expected or set(ends) != expected or len(items) != 2 * len(expected):
        raise ValueError("missing or duplicated IP page markers")
    previous = 0
    for chapter in index:
        identifier = chapter["id"]
        if starts[identifier] <= previous or ends[identifier] < starts[identifier]:
            raise ValueError(f"IP chapter does not start on a new page: {identifier}")
        previous = ends[identifier]


def validate_character_size(char: dict, number: int, regions: list[dict]) -> None:
    """Only continuation text inside a renderer-marked box may be below 9 pt."""
    if not char["text"].strip() or char["size"] >= 8.95:
        return
    continuation = any(
        region["kind"] == "table-continuation"
        and region["page"] == number
        and char["x0"] >= region["x"] - 0.5
        and char["x1"] <= region["x"] + region["width"] + 0.5
        and char["top"] >= region["y"] - 0.5
        and char["bottom"] <= region["y"] + region["height"] + 0.5
        for region in regions
    )
    minimum = 8.5 if continuation else 9.0
    if char["size"] < minimum - 0.05:
        raise ValueError(f"text smaller than {minimum:g} pt on page {number}")


def check_pdf(pdf: Path, config: dict, data: dict) -> dict:
    try:
        from pypdf import PdfReader
        import pdfplumber
    except ImportError as error:
        raise ValueError(
            "PDF checks require pypdf and pdfplumber; use the bundled runtime"
        ) from error
    manifest = read_json(pdf.parent / "manifest.json")
    if manifest["inputs"] != source_hashes(config, data["catalog"], data["registers"]):
        raise ValueError("PDF inputs have changed; rebuild before checking this PDF")
    if manifest["pdf_sha256"] != sha256(pdf):
        raise ValueError("PDF differs from its build manifest")
    region_path = pdf.parent / "layout-regions.json"
    if not region_path.is_file() or manifest.get("layout_regions_sha256") != sha256(region_path):
        raise ValueError("PDF layout regions missing or changed; rebuild before checking")
    layout_regions = read_json(region_path)
    validate_page_map(
        read_json(pdf.parent / "ip-pages.json"),
        read_json(ROOT / "publications/datasheets/chapter-index.json"),
    )
    reader = PdfReader(pdf)
    marker_path = pdf.parent / "change-markers.json"
    if not marker_path.is_file() or manifest.get("change_markers_sha256") != sha256(marker_path):
        raise ValueError("PDF change markers missing or changed; rebuild before checking")
    page_ranges(read_json(marker_path), len(reader.pages))
    structure_path = pdf.parent / "document-structure.json"
    if not structure_path.is_file() or manifest.get("document_structure_sha256") != sha256(structure_path):
        raise ValueError("PDF structure record missing or changed; rebuild before checking")
    validate_structure(read_json(ROOT / "publications/datasheets/structure-contract.json"),
                       read_json(structure_path), read_json(ROOT / "publications/datasheets/chapter-index.json"))
    if reader.metadata.title != config["title"] or not reader.metadata.author:
        raise ValueError("PDF title or author metadata missing or inconsistent")
    if not reader.outline:
        raise ValueError("PDF bookmarks missing")
    internal, external = 0, set()
    for page in reader.pages:
        text = page.extract_text() or ""
        if not text.strip():
            raise ValueError("empty or raster-only PDF page")
        for annotation in page.get("/Annots", []):
            item = annotation.get_object()
            action = item.get("/A", {})
            if item.get("/Dest") or action.get("/S") == "/GoTo":
                internal += 1
            if action.get("/S") in {"/Launch", "/GoToR"}:
                raise ValueError("PDF contains a local file or remote-document action")
            if "/URI" in action:
                uri = str(action["/URI"])
                if urlparse(uri).scheme not in {"https", "mailto"}:
                    raise ValueError(f"invalid PDF URL: {uri}")
                external.add(uri)
        resources = page["/Resources"].get_object()
        for font_ref in resources.get("/Font", {}).values():
            font = font_ref.get_object()
            descendants = font.get("/DescendantFonts", [font])
            for child in descendants:
                descriptor = child.get_object().get("/FontDescriptor")
                if descriptor is None or not any(
                    key in descriptor.get_object()
                    for key in ("/FontFile", "/FontFile2", "/FontFile3")
                ):
                    raise ValueError("PDF contains an unembedded font")
    if internal == 0 or not external:
        raise ValueError("PDF navigation links missing")
    with pdfplumber.open(pdf) as document:
        all_text = ""
        for number, page in enumerate(document.pages, 1):
            for char in page.chars:
                if (
                    char["x0"] < -0.5
                    or char["x1"] > page.width + 0.5
                    or char["top"] < -0.5
                    or char["bottom"] > page.height + 0.5
                ):
                    raise ValueError(f"text clipped outside page {number}")
                validate_character_size(char, number, layout_regions)
            all_text += page.extract_text() or ""
        normalized = re.sub(r"[\s\u200b\u00ad]", "", all_text)
        expected = [p["name"] for p in data["pads"]]
        expected += [r["symbol"] for r in data["regions"]]
        for value in expected:
            if value not in normalized:
                raise ValueError(f"generated engineering entry absent from PDF: {value}")
    report = {
        "pages": len(reader.pages),
        "internal_links": internal,
        "external_links": sorted(external),
        "pdf_sha256": sha256(pdf),
    }
    write_json(pdf.parent / "check-report.json", report)
    print(f"PDF checks passed: {len(reader.pages)} pages, {internal} internal links")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("setup", "build", "check"))
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--typst")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    try:
        config = read_json(args.config)
        lock = load_lock()
        if args.command == "setup":
            resolve_typst(args.typst, lock)
            prepare(lock, args.update)
        elif args.command == "build":
            build(config, lock, resolve_typst(args.typst, lock), args.output_dir)
        else:
            data = collect_data(config)
            check_document_sources(config, data)
            if not args.source_only:
                check_assets(lock)
                pdf = args.pdf or Path((CACHE / "latest").read_text().strip()) / config["filename"]
                check_pdf(pdf, config, data)
            print("Source checks passed: complete IP, address, IRQ, pad and topology coverage")
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"datasheet: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
