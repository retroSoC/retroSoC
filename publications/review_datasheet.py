#!/usr/bin/env python3
"""Render every page and record baseline body matches without claiming manual review."""
from __future__ import annotations

import argparse
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path
import re
import os
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publications.specification_reference import digest, read, write  # noqa: E402


def normalize(text: str) -> str:
    """Ignore running furniture, automatic numbering and the declared caption qualifier."""
    lines = text.splitlines()
    if lines and lines[0].startswith("Rill"):
        lines = lines[1:]
    body = "\n".join(lines).split("https://github.com/retroSoC/retroSoC")[0]
    body = re.sub(r"(?m)^(\d+(?:\.\d+)*\.?)\s+", "", body)
    body = re.sub(r"(Table\s*\d+\s*:\s*)[A-Z0-9_/-]+\s*/\s*", r"\1", body)
    body = re.sub(r"\s*-\s*register overview", "", body)
    body = re.sub(r"\b(?:Table|Figure)\s+\d+\s*:", "", body)
    # Resolved deep-section references are pagination/navigation, not changed prose.
    body = re.sub(r"\b\d+(?:\.\d+){2,}\b", "<section>", body)
    return re.sub(r"\s+", " ", body).strip()


def body_match(old_text: list[str], new_text: list[str], old_ip: list[dict], new_ip: list[dict]) -> list[dict]:
    old = [normalize(t) for t in old_text]
    new = [normalize(t) for t in new_text]
    index = defaultdict(list)
    for n, t in enumerate(old, 1):
        index[t].append(n)
    starts = sorted((r["page"], r["id"]) for r in new_ip if r["kind"] == "ip-start")
    old_starts = {r["id"]: r["page"] for r in old_ip if r["kind"] == "ip-start"}
    rows = []
    for n, text in enumerate(new, 1):
        if text in index:
            rows.append(dict(page=n, baseline_page=index[text][0], status="exact-normalized-body", ratio=1.0))
            continue
        owner = next(((p, i) for p, i in reversed(starts) if p <= n), None)
        # Only compare inside the actual IP scope, never extend the last IP into appendices.
        ends = [r["page"] for r in new_ip if r["kind"] == "ip-end" and owner and r["id"] == owner[1]]
        candidates = []
        if owner and owner[1] in old_starts and ends and n <= ends[0]:
            projected = old_starts[owner[1]] + n - owner[0]
            candidates = range(max(1, projected - 2), min(len(old), projected + 2) + 1)
        score, prior = 0.0, None
        for p in candidates:
            similarity = SequenceMatcher(None, old[p - 1], text, autojunk=False).ratio()
            if similarity > score:
                score, prior = similarity, p
        rows.append(dict(page=n, baseline_page=prior, status="near-body" if score >= .985 else "review-required",
                         ratio=round(score, 6)))
    return rows


def render(pdf: Path, baseline: Path, dpi: int = 96) -> dict:
    from PIL import Image, ImageDraw
    import pypdfium2 as pdfium
    from pypdf import PdfReader

    manifest = read(pdf.parent / "manifest.json")
    if digest(pdf) != manifest["pdf_sha256"] or digest(baseline) != read(baseline.parent / "manifest.json")["pdf_sha256"]:
        raise ValueError("review PDF differs from manifest")
    output = pdf.parent / "visual"
    color, gray = output / "color", output / "gray"
    color.mkdir(parents=True, exist_ok=True)
    gray.mkdir(exist_ok=True)
    old_reader, reader = PdfReader(baseline), PdfReader(pdf)
    old_text = [p.extract_text() or "" for p in old_reader.pages]
    new_text = [p.extract_text() or "" for p in reader.pages]
    matches = body_match(old_text, new_text, read(baseline.parent / "ip-pages.json"), read(pdf.parent / "ip-pages.json"))
    poppler = os.environ.get("PDFTOPPM") or shutil.which("pdftoppm") or shutil.which("pdftoppm.exe")
    renderer = "Poppler" if poppler else "PDFium / fresh document per page"
    renderer_version = None
    if poppler:
        version = subprocess.run([poppler, "-v"], capture_output=True, text=True)
        renderer_version = (version.stdout + version.stderr).strip()
        with (output / "poppler.log").open("w", encoding="utf-8") as log:
            subprocess.run([poppler, "-r", str(dpi), "-png", str(pdf), str(color / "render")],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    pages = []
    candidates = {int(p.stem.split("-")[-1]): p for p in color.glob("render-*.png")} if poppler else {}
    for i in range(len(reader.pages)):
        if poppler:
            rendered = candidates[i + 1]
            with Image.open(rendered) as original:
                im = original.convert("RGB")
        else:
            # Inspect each fallback page with an independent rendering state.
            raster = pdfium.PdfDocument(pdf)
            page = raster[i]
            bitmap = page.render(scale=dpi / 72)
            im = bitmap.to_pil().convert("RGB")
        name = f"p{i + 1:04}.png"
        im.save(color / name)
        im.convert("L").save(gray / name)
        pages.append(dict(page=i + 1, width=im.width, height=im.height,
                          color_sha256=digest(color / name), gray_sha256=digest(gray / name)))
        if poppler:
            rendered.unlink()
        else:
            bitmap.close()
            page.close()
            raster.close()
    required = [r["page"] for r in matches if r["status"] == "review-required"]
    # Contact sheets are navigation aids; review-required pages must also be read at native size.
    for start in range(0, len(required), 12):
        sheet = Image.new("RGB", (1000, 1480), "white")
        draw = ImageDraw.Draw(sheet)
        for n, p in enumerate(required[start:start + 12]):
            im = Image.open(color / f"p{p:04}.png")
            im.thumbnail((238, 340))
            x, y = (n % 4) * 250, (n // 4) * 490
            sheet.paste(im, (x, y + 24))
            draw.text((x + 6, y + 4), f"Page {p}", fill="black")
        sheet.save(output / f"contact-{start // 12 + 1:03}.png")
    report = dict(pdf_sha256=digest(pdf), baseline_sha256=digest(baseline), dpi=dpi,
                  renderer=renderer, renderer_version=renderer_version,
                  grayscale="PIL luminance conversion of the same full-resolution color raster",
                  page_count=len(pages), pages=pages, baseline_matches=matches,
                  exact_body_matches=sum(r["status"] == "exact-normalized-body" for r in matches),
                  near_body_matches=sum(r["status"] == "near-body" for r in matches),
                  review_required_pages=required, manual_review="pending; raster generation is not manual acceptance",
                  normalization="Running furniture, automatic section/table/figure references and declared IP caption qualification excluded; source/PDF checks remain independent.")
    write(output / "render-report.json", report)
    write(output / "render-index.json", {f"{mode}/{p.name}": digest(p) for mode in ("color", "gray")
                                      for p in sorted((output / mode).glob("*.png"))})
    print(f"Rendered {len(pages)} color + {len(pages)} grayscale pages; {len(required)} require native-size review.", flush=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--dpi", type=int, default=96)
    args = parser.parse_args()
    if args.dpi < 96:
        parser.error("full-size review requires at least 96 dpi")
    render(args.pdf.resolve(), args.baseline.resolve(), args.dpi)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
