"""Read-only register documentation extraction from reviewed RTL and annotations.

This is a publication adapter, not a register generator. Unsupported expressions
are reported for explicit documentation review rather than evaluated as Python.
"""

from __future__ import annotations

import ast
import json
import operator
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "publications/datasheets/register-profiles.json"
ANNOTATIONS = ROOT / "publications/datasheets/register-annotations.json"
LITERAL = re.compile(r"(?P<w>\d+)?'[sS]?(?P<base>[hHbBdDoO])(?P<digits>[0-9a-fA-F_]+)")


def number(expression: str, constants: dict[str, int] | None = None) -> int:
    constants = constants or {}
    expression = " ".join(expression.split()).replace("`", "")
    expression = LITERAL.sub(
        lambda m: str(
            int(m["digits"].replace("_", ""), {"h": 16, "b": 2, "d": 10, "o": 8}[m["base"].lower()])
        ),
        expression,
    )
    expression = re.sub(r"\b(\d+)[uUlL]+\b", r"\1", expression)
    if expression in {"'0", "'1"}:
        return 0 if expression == "'0" else 0xFFFFFFFF
    expression = expression.replace("$clog2", "clog2")
    expression = re.sub(r"(?:\w+|\d+)'\(([^()]+)\)", r"(\1)", expression)
    conditional = split_top(expression, "?")
    if len(conditional) == 2:
        branches = split_top(conditional[1], ":")
        if len(branches) == 2:
            return number(
                branches[0] if number(conditional[0], constants) else branches[1], constants
            )
    operations = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.floordiv,
        ast.FloorDiv: operator.floordiv,
        ast.LShift: operator.lshift,
        ast.RShift: operator.rshift,
        ast.BitOr: operator.or_,
        ast.BitAnd: operator.and_,
        ast.BitXor: operator.xor,
    }

    def visit(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name) and node.id in constants:
            return constants[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in operations:
            return operations[type(node.op)](visit(node.left), visit(node.right))
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            comparisons = {
                ast.Eq: operator.eq,
                ast.NotEq: operator.ne,
                ast.Lt: operator.lt,
                ast.LtE: operator.le,
                ast.Gt: operator.gt,
                ast.GtE: operator.ge,
            }
            if type(node.ops[0]) in comparisons:
                return int(
                    comparisons[type(node.ops[0])](visit(node.left), visit(node.comparators[0]))
                )
        if isinstance(node, ast.UnaryOp):
            if isinstance(node.op, ast.USub):
                return -visit(node.operand)
            if isinstance(node.op, ast.Invert):
                return ~visit(node.operand)
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "clog2"
            and len(node.args) == 1
        ):
            return (visit(node.args[0]) - 1).bit_length()
        raise ValueError(f"unresolved constant expression: {expression}")

    try:
        return visit(ast.parse(expression, mode="eval").body)
    except (SyntaxError, KeyError, TypeError, ZeroDivisionError) as error:
        raise ValueError(f"unresolved constant expression: {expression}") from error


def split_top(text: str, separator: str = ",") -> list[str]:
    depth = 0
    start = 0
    parts = []
    for pos, char in enumerate(text):
        if char in "({[":
            depth += 1
        elif char in ")}]":
            depth -= 1
        elif char == separator and depth == 0:
            parts.append(text[start:pos].strip())
            start = pos + 1
    parts.append(text[start:].strip())
    return parts


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m[0].count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def named_argument(text: str, name: str) -> str | None:
    found = re.search(r"\." + name + r"\s*\(", text)
    if not found:
        return None
    depth = 1
    for index in range(found.end(), len(text)):
        depth += (text[index] == "(") - (text[index] == ")")
        if depth == 0:
            return text[found.end() : index].strip()
    raise ValueError(f"unclosed {name} argument")


