"""Publication-only chapter assembly and source-prose conversion."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIST_ITEM = re.compile(r"^( *)(?:(?P<bullet>[-+*])|(?P<number>\d+)[.)])\s+(?P<body>.*)$")


def list_block(lines: list[str], start: int) -> tuple[dict, int]:
    """Keep list hierarchy and explicit numbers instead of publishing fake paragraphs."""
    first = LIST_ITEM.match(lines[start])
    assert first is not None
    indent = len(first[1])
    ordered = first["number"] is not None
    items = []
    index = start
    while index < len(lines):
        match = LIST_ITEM.match(lines[index])
        if (
            match is None
            or len(match[1]) != indent
            or (match["number"] is not None) != ordered
        ):
            break
        content_indent = match.start("body")
        content = [match["body"]]
        index += 1
        blank = False
        fence = None
        while index < len(lines):
            line = lines[index]
            stripped = line.strip()
            depth = len(line) - len(line.lstrip())
            candidate = LIST_ITEM.match(line)
            if fence is None:
                if candidate and len(candidate[1]) <= indent:
                    break
                if stripped and depth <= indent and (
                    blank or stripped.startswith(("#", "|", "```"))
                ):
                    break
            if stripped.startswith("```"):
                fence = None if fence else "```"
            content.append(line[min(depth, content_indent) :])
            blank = not stripped
            index += 1
        items.append(
            {
                "number": int(match["number"]) if ordered else None,
                "blocks": blocks_from_markdown("\n".join(content)),
            }
        )
    return {"kind": "list", "ordered": ordered, "items": items}, index


def blocks_from_markdown(text: str) -> list[dict]:
    blocks = []
    lines = text.expandtabs(4).splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if LIST_ITEM.match(lines[i]):
            block, i = list_block(lines, i)
            blocks.append(block)
        elif line.startswith("#"):
            blocks.append({"kind": "heading", "text": line.lstrip("# ")})
            i += 1
        elif line.startswith("```"):
            language = line[3:].strip()
            start = i + 1
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
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
                and not lines[i].strip().startswith(("#", "|", "```"))
                and not LIST_ITEM.match(lines[i])
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
    if len(titles) != len(set(titles)):
        raise ValueError(f"duplicate requested publication section: {path}")
    for title in titles:
        count = sum(head[2] == title for head in headings)
        if count != 1:
            raise ValueError(
                f"publication section must match exactly once: {path}: {title!r} ({count} matches)"
            )
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


def apply_prose_corrections(sections: list[dict], corrections: list[dict], root: Path) -> None:
    """Reconcile selected legacy prose with explicit current-source bindings."""
    blocks = [block for section in sections for block in section["blocks"]]
    def normalize(text: str) -> str:
        return re.sub(r"\s+", "", text)
    for correction in corrections:
        before, after = correction["before"], correction["after"]
        if not before or not after or not correction.get("bindings"):
            raise ValueError("prose correction requires text and executable source bindings")
        target = correction.get("target", "paragraph")
        if target == "paragraph":
            matches = [(block, "text") for block in blocks
                       if block["kind"] == "paragraph" and block["text"] == before]
        elif target == "table_header":
            matches = [(block["headers"], index) for block in blocks if block["kind"] == "table"
                       for index, text in enumerate(block["headers"]) if text == before]
        elif target == "table_cell":
            matches = [(row, index) for block in blocks if block["kind"] == "table"
                       for row in block["rows"] for index, text in enumerate(row) if text == before]
        else:
            raise ValueError("unknown prose correction target")
        if len(matches) != 1:
            raise ValueError(f"prose correction must match exactly one selected {target}")
        for binding in correction["bindings"]:
            path = (root / binding["file"]).resolve()
            if (not path.is_relative_to(root.resolve()) or not binding["text"]
                    or normalize(binding["text"]) not in normalize(path.read_text(encoding="utf-8"))):
                raise ValueError(f"prose correction source binding changed: {binding['file']}")
        container, key = matches[0]
        container[key] = after


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
        apply_prose_corrections(item["functional"] + item["software"],
                               item.get("prose_corrections", []), ROOT)
        item["reference"] = item.get("reference", registers[family]["document"])
        item["example"] = ""
        if item.get("example_file"):
            item["example"] = (ROOT / item["example_file"]).read_text(encoding="utf-8")
    return content
