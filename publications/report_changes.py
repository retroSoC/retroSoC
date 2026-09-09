#!/usr/bin/env python3
"""Bind final content/navigation page ranges to a baseline and the delivered PDF."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

REPOSITORY_URL = "https://github.com/retroSoC/retroSoC"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def page_ranges(markers: list[dict], page_count: int) -> list[dict]:
    starts, ends, rows = {}, {}, []
    for marker in markers:
        name, page = marker["id"], marker["page"]
        if type(page) is not int or not 1 <= page <= page_count:
            raise ValueError("change marker page is outside the PDF")
        if marker["kind"] == "publication-change-start":
            if name in starts or marker.get("category") not in {"added", "modified", "cross-reference", "navigation"}:
                raise ValueError("duplicate change start or invalid category")
            starts[name] = marker
        elif marker["kind"] == "publication-change-end":
            if name in ends or name not in starts:
                raise ValueError("duplicate or unmatched change end")
            ends[name] = marker
        else:
            raise ValueError("unknown change marker kind")
    if starts.keys() != ends.keys():
        raise ValueError("change region lacks an end marker")
    for name, start in starts.items():
        if ends[name]["page"] < start["page"]:
            raise ValueError("reversed change page range")
        rows.append({"id": name, "title": start["title"], "category": start["category"],
                     "start_page": start["page"], "end_page": ends[name]["page"]})
    return sorted(rows, key=lambda row: (row["start_page"], row["end_page"], row["id"]))


def verified_pdf(path: Path):
    from pypdf import PdfReader
    manifest = json.loads((path.parent / "manifest.json").read_text(encoding="utf-8"))
    actual = digest(path)
    if manifest["pdf_sha256"].lower() != actual:
        raise ValueError("PDF does not match its build manifest")
    return PdfReader(path), actual


def repository_footer_pages(reader) -> list[int]:
    pages = []
    for number, page in enumerate(reader.pages, 1):
        for reference in page.get("/Annots", []):
            annotation = reference.get_object()
            if annotation.get("/A", {}).get("/URI") != REPOSITORY_URL:
                continue
            rect = annotation.get("/Rect", [])
            if len(rect) == 4 and 0 <= float(rect[1]) < float(rect[3]) < 70:
                pages.append(number)
                break
    return pages


def report_changes(pdf: Path, baseline: Path) -> dict:
    reader, final_hash = verified_pdf(pdf)
    old, baseline_hash = verified_pdf(baseline)
    marker_file = pdf.parent / "change-markers.json"
    manifest = json.loads((pdf.parent / "manifest.json").read_text(encoding="utf-8"))
    if manifest["change_markers_sha256"] != digest(marker_file):
        raise ValueError("change markers do not match the delivered manifest")
    markers = json.loads(marker_file.read_text(encoding="utf-8"))
    ranges = page_ranges(markers, len(reader.pages))
    if not ranges:
        raise ValueError("no tracked changes in this publication")
    # Inspect footer text on every reported page; viewer indexes are kept separately.
    labels = {}
    for row in ranges:
        for page in range(row["start_page"], row["end_page"] + 1):
            if page in labels:
                continue
            text = reader.pages[page - 1].extract_text() or ""
            found = re.findall(r"\b(\d+)\s*/\s*(\d+)\b", text[-200:])
            if len(found) != 1 or int(found[0][1]) != len(reader.pages):
                raise ValueError(f"missing or ambiguous printed footer on page {page}")
            labels[page] = int(found[0][0])
        row["printed_start"] = labels[row["start_page"]]
        row["printed_end"] = labels[row["end_page"]]
    global_changes = []
    footer_pages = repository_footer_pages(reader)
    if footer_pages == list(range(1, len(reader.pages) + 1)) and not repository_footer_pages(old):
        global_changes.append({"id": "repository-footer", "category": "global-presentation",
                               "title": "Left footer replaced by the clickable repository URL",
                               "start_page": 1, "end_page": len(reader.pages), "url": REPOSITORY_URL})
    return {
        "baseline": {"path": str(baseline.resolve()), "sha256": baseline_hash, "pages": len(old.pages)},
        "final": {"path": str(pdf.resolve()), "sha256": final_hash, "pages": len(reader.pages)},
        "marker_sha256": digest(marker_file), "ranges": ranges,
        "global_presentation_changes": global_changes,
        "printed_pages_equal_viewer_pages": all(page == value for page, value in labels.items()),
        "scope": "Tracked added/rewritten content and explicit cross-references; navigation and global presentation changes are separate. Subsequent pagination/numbering-only changes are not substantive edits.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    report = report_changes(args.pdf, args.baseline)
    output = args.pdf.parent / "changed-pages.json"
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Verified {len(report['ranges'])} content/navigation ranges: {output}")


if __name__ == "__main__":
    main()