def parse_definitions(paths: list[str], extra: dict[str, int]) -> tuple[dict, dict]:
    definitions = {}
    constants = dict(extra)
    memory = json.loads((ROOT / "rtl/mini/address_map/memory_map.json").read_text())
    constants.update(
        {
            f"SOC_SYSCTRL_{r['symbol']}_OFFSET": int(r["offset"], 0)
            for r in memory["sysctrl_registers"]
        }
    )
    for register in memory["sysctrl_registers"]:
        key = f"SOC_SYSCTRL_{register['symbol']}_OFFSET"
        definitions[key] = {
            "expression": f"16'h{int(register['offset'], 0):04x}",
            "source": "rtl/mini/address_map/memory_map.json",
            "line": 1,
        }
    for path in paths:
        text = strip_comments((ROOT / path).read_text(encoding="utf-8"))
        for match in re.finditer(r"^[ \t]*`define[ \t]+(\w+)[ \t]+([^\n]+)", text, re.M):
            definitions[match[1]] = {
                "expression": match[2].strip(),
                "source": path,
                "line": text.count("\n", 0, match.start()) + 1,
            }
        for match in re.finditer(
            r"\b(?:localparam|parameter)\s+(?:(?:int(?:\s+unsigned)?|logic(?:\s*\[[^]]+\])?|\w+_t)\s+)?"
            r"(\w+)\s*=\s*([^;\n]+)",
            text,
        ):
            expression = match[2].rstrip(",")
            definitions.setdefault(
                match[1],
                {
                    "expression": expression,
                    "source": path,
                    "line": text.count("\n", 0, match.start()) + 1,
                },
            )
        for match in re.finditer(
            r"\blocalparam\s+(?:int(?:\s+unsigned)?|logic(?:\s*\[[^]]+\])?|\w+_t)\s+(\w+)\s*=\s*([^;]+);",
            text,
        ):
            definitions[match[1]] = {
                "expression": match[2].strip(),
                "source": path,
                "line": text.count("\n", 0, match.start()) + 1,
            }
    for _ in range(8):
        for name, entry in definitions.items():
            if name in constants:
                continue
            try:
                constants[name] = number(entry["expression"], constants)
            except ValueError:
                pass
    return definitions, constants


def source_model(text: str, constants: dict) -> dict:
    widths = {}
    arrays = set()
    for match in re.finditer(r"\blogic\s*((?:\[[^]\n]+\][ \t]*)*)([^;()\n]+)", text):
        dimensions, variables = match.groups()
        dims = re.findall(r"\[([^]:]+):([^]]+)\]", dimensions)
        try:
            width = (
                1
                if not dims
                else abs(number(dims[-1][0], constants) - number(dims[-1][1], constants)) + 1
            )
        except ValueError:
            continue
        for variable in variables.split(","):
            found = re.match(r"\s*(\w+)", variable)
            if found:
                widths[found[1]] = width
                if len(dims) > 1 or "[" in variable:
                    arrays.add(found[1])
    assigns = {m[1]: m[2].strip() for m in re.finditer(r"\bassign\s+(\w+)\s*=\s*([^;]+);", text)}
    resets = {}
    for match in re.finditer(
        r"\b(dffr\w*|dffer\w*)\s*#\s*\((.*?)\)\s+\w+\s*\((.*?)\);", text, re.S
    ):
        params, ports = match[2], match[3]
        output = named_argument(ports, "dat_o")
        value = next(
            (
                v
                for key in ("RST_VALUE", "RESET_VAL", "RESET_VALUE")
                if (v := named_argument(params, key)) is not None
            ),
            None,
        )
        if output:
            resets[output] = value if value is not None else "0"
    # Explicit reset arms; only assignments before the corresponding else are used.
    for match in re.finditer(
        r"if\s*\([^)]*(?:!\w*rst\w*|!\w*reset\w*)[^)]*\)\s*begin(.*?)end\s*else", text, re.S | re.I
    ):
        for assignment in re.finditer(r"(\w+(?:\[[^]]+\])?)\s*<=\s*([^;]+);", match[1]):
            resets[assignment[1]] = assignment[2].strip()
    return {
        "text": text,
        "widths": widths,
        "arrays": arrays,
        "assigns": assigns,
        "resets": resets,
        "constants": constants,
    }


