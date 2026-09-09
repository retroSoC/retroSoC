"""Publication data for routed resources and checked integer timing/buffer examples."""
from __future__ import annotations

import ast
import copy
import json
import re
from pathlib import Path

UINT32_MAX = (1 << 32) - 1
COLLECTIONS = ("dma_routes", "channels", "engines", "conflicts", "devices", "glossary")


def dependencies(spec: dict) -> set[str]:
    paths = set(spec.get("sources", []))
    for name in COLLECTIONS:
        for row in spec.get(name, []):
            paths.update(row.get("sources", []))
            paths.update(x["file"] for x in row.get("bindings", []))
            for report in row.get("reports", []):
                paths.update((report["path"], report["profile"]))
    return paths


def positive(*values: int) -> None:
    if any(type(v) is not int or v <= 0 or v > UINT32_MAX for v in values):
        raise ValueError("positive 32-bit inputs required")


def uart_timing(clock: int, baud: int) -> dict | None:
    positive(clock, baud)
    scaled = (clock * 256 + baud // 2) // baud
    if not 4096 <= scaled <= 0xFFFFFFFF:
        return None
    return {"integer": scaled >> 8, "fraction": scaled & 255,
            "actual_hz": round(clock * 256 / scaled, 6),
            "error_ppm": round((clock * 256 / scaled / baud - 1) * 1_000_000, 3)}


def i2c_timing(clock: int, rate: int) -> dict | None:
    positive(clock, rate)
    if rate > 1_000_000:
        return None
    ns = ((4700, 4000, 4000, 4700, 250, 4000, 4700) if rate <= 100_000 else
          (1300, 600, 600, 600, 100, 600, 1300) if rate <= 400_000 else
          (500, 260, 260, 260, 50, 260, 500))
    cycles = [(clock * value + 999_999_999) // 1_000_000_000 for value in ns]
    cycles[0] += max(0, (clock + rate - 1) // rate - cycles[0] - cycles[1])
    if any(not 0 < value <= 65535 for value in cycles):
        return None
    return {"cycles": cycles, "actual_hz": round(clock / (cycles[0] + cycles[1]), 6),
            "error_ppm": round((clock / (cycles[0] + cycles[1]) / rate - 1) * 1_000_000, 3)}


def timer_timing(clock: int, milliseconds: int) -> dict | None:
    positive(clock, milliseconds)
    cycles = (clock * milliseconds + 999) // 1000
    divider = max(1, (cycles + (1 << 32) - 1) // (1 << 32))
    if divider > 65536:
        return None
    ticks = (cycles + divider - 1) // divider
    return {"prescale": divider - 1, "load": ticks - 1,
            "actual_ms": round(divider * ticks * 1000 / clock, 9)}


def i2s_timing(clock: int, rate: int, bits: int) -> dict | None:
    positive(clock, rate, bits)
    divisor = rate * 4 * bits
    if bits not in (16, 24) or clock % divisor or not 1 <= clock // divisor <= 256:
        return None
    return {"sclk_div": clock // divisor - 1, "lrck_div": bits - 1,
            "actual_hz": rate, "error_ppm": 0}


def aligned_bytes(size: int, alignment: int = 64) -> int:
    positive(size, alignment)
    if alignment & (alignment - 1):
        raise ValueError("alignment must be a power of two")
    result = (size + alignment - 1) // alignment * alignment
    if result > UINT32_MAX:
        raise ValueError("buffer allocation overflows 32 bits")
    return result


def buffer_budget(kind: str, *, width=0, height=0, rate=0, bits=0, milliseconds=0,
                  count=1, descriptors=0, alignment=64) -> dict:
    positive(count)
    if kind == "frame":
        positive(width, height)
        payload = width * height * 2
        storage = ((width + 1) // 2) * 4 * height
        supported = width % 2 == 0
    elif kind == "audio":
        positive(rate, bits, milliseconds)
        if bits not in (16, 24) or rate * milliseconds % 1000:
            raise ValueError("audio block requires whole 16/24-bit sample frames")
        samples = rate * milliseconds // 1000 * 2
        payload = samples * bits // 8
        storage = samples * (2 if bits == 16 else 4)
        supported = True
    elif kind == "descriptors":
        positive(descriptors)
        payload = storage = descriptors * 64
        supported = True
    else:
        raise ValueError("unknown buffer kind")
    stride = aligned_bytes(storage, alignment)
    if stride * count > UINT32_MAX:
        raise ValueError("buffer allocation overflows 32 bits")
    return {"payload_bytes": payload, "storage_bytes": storage, "stride_bytes": stride,
            "total_bytes": stride * count, "dma_supported": supported}


def constants(text: str, prefix: str, rtl=False) -> dict[str, int]:
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    pattern = (rf"\b({prefix}\w+)\s*=\s*\d+'d(\d+)\s*;" if rtl else
               rf"\b({prefix}\w+)\s*(?:=\s*|\s+)(\d+)(?:U)?(?=\s*[,;\n])")
    pairs = re.findall(pattern, text)
    if len({name for name, _ in pairs}) != len(pairs):
        raise ValueError(f"duplicate constant: {prefix}")
    return {name: int(value) for name, value in pairs}


def clean_source(text: str) -> str:
    return re.sub(r"\s+", "", re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S))


def validate_programming(spec: dict, ids: set[str], root: Path, revision: str) -> None:
    for relative in dependencies(spec):
        path = root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("programming path escapes repository")
        if not path.is_file():
            raise ValueError(f"missing programming source: {relative}")
    for name in COLLECTIONS:
        rows = spec[name]
        keys = [r["id"] for r in rows]
        if len(set(keys)) != len(keys):
            raise ValueError(f"duplicate programming identifier: {name}")
        for row in rows:
            if not row.get("sources"):
                raise ValueError(f"programming source missing: {row['id']}")
            if not set(row.get("ips", [])) <= ids:
                raise ValueError(f"unknown programming IP: {row['id']}")
            for binding in row.get("bindings", []):
                text = (root / binding["file"]).read_text(encoding="utf-8")
                if clean_source(binding["text"]) not in clean_source(text):
                    raise ValueError(f"programming binding changed: {row['id']}")
            if name == "devices":
                if row["board"] not in ("Not established", "Reported pass") or row["silicon"] not in ("Not established", "Reported pass"):
                    raise ValueError("invalid device qualification state")
                for stage in ("board", "silicon"):
                    if row[stage] == "Reported pass":
                        reports = [r for r in row.get("reports", []) if r.get("stage") == stage]
                        if not reports or not all(r.get("revision") == revision and r.get("result") == "pass" and r.get("path") and r.get("profile") for r in reports):
                            raise ValueError(f"device claim requires matching evidence: {row['id']}")
    sdk = constants((root / "crt/include/retrosoc/hal/dma.h").read_text(), "RS_DMA_REQUEST_")
    rtl = constants((root / "rtl/ip/peripheral/dma_pkg.sv").read_text(), "DMA_REQUEST_", rtl=True)
    routes = spec["dma_routes"]
    if {r["sdk"] for r in routes} != set(sdk) or {r["rtl"] for r in routes} != set(rtl):
        raise ValueError("DMA route coverage mismatch")
    if len(routes) != len(sdk) or len({r["sdk"] for r in routes}) != len(routes):
        raise ValueError("duplicate DMA request mapping")
    for row in routes:
        if sdk[row["sdk"]] != rtl[row["rtl"]]:
            raise ValueError(f"RTL/SDK DMA request mismatch: {row['id']}")
        if sdk[row["sdk"]] and not row.get("bindings"):
            raise ValueError(f"missing DMA connection evidence: {row['id']}")


def credit_values(text: str, function: str, masters: int) -> list[int]:
    """Read only the bounded if/return form of the two current credit functions."""
    body = re.search(rf"function automatic[^;]*\b{function}\([^;]*;(.+?)endfunction", text, re.S)
    if body is None:
        raise ValueError("credit function missing")
    branches = re.findall(r"if\s*\((.*?)\)\s*return CountWidth'\((\d+)\);", body[1], re.S)
    remainder = re.sub(r"if\s*\((.*?)\)\s*return CountWidth'\((\d+)\);", "", body[1], flags=re.S)
    if clean_source(remainder) != "return'0;":
        raise ValueError("unsupported credit function shape")
    allowed = (ast.Expression, ast.BoolOp, ast.And, ast.Or, ast.Compare, ast.Name, ast.Load,
               ast.Constant, ast.Eq, ast.LtE, ast.GtE, ast.Lt, ast.Gt)
    parsed = []
    for condition, value in branches:
        tree = ast.parse(condition.replace("&&", " and ").replace("||", " or "), mode="eval")
        if any(not isinstance(node, allowed) or isinstance(node, ast.Name) and node.id != "master" for node in ast.walk(tree)):
            raise ValueError("unsupported credit condition")
        parsed.append((compile(tree, "<credit condition>", "eval"), int(value)))
    return [next((value for expression, value in parsed if eval(expression, {"__builtins__": {}}, {"master": master})), 0) for master in range(masters)]


def collect_programming(root: Path, spec: dict, ids: set[str], revision: str) -> dict:
    validate_programming(spec, ids, root, revision)
    result = copy.deepcopy(spec)
    sdk_text = (root / "crt/include/retrosoc/hal/dma.h").read_text()
    sdk = constants(sdk_text, "RS_DMA_REQUEST_")
    channels = constants(sdk_text, "RS_DMA_CHANNEL_")
    channels.update(constants((root / "crt/include/retrosoc/hal/dma_regs.h").read_text(), "RS_DMA_CHANNEL_"))
    channels.pop("RS_DMA_CHANNEL_COUNT")
    if {r["symbol"] for r in spec["channels"]} != set(channels):
        raise ValueError("DMA channel allocation coverage mismatch")
    for row in result["dma_routes"]:
        row["number"] = sdk[row["sdk"]]
    for row in result["channels"]:
        row["number"] = channels[row["symbol"]]
    result["dma_routes"].sort(key=lambda r: r["number"])
    result["channels"].sort(key=lambda r: r["number"])
    topology = json.loads((root / "rtl/mini/integration/soc_topology.json").read_text())
    interrupts = {row["name"]: row["core_bit"] for row in topology["interrupts"]}
    wiring = clean_source((root / "rtl/mini/top/apb4_periph.sv").read_text())
    for row in result["dma_routes"]:
        if row["irq"] is not None and row["irq"] not in interrupts:
            raise ValueError(f"unknown endpoint interrupt: {row['id']}")
        row["lp_irq"] = ("Client-dependent" if row["number"] == 0 else
                         str(interrupts[row["irq"]]) if row["irq"] else "No separate line")
    for row in result["engines"]:
        if row["irq"] not in interrupts:
            raise ValueError(f"unknown DMA engine interrupt: {row['id']}")
        routed = re.findall(r"s_hp_plic_source\[(\d+)\]=" + re.escape(row["hp_signal"]) + ";", wiring)
        if len(routed) != 1:
            raise ValueError(f"HP interrupt routing changed: {row['id']}")
        row["lp_irq"], row["hp_irq"] = interrupts[row["irq"]], int(routed[0])
    crossbar = (root / "rtl/mini/top/axi4_data_crossbar.sv").read_text()
    result["read_credits"] = credit_values(crossbar, "master_read_limit", 8)
    result["write_credits"] = credit_values(crossbar, "master_write_limit", 8)
    result["timing"] = {
        "uart": [{"clock": c, "target": b, **uart_timing(c, b)} for c, b in ((24_000_000, 115200), (72_000_000, 115200))],
        "i2c": [{"clock": 24_000_000, "target": rate, **i2c_timing(24_000_000, rate)} for rate in (100_000, 400_000, 1_000_000)],
        "timer": [{"clock": 24_000_000, "target_ms": t, **timer_timing(24_000_000, t)} for t in (1, 1000)],
        "i2s": [{"clock": 18_432_000, "target": rate, "bits": bits, **i2s_timing(18_432_000, rate, bits)} for bits in (16, 24) for rate in (48000, 96000)],
    }
    result["budgets"] = [
        {"name": "VGA RGB565, 640 x 480, two buffers", **buffer_budget("frame", width=640, height=480, count=2)},
        {"name": "Odd-width example, 641 x 480, one buffer", **buffer_budget("frame", width=641, height=480)},
        *[{"name": f"Stereo {bits}-bit, 48 kHz, 10 ms, two buffers", **buffer_budget("audio", rate=48000, bits=bits, milliseconds=10, count=2)} for bits in (16, 24)],
        {"name": "Eight 64-byte DMA TCDs", **buffer_budget("descriptors", descriptors=8)},
    ]
    return result
