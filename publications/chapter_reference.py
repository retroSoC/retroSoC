"""Publication-only chapter assembly and source-prose conversion."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def blocks_from_markdown(text: str) -> list[dict]:
    blocks = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("#"):
            blocks.append({"kind": "heading", "text": line.lstrip("# ")})
            i += 1
        elif line.startswith("```"):
            language = line[3:].strip()
            start = i + 1
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                i += 1
            code_text = "\n".join(lines[start:i])
            if language in {"", "text"} and re.search(r"\+[-─=]{2,}|-->|→", code_text):
                i += 1
                continue
            blocks.append({"kind": "code", "language": language, "text": code_text})
            i += 1
        elif line.startswith("|"):
            table = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = re.split(r"\s+\|\s+", lines[i].strip().strip("|").strip())
                if not all(re.fullmatch(r"[-: ]+", c) for c in cells):
                    table.append(cells)
                i += 1
            if table and all(len(row) == len(table[0]) for row in table):
                blocks.append({"kind": "table", "headers": table[0], "rows": table[1:]})
        else:
            content = [line]
            i += 1
            while (
                i < len(lines)
                and lines[i].strip()
                and not lines[i].startswith(("#", "|", "```", "- "))
                and not re.match(r"\d+\. ", lines[i])
            ):
                content.append(lines[i].strip())
                i += 1
            paragraph = " ".join(content)
            paragraph = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", paragraph)
            blocks.append({"kind": "paragraph", "text": paragraph})
    return blocks


def section_text(path: Path, titles: list[str]) -> list[dict]:
    source = path.read_text(encoding="utf-8")
    headings = list(re.finditer(r"^(#{1,6}) (.+)$", source, re.M))
    selected = []
    for index, head in enumerate(headings):
        if head[2] not in titles:
            continue
        end = len(source)
        for next_head in headings[index + 1 :]:
            if len(next_head[1]) <= len(head[1]):
                end = next_head.start()
                break
        selected.append(
            {"title": head[2], "blocks": blocks_from_markdown(source[head.end() : end])}
        )
    return selected


def collect_chapters(registers: dict) -> dict:
    content = json.loads((ROOT / "publications/datasheets/ip-content.json").read_text())
    features = json.loads((ROOT / "publications/datasheets/features.json").read_text())
    for ip, item in content.items():
        item["features"] = features[ip]
        family = item.get("register_family", ip)
        if family not in registers:
            continue
        source = ROOT / item.get("reference", registers[family]["document"])
        item["functional"] = section_text(source, item["function_sections"])
        item["software"] = section_text(source, item["software_sections"])
        item["reference"] = item.get("reference", registers[family]["document"])
        item["example"] = ""
        if item.get("example_file"):
            item["example"] = (ROOT / item["example_file"]).read_text(encoding="utf-8")
    return content