def width_of(expression: str, model: dict) -> int:
    expression = expression.strip()
    if expression in {"'0", "'1"}:
        return 32
    repeat = re.fullmatch(r"\{([^{}]+)\{(.+)\}\}", expression, re.S)
    if repeat:
        return number(repeat[1], model["constants"]) * width_of(repeat[2], model)
    if expression.startswith("(") and expression.endswith(")"):
        return width_of(expression[1:-1], model)
    if expression.startswith(("!", "|", "&")) or re.search(r"&&|\|\||!=|==|<=|>=", expression):
        return 1
    if "?" in expression:
        branches = split_top(expression.split("?", 1)[1], ":")
        if len(branches) == 2:
            return max(width_of(branch, model) for branch in branches)
    literal = LITERAL.fullmatch(expression)
    if literal and literal["w"]:
        return int(literal["w"])
    cast = re.match(r"(\d+)'\(", expression)
    if cast:
        return int(cast[1])
    select = re.fullmatch(r"\w+(?:\.\w+)*(?:\[[^]]+\])*\[([^]]+)\]", expression)
    if select:
        if "+:" in select[1] or "-:" in select[1]:
            return number(re.split(r"[+-]:", select[1])[-1], model["constants"])
        if ":" in select[1]:
            a, b = select[1].split(":")
            return abs(number(a, model["constants"]) - number(b, model["constants"])) + 1
        base = expression.split("[", 1)[0]
        if base in model["arrays"] and expression.count("[") == 1:
            return model["widths"][base]
        return 1
    if expression in model["widths"]:
        return model["widths"][expression]
    if "." in expression and expression.rsplit(".", 1)[-1] in model["widths"]:
        return model["widths"][expression.rsplit(".", 1)[-1]]
    call = re.fullmatch(r"(\w+)\((.*)\)", expression, re.S)
    if call:
        declaration = re.search(
            r"function\s+automatic\s+logic\s*\[([^]:]+):([^]]+)\]\s+" + call[1], model["text"]
        )
        if declaration:
            return (
                abs(
                    number(declaration[1], model["constants"])
                    - number(declaration[2], model["constants"])
                )
                + 1
            )
    if expression.startswith("`") and expression[1:] in model["widths"]:
        return model["widths"][expression[1:]]
    if expression.replace("`", "") in model["constants"]:
        return 32
    for separator in ("&", "|"):
        parts = split_top(expression, separator)
        if len(parts) > 1:
            return max(width_of(part, model) for part in parts)
    if expression.startswith("{") and expression.endswith("}"):
        return sum(width_of(p, model) for p in split_top(expression[1:-1]))
    raise ValueError(f"unknown expression width: {expression}")


def friendly(expression: str) -> str:
    value = re.sub(r"^s_", "", expression.strip())
    value = re.sub(r"_(?:q|d|i|o)(?=\[|$)", "", value)
    value = value.replace("`", "")
    return value.upper()


def reset_of(expression: str, model: dict, depth: int = 0) -> int:
    expression = expression.strip()
    if depth > 8:
        raise ValueError("reset recursion")
    try:
        return number(expression, model["constants"])
    except ValueError:
        pass
    if expression.startswith("(") and expression.endswith(")"):
        return reset_of(expression[1:-1], model, depth + 1)
    cast = re.fullmatch(r"(\w+|\d+)'\((.+)\)", expression, re.S)
    if cast:
        return reset_of(cast[2], model, depth + 1) & (
            (1 << number(cast[1], model["constants"])) - 1
        )
    if expression.startswith("{") and expression.endswith("}"):
        value = 0
        for part in split_top(expression[1:-1]):
            width = width_of(part, model)
            value = (value << width) | (reset_of(part, model, depth + 1) & ((1 << width) - 1))
        return value
    if expression in model["resets"]:
        return reset_of(model["resets"][expression], model, depth + 1)
    if expression in model["assigns"]:
        return reset_of(model["assigns"][expression], model, depth + 1)
    if expression in model.get("definitions", {}):
        return reset_of(model["definitions"][expression]["expression"], model, depth + 1)
    selected = re.fullmatch(r"(\w+)\[([^]]+)\]", expression)
    if selected:
        candidates = [v for k, v in model["resets"].items() if k.startswith(selected[1] + "[")]
        if candidates:
            values = [reset_of(v, model, depth + 1) for v in candidates]
            if set(values) == {0}:
                return 0
    if selected and selected[1] in model["resets"]:
        value = reset_of(model["resets"][selected[1]], model, depth + 1)
        if "+:" in selected[2] or selected[1] in model["arrays"]:
            # Uniform zero resets of packed channel arrays do not need the index.
            if value == 0:
                return 0
        else:
            indices = selected[2].split(":")
            low = number(indices[-1], model["constants"])
            high = number(indices[0], model["constants"])
            return (value >> low) & ((1 << (high - low + 1)) - 1)
    raise ValueError(f"reset requires integration or semantic annotation: {expression}")


