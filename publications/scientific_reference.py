"""Publication-only scientific notation; numerical and software sources stay raw.

The display grammar is deliberately small and never evaluates source text.
Only approved engineering symbols and explicit arithmetic powers are attached.
"""
from __future__ import annotations

from collections.abc import Iterator
import hashlib
import json
import math
import re
import textwrap
import xml.etree.ElementTree as ET


ALIASES = {
    "Iref": ("I", "ref"), "I_ref": ("I", "ref"),
    "Tref": ("T", "ref"), "T_ref": ("T", "ref"),
    "Bideal": ("B", "ideal"), "B_ideal": ("B", "ideal"),
    "fbus": ("f", "bus"), "f_bus": ("f", "bus"), "f_MHz": ("f", "MHz"),
    "setup_cycles": ("setup", "cycles"),
    "VOH": ("V", "OH"), "V_OH": ("V", "OH"),
    "VOL": ("V", "OL"), "V_OL": ("V", "OL"),
    "VIH": ("V", "IH"), "V_IH": ("V", "IH"),
    "VIL": ("V", "IL"), "V_IL": ("V", "IL"),
    "VIO": ("V", "IO"), "V_IO": ("V", "IO"),
    "VCORE": ("V", "CORE"), "Vcore": ("V", "core"),
    "Rout": ("R", "out"), "R_out": ("R", "out"),
}
# Package outline, tape/reel, and reflow notation are scoped to packaging views.
MECHANICAL = {
    "D2": ("D", "2"), "E2": ("E", "2"), "A1": ("A", "1"), "A3": ("A", "3"),
    "A0": ("A", "0"), "B0": ("B", "0"), "K0": ("K", "0"), "P1": ("P", "1"), "W1": ("W", "1"),
    "T_Smin": ("T", "S,min"), "T_Smax": ("T", "S,max"), "T_L": ("T", "L"), "T_P": ("T", "P"),
    "t_S": ("t", "S"), "t_L": ("t", "L"), "t_P": ("t", "P"),
}
_ALIAS = re.compile(r"\b(?:" + "|".join(map(re.escape, sorted(ALIASES, key=len, reverse=True))) + r")\b")
_MECHANICAL = re.compile(r"\b(?:" + "|".join(MECHANICAL) + r")\b")
_POWER = re.compile(r"(?<![\w.])(?P<base>\d+(?:\.\d+)?|x|X|e|mm|cm|m)\s*(?:\*\*|\^)\s*")
_EQUATION = re.compile(r"\b(?:Iref|I_ref|Tref|T_ref|VOH|VOL|V_OH|V_OL|SCK)\s*(?:\[[^]]+\])?\s*=")
_SCRIPT = re.compile(r"[A-Za-z0-9θµΩ() +−*/.,-]{1,80}\Z")


def _plain(value: str, equation: bool) -> str:
    value = value.replace("deg C", "°C")
    if "temperature" in value.lower():
        value = value.replace("(C)", "(°C)")
    value = re.sub(r"(?<=\d)\s+C\b", " °C", value)
    value = re.sub(r"(?<=\d)\s+kohm\b", " kΩ", value)
    value = re.sub(r"(?<=\d)\s+ohm\b", " Ω", value)
    value = re.sub(r"(?<=\d)\s+uA\b", " µA", value)
    value = re.sub(r"(?<=\d)\s+uF\b", " µF", value)
    value = re.sub(r"(?<=\d)\s+us\b", " µs", value)
    if equation:
        value = value.replace("*", "×")
        value = re.sub(r"(?<![A-Za-z])-(?=(?:[A-Za-z]\b|\d|\())", "−", value)
    return value


