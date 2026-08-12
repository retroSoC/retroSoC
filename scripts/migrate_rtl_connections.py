#!/usr/bin/env python3
"""Convert provably positional RTL instances to named connections.

The converter is deliberately conservative. It only rewrites an instance when
the module header is ANSI-style and every positional argument can be matched
to a known port/parameter in the same order. Ambiguous instances are reported
and left unchanged for manual review.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")
KEYWORDS = {
    "input",
    "output",
    "inout",
    "logic",
    "wire",
    "reg",
    "signed",
    "unsigned",
    "parameter",
    "localparam",
    "type",
    "integer",
    "int",
    "bit",
    "var",
}


def matching(text: str, opening: int) -> int | None:
    depth = 0
    quote = False
    escaped = False
    for index in range(opening, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            continue
        if char == '"':
            quote = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def split_top(text: str) -> list[str]:
    result: list[str] = []
    start = 0
    paren = bracket = brace = 0
    quote = False
    escaped = False
    for index, char in enumerate(text):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            continue
        if char == '"':
            quote = True
        elif char == "(":
            paren += 1
        elif char == ")":
            paren -= 1
        elif char == "[":
            bracket += 1
        elif char == "]":
            bracket -= 1
        elif char == "{":
            brace += 1
        elif char == "}":
            brace -= 1
        elif char == "," and paren == bracket == brace == 0:
            result.append(text[start:index])
            start = index + 1
    result.append(text[start:])
    return result


def port_name(chunk: str) -> str | None:
    value = re.sub(r"//.*", "", chunk).strip()
    if not value or value.startswith("."):
        return None
    value = re.sub(r"\[[^]]*\]\s*$", "", value).rstrip()
    identifiers = [item for item in IDENT_RE.findall(value) if item not in KEYWORDS]
    return identifiers[-1] if identifiers else None


def parameter_name(chunk: str) -> str | None:
    value = re.sub(r"//.*", "", chunk).strip()
    if not value:
        return None
    match = re.search(r"(?:parameter\s+)?(?:type\s+)?([A-Za-z_][A-Za-z0-9_$]*)\s*(?:=|$)", value)
    return match.group(1) if match else None


def module_headers(paths: list[Path]) -> dict[str, tuple[list[str], list[str]]]:
    headers: dict[str, tuple[list[str], list[str]]] = {}
    pattern = re.compile(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)")
    for path in paths:
        source = path.read_text(encoding="utf-8", errors="replace")
        for match in pattern.finditer(source):
            name = match.group(1)
            cursor = match.end()
            while cursor < len(source) and source[cursor].isspace():
                cursor += 1
            params: list[str] = []
            if source[cursor:cursor + 2] == "#(":
                close = matching(source, cursor + 1)
                if close is None:
                    continue
                params = [parameter_name(chunk) for chunk in split_top(source[cursor + 2:close])]
                if any(item is None for item in params):
                    continue
                cursor = close + 1
            while cursor < len(source) and source[cursor].isspace():
                cursor += 1
            if cursor >= len(source) or source[cursor] != "(":
                continue
            close = matching(source, cursor)
            if close is None:
                continue
            ports = [port_name(chunk) for chunk in split_top(source[cursor + 1:close])]
            if not ports or any(item is None for item in ports):
                continue
            headers.setdefault(name, ([item for item in params if item], [item for item in ports if item]))
    return headers


def instance_candidates(source: str):
    module_re = re.compile(r"(?m)^[ \t]*(?P<module>[A-Za-z_][A-Za-z0-9_$]*)\b")
    for match in module_re.finditer(source):
        module = match.group("module")
        if module in {"module", "if", "for", "while", "case"}:
            continue
        cursor = match.end()
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        param_open = param_close = None
        if cursor < len(source) and source[cursor] == "#":
            cursor += 1
            while cursor < len(source) and source[cursor].isspace():
                cursor += 1
            if cursor >= len(source) or source[cursor] != "(":
                continue
            param_open = cursor
            param_close = matching(source, cursor)
            if param_close is None:
                continue
            cursor = param_close + 1
            while cursor < len(source) and source[cursor].isspace():
                cursor += 1
        instance_match = re.match(r"u_[A-Za-z_][A-Za-z0-9_$]*", source[cursor:])
        if instance_match is None:
            continue
        cursor += instance_match.end()
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        if cursor >= len(source) or source[cursor] != "(":
            continue
        yield module, param_open, param_close, cursor


def render_named(args: list[str], names: list[str], indent: str) -> str:
    rendered: list[str] = []
    for index, (name, arg) in enumerate(zip(names, args, strict=True)):
        value = arg.strip()
        comma = "," if index + 1 < len(args) else ""
        rendered.append(f"{indent}.{name}({value}){comma}")
    return "\n".join(rendered)


def rewrite(path: Path, headers: dict[str, tuple[list[str], list[str]]], apply: bool) -> tuple[int, int]:
    source = path.read_text(encoding="utf-8")
    edits: list[tuple[int, int, str]] = []
    skipped = 0
    for module, param_open, param_close, open_port in instance_candidates(source):
        header = headers.get(module)
        if header is None:
            continue
        close_port = matching(source, open_port)
        if close_port is None:
            skipped += 1
            continue
        params, ports = header
        if param_open is not None and param_close is not None:
            param_args = split_top(source[param_open + 1:param_close])
            if param_args and not any(arg.strip().startswith(".") for arg in param_args):
                if len(param_args) != len(params):
                    skipped += 1
                    continue
                line_start = source.rfind("\n", 0, param_open) + 1
                indent_match = re.match(r"[ \t]*", source[line_start:])
                indent = (indent_match.group(0) if indent_match else "") + "  "
                replacement = render_named(param_args, params, indent)
                edits.append((param_open + 1, param_close, "\n" + replacement + "\n" + indent[:-2]))
        args = split_top(source[open_port + 1:close_port])
        if not args or any(arg.strip().startswith(".") for arg in args):
            continue
        if len(args) != len(ports):
            skipped += 1
            continue
        line_start = source.rfind("\n", 0, open_port) + 1
        indent_match = re.match(r"[ \t]*", source[line_start:])
        indent = (indent_match.group(0) if indent_match else "") + "  "
        replacement = "\n" + render_named(args, ports, indent) + "\n" + (indent[:-2] if len(indent) >= 2 else "")
        edits.append((open_port + 1, close_port, replacement))
    if apply:
        for start, end, replacement in reversed(edits):
            source = source[:start] + replacement + source[end:]
        path.write_text(source, encoding="utf-8")
    return len(edits), skipped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    production = sorted((root / "rtl/ip").rglob("*.sv")) + sorted((root / "rtl/mini/top").rglob("*.sv"))
    declaration_roots = [
        root / "rtl/managed/clusterip/common",
        root / "rtl/managed/clusterip",
        root / "rtl/tech",
    ]
    declarations = [
        path
        for directory in declaration_roots
        for path in sorted(directory.rglob("*.sv"))
        if path.is_file()
    ]
    headers = module_headers([*production, *declarations])
    total = skipped = 0
    for path in production:
        changed, ignored = rewrite(path, headers, args.apply)
        total += changed
        skipped += ignored
    print(f"named connections: rewritten={total} ambiguous={skipped} modules={len(headers)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