def decompose(expression: str, model: dict, lsb: int = 0, depth: int = 0) -> list[dict]:
    expression = expression.strip()
    if depth > 6:
        raise ValueError("readback expression recursion")
    repeat = re.fullmatch(r"\{([^{}]+)\{(.+)\}\}", expression, re.S)
    if repeat:
        width = width_of(expression, model)
        if width == 0:
            return []
        try:
            zero = number(repeat[2], model["constants"]) == 0
        except ValueError:
            zero = False
        return [
            {
                "lsb": lsb,
                "msb": lsb + width - 1,
                "name": "Reserved" if zero else "Sign extension",
                "description": "Reserved; reads zero."
                if zero
                else "Copies the sign bit into the upper word bits.",
                "reset": "0" if zero else "Register reset applies",
                "expression": expression,
            }
        ]
    if expression in model["assigns"]:
        assigned = model["assigns"][expression]
        if assigned.startswith("{"):
            return decompose(assigned, model, lsb, depth + 1)
    if expression.startswith("{") and expression.endswith("}"):
        fields = []
        offset = lsb
        for part in reversed(split_top(expression[1:-1])):
            width = width_of(part, model)
            fields.extend(decompose(part, model, offset, depth + 1))
            offset += width
        return fields
    width = width_of(expression, model)
    if width > 32:
        raise ValueError("unselected wide register source")
    try:
        value = number(expression, model["constants"])
        name = "Reserved" if value == 0 else "Constant"
        reset = hex(value)
        description = (
            "Reads zero." if value == 0 else f"Fixed identification/capability value {hex(value)}."
        )
    except ValueError:
        name = friendly(expression)
        try:
            reset = hex(reset_of(expression, model) & ((1 << width) - 1))
        except ValueError:
            reset = model["resets"].get(expression, "Live / source-dependent")
        description = name.replace("_", " ").capitalize() + "."
    return [
        {
            "lsb": lsb,
            "msb": lsb + width - 1,
            "name": name,
            "description": description,
            "reset": reset,
            "expression": expression,
        }
    ]


def read_expressions(name: str, text: str) -> list[str]:
    expressions = []
    token = r"(?:`?\w+|\d+'[hHbBdD][0-9a-fA-F_]+)"
    labels = list(
        re.finditer(r"^[ \t]*((?:" + token + r")(?:\s*,\s*" + token + r")*)[ \t]*:", text, re.M)
    )
    for index, found in enumerate(labels):
        if name not in re.findall(r"\w+", found[1]):
            continue
        body = text[
            found.end() : labels[index + 1].start() if index + 1 < len(labels) else len(text)
        ]
        for match in re.finditer(
            r"\b\w*(?:rdata|read_data|read_value|readback)\w*\s*=\s*([^;]+);", body
        ):
            expr = match[1].strip()
            if expr not in expressions:
                expressions.append(expr)
    if not expressions:
        aliases = re.findall(
            r"localparam\s+\w+\s+(\w+)\s*=\s*\w+'\(`" + re.escape(name) + r"\)", text
        )
        for alias in aliases:
            expressions.extend(read_expressions(alias, text))
    return expressions


def writable_symbols(text: str) -> set[str]:
    symbols = set()
    tokens = re.compile(r"\bbegin\b|\bend\b")
    for found in re.finditer(
        r"if\s*\([^\n)]*(?:s_write|apb4\.pwrite|write_valid_i)[^\n)]*\)\s*begin", text
    ):
        depth = 1
        end = len(text)
        for token in tokens.finditer(text, found.end()):
            depth += 1 if token[0] == "begin" else -1
            if depth == 0:
                end = token.start()
                break
        block = text[found.end() : end]
        cases = list(re.finditer(r"^[ \t]*(`?\w+)[ \t]*:", block, re.M))
        for i, case in enumerate(cases):
            body = block[case.end() : cases[i + 1].start() if i + 1 < len(cases) else len(block)]
            if re.search(
                r"\b(?!s_write_err\b|s_access_err\b)\w+(?:_d|_q|_write|_en)(?:\[[^]]+\])*\s*(?:<=|=)",
                body,
            ):
                symbols.add(case[1].lstrip("`"))
    return symbols


