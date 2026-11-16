#!/usr/bin/env python3
"""Prepare, build and verify the independent Tiny Gen1 publication."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from publications.tiny_reference import BOOK, MANAGED, collect, read, validate_configuration  # noqa: E402
from publications.package_reference import directory_hashes, package_records, validate_package_closure  # noqa: E402
from publications.structure_reference import validate_structure  # noqa: E402
from publications.specification_reference import export_audits, verify_audits  # noqa: E402
from publications.specification_plots import render as render_specifications  # noqa: E402
from publications.specification_vectors import render as render_vectors  # noqa: E402
from publications.tiny_publication_reference import validate_chapter_pages, validate_navigation  # noqa: E402
from publications.tiny_diagram_reference import coverage as diagram_coverage, validate_rendered  # noqa: E402
from publications.report_changes import repository_footer_pages, page_ranges, validate_change_scope  # noqa: E402
from publications.page_reference import collect_page_roles, read_page_roles, validate_footer_pages, validate_page_roles  # noqa: E402
from scripts.dependency_lock import load_lock  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file, ensure_git_repo, sha256  # noqa: E402

CACHE = ROOT / ".cache/retrosoc/publications"
LATEST = CACHE / "latest-tiny"


def write(path: Path, value) -> None:
    atomic_write(path, json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def assets(lock: dict) -> dict:
    for name in MANAGED:
        spec = lock["sources"][name]
        location = ROOT / spec["destination"]
        if not (location / ".git").exists():
            raise ValueError(f"Tiny managed input absent: {name}; run setup")
        revision = subprocess.check_output(["git", "-C", str(location), "rev-parse", "HEAD"], text=True).strip()
        dirty = subprocess.check_output(["git", "-C", str(location), "status", "--porcelain"], text=True).strip()
        if revision != spec["revision"] or dirty:
            raise ValueError(f"Tiny managed input differs from its lock: {name}")
    media = ROOT / lock["sources"]["publication_media"]["destination"]
    manifest = read(media / "assets.json")
    for path, expected in manifest["files"].items():
        if sha256(media / path) != expected:
            raise ValueError(f"Tiny media digest mismatch: {path}")
    validate_package_closure(ROOT, package_records(lock))
    return manifest


def prepare(lock: dict) -> None:
    for name in sorted(MANAGED):
        spec = lock["sources"][name]
        ensure_git_repo(spec["url"], ROOT / spec["destination"], spec["revision"], update=False)
    for package in package_records(lock):
        archive = CACHE / "downloads" / f"{package['name']}-{package['version']}.tar.gz"
        download_file(package["url"], archive, package["sha256"], update=False)
        destination = ROOT / package["destination"]
        manifest = destination / ".manifest.json"
        if manifest.is_file() and read(manifest) == {"archive": package["sha256"], "files": directory_hashes(destination)}:
            continue
        if destination.exists():
            raise ValueError("Existing package cache differs from its lock; review the cache before replacing it")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
            unpacked = Path(temp) / "content"
            unpacked.mkdir()
            safe_extract(archive, unpacked)
            write(unpacked / ".manifest.json", {"archive": package["sha256"], "files": directory_hashes(unpacked)})
            unpacked.rename(destination)
    assets(lock)


def inputs(data: dict) -> dict[str, str]:
    paths = set(data["source_paths"])
    paths.update(data["specifications"]["source_paths"])
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / BOOK).rglob("*") if p.suffix in {".typ", ".json"})
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "publications/examples/tiny").glob("*.c"))
    paths.update({"publications/build_tiny_datasheet.py", "publications/check_tiny_examples.py", "tests/test_publication_tiny.py", "publications/tiny_reference.py", "publications/register_reference.py",
                  "publications/waveform_reference.py", "publications/structure_reference.py", "publications/package_reference.py",
                  "publications/report_changes.py", "publications/page_reference.py", "scripts/rtl/generate_memory_map.py",
                  "scripts/rtl/generate_pin_map.py", "scripts/check_clock_reset_domains.py"})
    paths.update({"publications/tiny_v02_reference.py", "tests/test_publication_tiny_refresh.py"})
    paths.update({"publications/tiny_diagram_reference.py", "publications/tiny_publication_reference.py",
                  "publications/circuit_reference.py", "publications/format_reference.py",
                  "publications/storage_reference.py", "publications/implementation_reference.py",
                  "tests/test_publication_tiny_alignment.py"})
    return {path: sha256(ROOT / path) for path in sorted(paths)}


def typst_binary(explicit: str | None, lock: dict) -> str:
    executable = explicit or os.environ.get("TYPST") or shutil.which("typst")
    if not executable:
        raise ValueError("Typst not found; use --typst")
    version = subprocess.check_output([executable, "--version"], text=True).strip()
    if not version.startswith("typst " + lock["publication_tools"]["typst"]["version"] + " "):
        raise ValueError("Tiny requires the locked Typst version")
    return executable


def validate_output(out: Path, config: dict) -> Path:
    out = out.resolve()
    if not out.is_relative_to((ROOT / "build").resolve()):
        raise ValueError("Tiny outputs must be inside build/")
    previous = out / "manifest.json"
    if previous.is_file() and read(previous).get("document", {}).get("document_id") != config["document_id"]:
        raise ValueError("Tiny output cannot overwrite another product's build record")
    return out


def validate_rendered_registers(data: dict, items: list) -> int:
    expected = {(family, r["key"]) for family, value in data["registers"].items() for r in value["registers"]}
    actual = [(r["family"], r["key"]) for r in items if isinstance(r, dict) and r.get("kind") == "tiny-register"]
    if len(actual) != len(set(actual)) or set(actual) != expected:
        raise ValueError("Tiny PDF omitted or duplicated a register definition")
    return len(actual)


def build(config: dict, executable: str, out: Path | None = None) -> Path:
    lock = load_lock()
    media = assets(lock)
    data = collect(config)
    hashes = inputs(data)
    signature = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()[:12]
    out = out or ROOT / "build" / f"datasheet-tiny-{datetime.now(timezone.utc):%Y-%m-%d-%H-%M}-{signature}"
    out = validate_output(out, config)
    out.mkdir(parents=True, exist_ok=True)
    specification_plots = render_specifications(ROOT, out, data["specifications"], config["date"])
    write(out / "data.json", data)
    pdf = out / config["filename"]
    epoch = int(datetime.fromisoformat(config["date"]).replace(tzinfo=timezone.utc).timestamp())
    options = ["--root", str(ROOT), "--font-path", "publications/media/fonts", "--ignore-system-fonts",
               "--package-path", str(CACHE / "packages"), "--package-cache-path", str(CACHE / "packages"),
               "--input", "data=/" + (out / "data.json").relative_to(ROOT).as_posix(), "--creation-timestamp", str(epoch)]
    engineering_vectors = render_vectors(ROOT, out, data["specifications"], executable, options)
    result = subprocess.run([executable, "compile", config["entrypoint"], str(pdf), *options], cwd=ROOT, text=True, capture_output=True, encoding="utf-8")
    atomic_write(out / "typst.log", result.stdout + result.stderr)
    if result.returncode or "warning:" in result.stderr:
        raise ValueError("Tiny Typst build failed or warned:\n" + result.stderr)
    query = ('(headings:query(heading).map(h=>(level:h.level,outlined:h.outlined,title:h.body,label:repr(h.at("label",default:none)),page:h.location().page())),'
             'items:query(metadata).map(it=>it.value),regions:query(<table-continuation-region>).map(region=>{'
             'let pos=region.location().position();(kind:"table-continuation",page:pos.page,x:pos.x.pt(),y:pos.y.pt(),'
             'width:region.width.length.pt(),height:region.height.length.pt())}))')
    result = subprocess.run([executable, "eval", query, "--in", config["entrypoint"], *options], cwd=ROOT, text=True, capture_output=True, encoding="utf-8")
    if result.returncode or "warning:" in result.stderr:
        raise ValueError("Tiny layout query failed:\n" + result.stderr)
    layout = json.loads(result.stdout)
    validate_structure(read(ROOT / BOOK / "structure-contract.json"), layout["headings"], data["chapter_index"])
    validate_navigation(read(ROOT / BOOK / "navigation-contract.json"), layout["headings"])
    validate_chapter_pages(layout["headings"], layout["items"], data["chapter_index"])
    validate_rendered(data["illustrations"], layout["items"])
    validate_rendered_registers(data, layout["items"])
    write(out / "document-structure.json", layout["headings"])
    write(out / "layout.json", layout["items"])
    write(out / "layout-regions.json", layout["regions"])
    write(out / "page-roles.json", collect_page_roles(layout["items"]))
    write(out / "register-index.json", data["register_index"])
    write(out / "ip-pages.json", [r for r in layout["items"] if isinstance(r, dict) and r.get("kind") in {"ip-start", "ip-end"}])
    write(out / "waveform-audit.json", data["waveform_audit"])
    diagrams = [r for r in layout["items"] if isinstance(r, dict) and r.get("kind") == "tiny-diagram"]
    write(out / "diagram-inventory.json", diagrams)
    write(out / "diagram-coverage.json", diagram_coverage(data["illustrations"], read(ROOT / BOOK / "navigation-contract.json")))
    markers = [r for r in layout["items"] if isinstance(r, dict) and r.get("kind") in {"publication-change-start", "publication-change-end"}]
    validate_change_scope(markers, config)
    page_ranges(markers, max(r["page"] for r in markers))
    write(out / "change-markers.json", markers)
    specification_audits = export_audits(out, data["specifications"], layout["items"])
    manifest = dict(engineering_vectors=engineering_vectors, specification_audits=specification_audits, specification_plots=specification_plots, change_markers_sha256=sha256(out / "change-markers.json"), document=config, inputs=hashes, assets=media, pdf_sha256=sha256(pdf),
                    publication_checkout=dict(head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), path=str(ROOT)),
                    typst=lock["publication_tools"]["typst"]["version"], media_revision=lock["sources"]["publication_media"]["revision"],
                    packages={p["identity"]: p["sha256"] for p in package_records(lock)},
                    document_structure_sha256=sha256(out / "document-structure.json"), diagram_inventory_sha256=sha256(out / "diagram-inventory.json"))
    manifest["page_roles_sha256"] = sha256(out / "page-roles.json")
    manifest["presentation"] = {"register_caption_context": "ip-qualified-v1"}
    manifest["layout_regions_sha256"] = sha256(out / "layout-regions.json")
    manifest["records"] = {name: sha256(out / name) for name in
                           ("data.json", "layout.json", "ip-pages.json", "waveform-audit.json", "register-index.json", "diagram-coverage.json")}
    write(out / "manifest.json", manifest)
    atomic_write(LATEST, str(out) + "\n")
    print(f"Built {pdf}")
    return pdf


def check_pdf(pdf: Path, data: dict) -> dict:
    from pypdf import PdfReader
    import pdfplumber
    manifest = read(pdf.parent / "manifest.json")
    verify_audits(pdf.parent, manifest["engineering_vectors"])
    verify_audits(pdf.parent, manifest["specification_audits"])
    verify_audits(pdf.parent, manifest["specification_plots"]["outputs"])
    if sha256(pdf.parent / "change-markers.json") != manifest["change_markers_sha256"]:
        raise ValueError("Tiny change marker integrity failure")
    validate_change_scope(read(pdf.parent / "change-markers.json"), manifest["document"])
    if sha256(pdf) != manifest["pdf_sha256"]:
        raise ValueError("Tiny PDF digest does not match manifest")
    for path, digest in manifest["inputs"].items():
        if sha256(ROOT / path) != digest:
            raise ValueError(f"Tiny input changed after build: {path}")
    reader = PdfReader(pdf)
    if reader.metadata.title != data["document"]["title"] or data["document"]["document_id"] not in reader.metadata.keywords:
        raise ValueError("Tiny PDF identity mismatch")
    roles = read_page_roles(pdf.parent, manifest, len(reader.pages))
    closing = validate_page_roles(roles, len(reader.pages))
    if len(closing) != 1:
        raise ValueError("Tiny requires its unique final closing page")
    validate_footer_pages(repository_footer_pages(reader), len(reader.pages), roles)
    for filename, expected in manifest.get("records", {}).items():
        if sha256(pdf.parent / filename) != expected:
            raise ValueError(f"Tiny output record changed: {filename}")
    for filename, key in [("layout-regions.json", "layout_regions_sha256"),
                          ("document-structure.json", "document_structure_sha256"),
                          ("diagram-inventory.json", "diagram_inventory_sha256")]:
        if sha256(pdf.parent / filename) != manifest[key]:
            raise ValueError(f"Tiny layout record changed: {filename}")
    regions = read(pdf.parent / "layout-regions.json")
    layout = read(pdf.parent / "ip-pages.json")
    register_count = validate_rendered_registers(data, read(pdf.parent / "layout.json"))
    starts = [r["id"] for r in layout if r["kind"] == "ip-start"]
    ends = [r["id"] for r in layout if r["kind"] == "ip-end"]
    if starts != ends or starts != [r["id"] for r in data["chapter_index"]]:
        raise ValueError("Tiny IP chapter coverage missing")
    start_pages = [r["page"] for r in layout if r["kind"] == "ip-start"]
    if len(set(start_pages)) != len(start_pages):
        raise ValueError("Tiny IP chapters must start on independent pages")
    validate_structure(read(ROOT / BOOK / "structure-contract.json"),
                       read(pdf.parent / "document-structure.json"), data["chapter_index"])
    validate_navigation(read(ROOT / BOOK / "navigation-contract.json"), read(pdf.parent / "document-structure.json"))
    validate_chapter_pages(read(pdf.parent / "document-structure.json"), layout, data["chapter_index"])
    validate_rendered(data["illustrations"], read(pdf.parent / "layout.json"))
    if read(pdf.parent / "diagram-coverage.json") != diagram_coverage(data["illustrations"], read(ROOT / BOOK / "navigation-contract.json")):
        raise ValueError("Tiny diagram coverage differs from current reviewed data")
    if not reader.outline:
        raise ValueError("Tiny bookmarks missing")
    bookmark_pages = []
    def walk_bookmarks(items):
        for item in items:
            if isinstance(item, list):
                walk_bookmarks(item)
            else:
                page = reader.get_destination_page_number(item)
                if page is not None:
                    bookmark_pages.append((item.title, page + 1))
    walk_bookmarks(reader.outline)
    detail_titles = {"Features and Block Diagram", "Functional Description", "Protocol and Timing",
                     "Register Summary", "Register Description", "Software"}
    for identifier in starts:
        first = next(r["page"] for r in layout if r["kind"] == "ip-start" and r["id"] == identifier)
        last = next(r["page"] for r in layout if r["kind"] == "ip-end" and r["id"] == identifier)
        if not detail_titles <= {title for title, page in bookmark_pages if first <= page <= last}:
            raise ValueError(f"Tiny IP detail bookmarks missing: {identifier}")
    internal = 0
    for page in reader.pages:
        if not (page.extract_text() or "").strip():
            raise ValueError("Tiny PDF contains a blank/raster-only page")
        for annotation in page.get("/Annots", []):
            item = annotation.get_object()
            destination = item.get("/Dest", item.get("/A", {}).get("/D"))
            if destination is not None:
                if isinstance(destination, list) and (not destination or destination[0].get_object().get("/Type") != "/Page"):
                    raise ValueError("Tiny link has no page destination")
                internal += 1
        for ref in page["/Resources"].get("/Font", {}).get_object().values():
            font = ref.get_object()
            child = font.get("/DescendantFonts", [font])[0].get_object()
            descriptor = child.get("/FontDescriptor", {}).get_object()
            if not any(key in descriptor for key in ("/FontFile", "/FontFile2", "/FontFile3")):
                raise ValueError("Tiny font is not embedded")
    with pdfplumber.open(pdf) as rendered:
        for page in rendered.pages:
            for char in page.chars:
                if not char["text"].strip():
                    continue
                continuation = any(r["kind"] == "table-continuation" and r["page"] == page.page_number
                                   and char["x0"] >= r["x"] - 0.3 and char["x1"] <= r["x"] + r["width"] + 0.3
                                   and char["top"] >= r["y"] - 0.3 and char["bottom"] <= r["y"] + r["height"] + 0.3
                                   for r in regions)
                # A quarter turn makes PDFMiner report the glyph advance as size.
                matrix = char.get("matrix", ())
                quarter_turn = (len(matrix) == 6 and abs(matrix[0]) < 1e-8 and abs(matrix[3]) < 1e-8
                                and abs(matrix[1]) > 1e-8 and abs(matrix[2]) > 1e-8)
                size = char["width"] if quarter_turn else char["size"]
                if size < (8.45 if continuation else 8.95):
                    raise ValueError(f"Tiny undersized text on page {page.page_number}: {char['text']}")
                if char["x0"] < -0.5 or char["x1"] > page.width + 0.5 or char["top"] < -0.5 or char["bottom"] > page.height + 0.5:
                    raise ValueError(f"Tiny text outside page {page.page_number}")
            footer = page.crop((0, page.height - 45, page.width, page.height)).extract_text() or ""
            if page.page_number in closing:
                if footer.strip():
                    raise ValueError("Tiny closing page must have no printed footer")
                if "Disclaimer and Copyright Notice" not in (page.extract_text() or ""):
                    raise ValueError("Tiny closing notice missing")
            elif f"{page.page_number} / {len(rendered.pages)}" not in footer:
                raise ValueError("Tiny printed footer numbering mismatch")
    result = dict(pages=len(reader.pages), internal_links=internal, ip_chapters=len(starts),
                  pdf_sha256=manifest["pdf_sha256"], fonts_embedded=True, register_definitions=register_count, source_inputs=len(manifest["inputs"]),
                  navigation_entries=len(read(ROOT / BOOK / "navigation-contract.json")["entries"]),
                  figures=len(read(pdf.parent / "diagram-inventory.json")), deep_ip_bookmarks=True)
    write(pdf.parent / "check-report.json", result)
    print("Tiny PDF checks passed:", result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["setup", "build", "check"])
    parser.add_argument("--config", type=Path, default=ROOT / BOOK / "tiny.json")
    parser.add_argument("--typst")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    try:
        config, lock = read(args.config), load_lock()
        validate_configuration(config)
        if args.command == "setup":
            prepare(lock)
        elif args.command == "build":
            build(config, typst_binary(args.typst, lock), args.output_dir)
        else:
            data = collect(config)
            if not args.source_only:
                assets(lock)
                check_pdf(args.pdf or Path(LATEST.read_text().strip()) / config["filename"], data)
            print(f"Tiny source checks passed: configuration, {len(data['catalog'])} IPs, registers, maps, interrupts, pads and waveforms")
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"tiny datasheet: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