def tokens(value: str, *, mechanical: bool = False) -> list[dict]:
    """Return inert display tokens; an empty result means exact literal output."""
    result, cursor = [], 0
    equation = bool(_EQUATION.search(value))
    while cursor < len(value):
        alias = (_MECHANICAL if mechanical else _ALIAS).search(value, cursor)
        power = _POWER.search(value, cursor)
        match = min((m for m in (alias, power) if m is not None), key=lambda m: m.start(), default=None)
        if match is None:
            result.append({"kind": "text", "value": _plain(value[cursor:], equation)})
            break
        if match.start() > cursor:
            result.append({"kind": "text", "value": _plain(value[cursor:match.start()], equation)})
        if match is alias:
            base, script = (MECHANICAL if mechanical else ALIASES)[match.group()]
            result.append({"kind": "symbol", "base": base, "value": script})
            cursor = match.end()
            continue
        end, script = match.end(), ""
        if end < len(value) and value[end] == "(":
            depth, start = 0, end
            for index in range(end, len(value)):
                depth += (value[index] == "(") - (value[index] == ")")
                if depth == 0:
                    end, script = index + 1, value[start + 1:index]
                    break
        else:
            exponent = re.match(r"(?:\d+(?:\.\d+)?|[nNkKmM])\b", value[end:])
            if exponent:
                script, end = exponent.group(), end + exponent.end()
        if script and _SCRIPT.fullmatch(script):
            result.append({"kind": "power", "base": match.group("base"), "value": _plain(script, True).replace("-", "−")})
            cursor = end
        else:
            result.append({"kind": "text", "value": value[match.start():match.end()]})
            cursor = match.end()
    merged = []
    for token in result:
        if token["kind"] == "text" and merged and merged[-1]["kind"] == "text":
            merged[-1]["value"] += token["value"]
        else:
            merged.append(token)
    result = merged
    if result == [{"kind": "text", "value": value}] or not result:
        return []
    return result