def resolve_producer(
    expression: str, model: dict, support: list[dict], depth: int = 0
) -> list[dict] | None:
    """Follow named input/output bindings to an explicitly packed status producer."""
    if depth > 5:
        return None
    expression = expression.strip()
    base = expression.split("[", 1)[0]
    if not re.fullmatch(r"\w+", base):
        return None
    # A combinational packed output can be assigned as a whole or once per lane.
    packed = re.search(
        r"\b" + re.escape(base) + r"(?:\[[^]]+\])?\s*=\s*(\{[^;]+\});", model["text"]
    )
    if packed:
        try:
            result = decompose(packed[1], model)
            if sum(f["msb"] - f["lsb"] + 1 for f in result) == 32:
                return result
        except ValueError:
            pass
    # Follow an output port attached to the local wire.
    for candidate in support:
        module = candidate["module"]
        instances = re.finditer(
            r"\b" + re.escape(module) + r"\s*(?:#\s*\(.*?\)\s*)?\w+\s*\((.*?)\);",
            model["text"],
            re.S,
        )
        for instance in instances:
            for port, wire in re.findall(r"\.(\w+_o)\s*\(\s*([^()]+)\s*\)", instance[1]):
                if wire.strip().split("[", 1)[0] == base:
                    target = candidate["model"]
                    if port in target["assigns"]:
                        try:
                            result = decompose(target["assigns"][port], target)
                            if sum(f["msb"] - f["lsb"] + 1 for f in result) == 32:
                                return result
                        except ValueError:
                            pass
                    result = resolve_producer(port, target, support, depth + 1)
                    if result:
                        return result
    # The register's named input is connected by its wrapper.
    if base.endswith("_i"):
        for wrapper in support:
            instances = re.finditer(
                r"\b"
                + re.escape(model.get("module", "__none__"))
                + r"\s*(?:#\s*\(.*?\)\s*)?\w+\s*\((.*?)\);",
                wrapper["model"]["text"],
                re.S,
            )
            for instance in instances:
                wire = named_argument(instance[1], base)
                if wire:
                    target = wrapper["model"]
                    if wire in target["assigns"]:
                        try:
                            result = decompose(target["assigns"][wire], target)
                            if sum(f["msb"] - f["lsb"] + 1 for f in result) == 32:
                                return result
                        except ValueError:
                            pass
                    result = resolve_producer(wire, target, support, depth + 1)
                    if result:
                        return result
    return None


def markdown_rows(path: str) -> list[dict]:
    text = (ROOT / path).read_text(encoding="utf-8")
    rows = []
    headers = []
    section = ""
    for line in text.splitlines():
        if line.startswith("#"):
            section = line.lstrip("# ")
        if not line.startswith("|"):
            headers = []
            continue
        cells = re.split(r"\s+\|\s+", line.strip().strip("|").strip())
        if any(c.lower() in {"offset", "local offset", "register", "name"} for c in cells):
            headers = cells
        elif (
            headers
            and len(cells) == len(headers)
            and not all(re.fullmatch(r"[-: ]+", c) for c in cells)
        ):
            row = dict(zip([h.lower() for h in headers], cells))
            row["section"] = section
            rows.append(row)
    return rows


def clean_markdown(value: str) -> str:
    return value.replace("`", "").replace("**", "").replace("<br>", " ")


def refine_fields(record: dict, spec: dict, definitions: dict, model: dict) -> list[dict]:
    """Combine explicit masks, bit selectors and typed readback lanes."""
    constants = model["constants"]
    existing = record["fields"]
    if not existing:
        return []
    candidates = []
    # Named slices of a packed readback word, or named output consumers of state.
    for part in existing:
        expr = part["expression"]
        if not re.fullmatch(r"\w+", expr):
            continue
        patterns = [
            (rf"\b{expr}\[([^]]+)\]\s*=(?!=)\s*([^;]+);", False),
            (rf"\bassign\s+(\w+)\s*=\s*{expr}\[([^]]+)\]\s*;", True),
        ]
        for pattern, reverse in patterns:
            for match in re.finditer(pattern, model["text"]):
                selector, value = (match[2], match[1]) if reverse else match.groups()
                try:
                    limits = selector.split(":")
                    high = number(limits[0], constants)
                    low = number(limits[-1], constants)
                except ValueError:
                    continue
                if high >= part["msb"] - part["lsb"] + 1:
                    continue
                field_name = (
                    friendly(value) if reverse or "`" not in selector else selector.replace("`", "")
                )
                candidates.append(
                    {
                        "lsb": part["lsb"] + low,
                        "msb": part["lsb"] + high,
                        "name": field_name,
                        "description": field_name.replace("_", " ").capitalize() + ".",
                        "reset": part["reset"],
                        "expression": f"{expr}[{selector}]",
                    }
                )
    prefixes = [
        record["symbol"].removesuffix("_OFFSET") + "_",
        record["symbol"].removeprefix("APB4_") + "_",
    ]
    prefixes += spec.get("field_aliases", {}).get(record["name"], [])
    for prefix in prefixes:
        entries = []
        for symbol, definition in definitions.items():
            if not symbol.startswith(prefix) or symbol not in constants:
                continue
            tail = symbol[len(prefix) :]
            if tail in {"ALL", "MASK"} or re.search(
                r"(?:VALID|WRITABLE|ALL|IMMUTABLE)_MASK$|_(?:SHIFT|WIDTH|MIN|MAX)$", tail
            ):
                continue
            value = constants[symbol]
            if tail.endswith("_MASK"):
                if value == 0:
                    continue
                low = (value & -value).bit_length() - 1
                high = value.bit_length() - 1
                if value != ((1 << (high - low + 1)) - 1) << low:
                    continue
                entries.append((low, high, tail.removesuffix("_MASK"), symbol))
            elif re.fullmatch(r"\d+", definition["expression"]) and 0 <= value < 32:
                entries.append(
                    (value, None, tail.removesuffix("_LSB").removesuffix("_BIT"), symbol)
                )
        entries.sort()
        payload_high = max((f["msb"] for f in existing if f["name"] != "Reserved"), default=31)
        for mask_name in (prefix + "VALID_MASK", prefix + "WRITABLE_MASK"):
            if mask_name in constants:
                payload_high = constants[mask_name].bit_length() - 1
        for index, (low, high, name, symbol) in enumerate(entries):
            if high is None:
                scalar_use = re.search(r"\[\s*`" + re.escape(symbol) + r"\s*\]", model["text"])
                if scalar_use:
                    high = low
                elif index + 1 < len(entries):
                    high = entries[index + 1][0] - 1
                elif symbol.endswith("_LSB"):
                    high = payload_high
                else:
                    high = low
            if high < low or high > 31:
                continue
            candidates.append(
                {
                    "lsb": low,
                    "msb": high,
                    "name": name,
                    "description": name.replace("_", " ").capitalize() + ".",
                    "reset": "Register reset applies",
                    "expression": "`" + symbol,
                }
            )
    if not candidates:
        return existing
    for field in candidates:
        for prefix in prefixes:
            if field["name"].startswith(prefix):
                field["name"] = field["name"][len(prefix) :]
        field["description"] = field["name"].replace("_", " ").capitalize() + "."
    result = []
    used = set()
    for field in sorted(candidates, key=lambda f: (f["msb"] - f["lsb"], f["lsb"])):
        bits = set(range(field["lsb"], field["msb"] + 1))
        if bits & used:
            continue
        result.append(field)
        used |= bits
    for original in existing:
        remaining = [b for b in range(original["lsb"], original["msb"] + 1) if b not in used]
        while remaining:
            first = last = remaining.pop(0)
            while remaining and remaining[0] == last + 1:
                last = remaining.pop(0)
            result.append({**original, "lsb": first, "msb": last})
    return sorted(result, key=lambda f: f["lsb"])