def _strings(value: object) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        if value.get("kind") == "code":
            return
        for key, child in value.items():
            if key not in {"scientific", "signature", "code"}:
                yield from _strings(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            yield from _strings(child)


def prepare(data: dict) -> None:
    """Attach a display lookup without rewriting any existing record or value."""
    entries, scripts = {}, {}
    candidates = set(_strings(data)) | set(ALIASES)
    for value in list(candidates):
        if tokens(value):
            candidates.update(textwrap.wrap(value, 104))
        for part in value.split("`"):
            candidates.update(part.split("**"))
    candidates.update("mechanical:" + r["meaning"] for r in data["specifications"].get("records", [])
                      if r["group"] == "mechanical")
    if data["specifications"].get("product") == "tiny":
        candidates.update("mechanical:" + name for name in MECHANICAL)
    for raw in sorted(candidates):
        display = tokens(raw.removeprefix("mechanical:"), mechanical=raw.startswith("mechanical:"))
        if not display:
            continue
        identity = hashlib.sha256(raw.encode()).hexdigest()
        entries[raw] = {"id": identity, "tokens": display}
        for n, token in enumerate(display):
            if token["kind"] != "text":
                scripts[f"{identity}:{n}"] = {"entry_id": identity, "text": token["value"],
                                              "role": "sub" if token["kind"] == "symbol" else "super"}
    for raw, display in {"deg C": "°C", "us": "µs", "uF": "µF", "uA": "µA", "ohm": "Ω", "kohm": "kΩ"}.items():
        key = "unit:" + raw
        entries[key] = {"id": hashlib.sha256(key.encode()).hexdigest(),
                        "tokens": [{"kind": "text", "value": display}]}
    notation = {"schema_version": 1, "entries": entries, "scripts": scripts}
    data["scientific"] = notation
    data["specifications"]["scientific"] = notation


def plot_text(raw: str, notation: dict) -> tuple[str, str | None]:
    entry = notation["entries"].get(raw)
    if entry is None:
        return raw, None
    pieces = []
    for token in entry["tokens"]:
        if token["kind"] == "text":
            pieces.append(token["value"].replace("$", r"\$"))
        else:
            operator = "_" if token["kind"] == "symbol" else "^"
            pieces.append(r"$\mathregular{" + token["base"] + "}" + operator
                          + r"{\mathregular{" + token["value"] + "}}$")
    return "".join(pieces), entry["id"]


def layout_query(base: str) -> str:
    """Append measured native-script and plot rectangles to a book's query."""
    return base[:-1] + (',script_boxes:query(<scientific-script-region>).map(r=>{'
        'let p=r.location().position();(page:p.page,x:p.x.pt(),y:p.y.pt(),'
        'width:r.width.length.pt(),height:r.height.length.pt())}),'
        'scientific_plots:("cpu-relative","current-frequency","current-modes",'
        '"current-voltage","current-temperature","transfer","gpio-load").map(id=>{'
        'let r=query(label("scientific-plot-"+id)).first();let p=r.location().position();'
        '(id:id,page:p.page,x:p.x.pt(),y:p.y.pt())}))')


def change_markers(items: list[dict], document: dict, notation: dict) -> list[dict]:
    """Actual display-use metadata identifies formatting pages, not old prose."""
    identities = {entry["id"] for entry in notation["entries"].values()}
    uses = [r for r in items if isinstance(r, dict) and r.get("kind") == "scientific-use"]
    if any(r["id"] not in identities for r in uses):
        raise ValueError("scientific use has no display source")
    if type(document.get("scientific_change_markers", True)) is not bool:
        raise ValueError("scientific_change_markers must be boolean")
    if document.get("scientific_change_markers", True) is False:
        return []
    result = []
    for page in sorted({r["page"] for r in uses}):
        identity = document["change_prefix"] + "scientific-page-" + str(page)
        result += [dict(kind="publication-change-start", id=identity, page=page,
                        title="Scientific formula / symbol typography", category="modified"),
                   dict(kind="publication-change-end", id=identity, page=page)]
    return result


def _multiply(a: tuple, b: tuple) -> tuple:
    x, y, z, w, u, v = a
    p, q, r, s, t, k = b
    return (x*p+z*q, y*p+w*q, x*r+z*s, y*r+w*s, x*t+z*k+u, y*t+w*k+v)


def _transform(raw: str) -> tuple:
    result = (1, 0, 0, 1, 0, 0)
    for name, body in re.findall(r"([a-zA-Z]+)\(([^)]*)\)", raw):
        v = [float(n) for n in re.findall(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", body)]
        if name == "translate":
            m = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            m = (v[0], 0, 0, v[-1], 0, 0)
        elif name == "rotate" and len(v) in {1, 3}:
            angle = math.radians(v[0])
            m = (math.cos(angle), math.sin(angle), -math.sin(angle), math.cos(angle), 0, 0)
            if len(v) == 3:
                m = _multiply(_multiply((1, 0, 0, 1, v[1], v[2]), m),
                              (1, 0, 0, 1, -v[1], -v[2]))
        elif name == "matrix" and len(v) == 6:
            m = tuple(v)
        else:
            raise ValueError("unsupported scientific SVG transform")
        result = _multiply(result, m)
    return result


def svg_scripts(path, notation: dict) -> list[dict]:
    """Read real MathText tspan positions; do not exempt an entire plot/label."""
    result = []
    registry = notation["scripts"]

    def visit(node, matrix=(1, 0, 0, 1, 0, 0), entry=None):
        matrix = _multiply(matrix, _transform(node.get("transform", "")))
        if node.get("id", "").startswith("scientific-"):
            entry = node.get("id")[11:]
        style = node.get("style", "")
        size = re.search(r"font-size:\s*([\d.]+)px", style)
        if node.tag.endswith("}tspan") and size and float(size[1]) < 8.95:
            if not entry or "Inter" not in style:
                raise ValueError("unattributed or non-Inter plot script")
            xs = [float(x) for x in node.get("x", "0").split()]
            ys = [float(y) for y in node.get("y", "0").split()]
            text, fontsize = node.text or "", float(size[1])
            for i, char in enumerate(text):
                if not char.strip():
                    continue
                matches = [(key, value) for key, value in registry.items()
                           if value["entry_id"] == entry and char in value["text"]]
                if not matches:
                    raise ValueError("plot script is absent from the display source")
                identity, source = matches[0]
                x, y = xs[min(i, len(xs)-1)], ys[min(i, len(ys)-1)]
                a, b, c, d, e, f = matrix
                points = [(a*px+c*py+e, b*px+d*py+f) for px, py in
                          [(x-.1, y-fontsize*1.1), (x+fontsize*1.3, y-fontsize*1.1),
                           (x-.1, y+fontsize*.5), (x+fontsize*1.3, y+fontsize*.5)]]
                left, top = min(p[0] for p in points), min(p[1] for p in points)
                result.append(dict(id=identity, text=char, role=source["role"], renderer="plot",
                                   x=left, y=top, width=max(p[0] for p in points)-left,
                                   height=max(p[1] for p in points)-top, font_size=fontsize,
                                   base_size=9.0))
        for child in node:
            visit(child, matrix, entry)

    visit(ET.parse(path).getroot())
    return result


def regions(layout: dict, data: dict) -> list[dict]:
    items = layout["items"]
    info = [r for r in items if isinstance(r, dict) and r.get("kind") == "scientific-script-info"]
    boxes = layout.get("script_boxes", [])
    if len(info) != len(boxes):
        raise ValueError("scientific script bounds are incomplete")
    result = []
    for box, record in zip(boxes, info):
        size, base = record["font_size"], record["base_size"]
        result.append(dict(kind="scientific-script", id=record["id"], text=record["text"],
                           role=record["role"], renderer="native", page=box["page"], x=box["x"],
                           y=box["y"] + (0.2 if record["role"] == "sub" else -0.5)*base - .8*size,
                           width=box["width"], height=size*1.1, font_size=size, base_size=base))
    plots = layout.get("scientific_plots", [])
    for plot in plots:
        dataset = next(d for d in data["specifications"]["datasets"] if d["id"] == plot["id"])
        for r in dataset.get("scientific_regions", []):
            result.append({**r, "kind": "scientific-script", "page": plot["page"],
                           "x": r["x"]+plot["x"], "y": r["y"]+plot["y"]})
    validate_regions(result, data["scientific"])
    return result


def validate_regions(values: list[dict], notation: dict) -> None:
    for r in values:
        source = notation["scripts"].get(r.get("id"))
        if not source or r.get("role") != source["role"] or r.get("renderer") not in {"native", "plot"}:
            raise ValueError("unknown scientific script region")
        text = r.get("text", "")
        if not text or any(c not in source["text"] for c in text):
            raise ValueError("scientific script text differs from its source")
        if r["renderer"] == "native" and text != source["text"]:
            raise ValueError("native script text is incomplete")
        if not all(type(r.get(k)) in {int, float} and math.isfinite(r[k])
                   for k in ("x", "y", "width", "height", "font_size", "base_size", "page")):
            raise ValueError("invalid scientific script geometry")
        if not (type(r["page"]) is int and r["page"] >= 1 and 9 <= r["base_size"] <= 30
                and abs(r["font_size"]-max(6.3, .7*r["base_size"])) < .06
                and 0 < r["width"] <= 250 and 0 < r["height"] <= r["font_size"]*1.7):
            raise ValueError("invalid scientific script size or bounds")


def script_allowed(char: dict, page: int, values: list[dict]) -> bool:
    matrix = char.get("matrix", ())
    rotated = len(matrix) == 6 and abs(matrix[0]) < 1e-8 and abs(matrix[3]) < 1e-8
    size = char["width"] if rotated else char["size"]
    return any(r.get("kind") == "scientific-script" and r["page"] == page
               and abs(size-r["font_size"]) < .1 and size >= 6.25
               and re.search(r"(?:^|\+)Inter(?:[-,]|$)", char.get("fontname", ""))
               and all(c in r["text"] for c in char["text"])
               and char["x0"] >= r["x"]-.2 and char["x1"] <= r["x"]+r["width"]+.2
               and char["top"] >= r["y"]-.2 and char["bottom"] <= r["y"]+r["height"]+.2
               for r in values)


def audit(data: dict, items: list[dict]) -> dict:
    sources = {e["id"]: dict(raw=raw, **e) for raw, e in data["scientific"]["entries"].items()}
    pages = {}
    for item in items:
        if isinstance(item, dict) and item.get("kind") == "scientific-use":
            if item["id"] not in sources:
                raise ValueError("unregistered scientific display use")
            pages.setdefault(item["id"], set()).add(item["page"])
    return dict(schema_version=1, grammar="restricted-v1", sources=[
        {**sources[identity], "pages": sorted(pages[identity])} for identity in sorted(pages)])


def export_audit(out, data: dict, items: list[dict]) -> dict:
    path = out / "scientific-notation.json"
    path.write_text(json.dumps(audit(data, items), ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8", newline="\n")
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()}


def verify_audit(out, manifest: dict, data: dict) -> None:
    path = out / "scientific-notation.json"
    if manifest.get("scientific_audits", {}).get(path.name) != hashlib.sha256(path.read_bytes()).hexdigest():
        raise ValueError("scientific display audit integrity failure")
    value = json.loads(path.read_text(encoding="utf-8"))
    items = [dict(kind="scientific-use", id=source["id"], page=page)
             for source in value["sources"] for page in source["pages"]]
    if any(type(item["page"]) is not int or item["page"] < 1 for item in items):
        raise ValueError("invalid scientific display page")
    if value != audit(data, items):
        raise ValueError("scientific display audit differs from current sources")