def extract_profile(ip: str, spec: dict, annotations: dict) -> dict:
    paths = list(dict.fromkeys(spec.get("defines", []) + spec["rtl"]))
    definitions, constants = parse_definitions(paths, spec.get("parameters", {}))
    text = "\n".join(strip_comments((ROOT / p).read_text(encoding="utf-8")) for p in spec["rtl"])
    model = source_model(text, constants)
    model["definitions"] = definitions
    for name, definition in definitions.items():
        literal = LITERAL.fullmatch(definition["expression"])
        if literal and literal["w"]:
            model["widths"].setdefault(name, int(literal["w"]))
    model["widths"].update(spec.get("signal_widths", {}))
    module_match = re.search(r"\bmodule\s+(\w+)", text)
    model["module"] = module_match[1] if module_match else ""
    support = []
    for source in spec.get("support", []):
        support_text = strip_comments((ROOT / source).read_text(encoding="utf-8"))
        support_module = re.search(r"\bmodule\s+(\w+)", support_text)
        if support_module is None:
            continue
        _, support_constants = parse_definitions(
            spec.get("defines", []) + [source], spec.get("parameters", {})
        )
        support_model = source_model(support_text, support_constants)
        support_model["module"] = support_module[1]
        support.append({"module": support_module[1], "model": support_model})
    rows = markdown_rows(spec["document"])
    writable = writable_symbols(text)
    producer_cache = {}
    records = []
    for group in spec["groups"]:
        for symbol, definition in definitions.items():
            if not re.fullmatch(group["pattern"], symbol) or symbol in group.get("exclude", []):
                continue
            literal = definition["expression"]
            if not (
                LITERAL.fullmatch(literal)
                or literal.startswith("`SOC_SYSCTRL_")
                or symbol.endswith("Offset")
            ):
                continue
            sized = LITERAL.fullmatch(literal)
            if sized and (not sized["w"] or not 6 <= int(sized["w"]) <= 16):
                continue
            if symbol not in constants:
                raise ValueError(f"{ip}: unresolved register offset {symbol}")
            value = constants[symbol]
            if re.search(r"(?:BASE|STRIDE|LAST|COUNT)$", symbol) and not re.search(
                r"`?" + re.escape(symbol) + r"\s*:", text
            ):
                continue
            if not 0 <= value < group.get("limit", 0x10000):
                continue
            name = re.sub(group["strip"], "", symbol)
            name = re.sub(r"_OFFSET$|Offset$", "", name)
            key = group["id"] + "." + name
            override = annotations.get(key, {})
            doc_name = group.get("doc_name_prefix", "") + name
            exact = [
                r
                for r in rows
                if clean_markdown(r.get("name", r.get("register", ""))).strip() == doc_name
            ]
            matching = [
                r
                for r in rows
                if doc_name in re.findall(r"[A-Z][A-Z0-9_]+", r.get("name", r.get("register", "")))
            ]
            matching = exact or matching
            if group.get("section"):
                scoped = [r for r in matching if r["section"] == group["section"]]
                matching = scoped or matching
            if not matching:
                for row in rows:
                    if group.get("section") and row["section"] != group["section"]:
                        continue
                    offset_text = row.get(
                        "offset", row.get("local offset", row.get("channel offset", ""))
                    )
                    values = re.findall(r"(?:0x)?([0-9a-fA-F]{2,6})", offset_text)
                    if not values:
                        continue
                    lo, hi = int(values[0], 16), int(values[-1], 16)
                    compare = (
                        value
                        if "local offset" in row or "channel offset" in row
                        else group["base"] + value
                    )
                    if lo <= compare <= hi:
                        matching.append(row)
            row = matching[-1] if matching else {}
            description = clean_markdown(
                row.get(
                    "description",
                    row.get(
                        "purpose",
                        row.get(
                            "meaning",
                            row.get(
                                "contract", row.get("semantics", row.get("access / purpose", ""))
                            ),
                        ),
                    ),
                )
            )
            access = clean_markdown(row.get("access", row.get("r/w", "")))
            if not access and re.match(r"(?:RO|RW|WO)\b", description):
                access = description.split(",")[0].split()[0]
            access = access or spec.get("default_access", "")
            expressions = read_expressions(symbol, text)
            fields, issue = [], None
            for expression in reversed(expressions):
                try:
                    fields = decompose(expression, model)
                    if sum(f["msb"] - f["lsb"] + 1 for f in fields) == 32:
                        break
                except ValueError:
                    fields = []
            if not fields:
                issue = f"Review field layout: {expressions or 'write-only / indirect decode'}"
            record = {
                "key": key,
                "width": 32,
                "name": name,
                "symbol": symbol,
                "offset": value,
                "group": group["id"],
                "access": access,
                "reset": clean_markdown(row.get("reset", "")),
                "description": description,
                "fields": fields,
                "source": definition["source"],
                "line": definition["line"],
                "readback": expressions,
                "review": issue,
            }
            record["write_case_present"] = symbol in writable
            if fields:
                try:
                    reset = 0
                    for field in fields:
                        reset |= (
                            number(field["reset"], constants)
                            & ((1 << (field["msb"] - field["lsb"] + 1)) - 1)
                        ) << field["lsb"]
                    record["rtl_reset"] = f"0x{reset:08X}"
                    record["reset"] = record["rtl_reset"]
                except ValueError:
                    pass
            record.update(override)
            if "fields" in override:
                record["review"] = None
            else:
                record["fields"] = refine_fields(record, spec, definitions, model)
                significant = [f for f in record["fields"] if f["name"] != "Reserved"]
                if (
                    len(significant) == 1
                    and significant[0]["msb"] - significant[0]["lsb"] == 31
                    and re.search(r"STATUS|CONFIG|CFG|CTRL|CAPABILITY|ERROR", record["name"])
                    and not re.search(r"ADDR|COUNT", record["name"])
                ):
                    expression = significant[0]["expression"]
                    if expression not in producer_cache:
                        producer_cache[expression] = resolve_producer(expression, model, support)
                    resolved = producer_cache[expression]
                    if resolved:
                        record["fields"] = resolved
            try:
                word_reset = number(record["reset"], constants)
            except ValueError:
                word_reset = None
            if not record["reset"] and record["fields"]:
                try:
                    word_reset = 0
                    for field in record["fields"]:
                        word_reset |= number(field["reset"], constants) << field["lsb"]
                    record["reset"] = f"0x{word_reset:08X}"
                except ValueError:
                    word_reset = None
            if word_reset is not None:
                for field in record["fields"]:
                    field["reset"] = hex(
                        (word_reset >> field["lsb"])
                        & ((1 << (field["msb"] - field["lsb"] + 1)) - 1)
                    )
            if record["access"].startswith("WO"):
                record["reset"] = "Not retained"
            elif not record["reset"]:
                record["reset"] = "Dynamic"
            for field in record["fields"]:
                if field["reset"] in {"Live / source-dependent", "Register reset applies"}:
                    field["reset"] = (
                        "Dynamic" if record["reset"].startswith("Dynamic") else "See register"
                    )
            records.append(record)
    for extra in spec.get("extra", []):
        record = {
            "key": extra["group"] + "." + extra["name"],
            "width": 32,
            "symbol": None,
            "line": 1,
            "source": spec["rtl"][0],
            "readback": [],
            "review": None,
            **extra,
        }
        records.append(record)
    records.sort(
        key=lambda r: (
            next(i for i, g in enumerate(spec["groups"]) if g["id"] == r["group"]),
            r["offset"],
        )
    )
    alias = {
        "sram": "onchip_sram",
        "mailbox": "hp_mailbox",
        "monitor": "fabric_monitor",
        "extensions": "extension",
        "aclint": "clint",
        "wdg": "watchdog",
    }.get(ip, ip)
    candidates = [f"crt/include/retrosoc/hal/{alias}_regs.h", f"crt/src/hal/{alias}.c"]
    if spec["rtl"][0].startswith("rtl/managed/clusterip/"):
        candidates = [
            f"rtl/managed/clusterip/{ip}/sw/include/{ip}_regs.h",
            f"rtl/managed/clusterip/{ip}/sw/include/{ip}.h",
        ] + candidates
    if ip.startswith("mpw-"):
        candidates = ["app/network/userip/src/user_ip_regs.h"]
    c_source = next((path for path in candidates if (ROOT / path).is_file()), None)
    for record in records:
        record["c_source"] = c_source
    paths += spec.get("support", [])
    if c_source:
        paths.append(c_source)
    return {
        "id": ip,
        "groups": spec["groups"],
        "registers": records,
        "document": spec["document"],
        "sources": paths,
    }


def collect_registers() -> dict[str, dict]:
    specs = json.loads(PROFILE.read_text(encoding="utf-8"))
    annotations = json.loads(ANNOTATIONS.read_text(encoding="utf-8"))
    result = {ip: extract_profile(ip, spec, annotations.get(ip, {})) for ip, spec in specs.items()}
    validate_reference(result)
    return result


def validate_reference(reference: dict) -> None:
    for ip, item in reference.items():
        if not item["registers"]:
            raise ValueError(f"empty register reference: {ip}")
        offsets = set()
        keys = set()
        for register in item["registers"]:
            key = register["key"]
            address = (register["group"], register["offset"])
            if key in keys or address in offsets or register["offset"] % 4:
                raise ValueError(f"duplicate or unaligned register: {ip}/{key}")
            keys.add(key)
            offsets.add(address)
            if register.get("review") or not register["description"] or not register["access"]:
                raise ValueError(f"incomplete register reference: {ip}/{key}")
            bits = [
                bit for field in register["fields"] for bit in range(field["lsb"], field["msb"] + 1)
            ]
            if sorted(bits) != list(range(32)):
                raise ValueError(f"overlapping or incomplete bit layout: {ip}/{key}")
            if register["width"] != 32:
                raise ValueError(f"unsupported register width: {ip}/{key}")
            try:
                word_reset = number(register["reset"])
            except ValueError:
                word_reset = None
            if word_reset is not None:
                if not 0 <= word_reset < 2**32:
                    raise ValueError(f"reset outside register width: {ip}/{key}")
                if "rtl_reset" in register and number(register["rtl_reset"]) != word_reset:
                    raise ValueError(f"reset disagrees with RTL: {ip}/{key}")
            for field in register["fields"]:
                try:
                    field_reset = number(field["reset"])
                except ValueError:
                    continue
                mask = (1 << (field["msb"] - field["lsb"] + 1)) - 1
                if not 0 <= field_reset <= mask:
                    raise ValueError(f"reset outside field width: {ip}/{key}/{field['name']}")
                if word_reset is not None and field_reset != (word_reset >> field["lsb"]) & mask:
                    raise ValueError(f"inconsistent field reset: {ip}/{key}/{field['name']}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    result = collect_registers()
    args.audit.parent.mkdir(parents=True, exist_ok=True)
    args.audit.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for name, item in result.items():
        incomplete = [
            r for r in item["registers"] if r["review"] or not r["access"] or not r["description"]
        ]
        print(name, len(item["registers"]), "to review", len(incomplete))
