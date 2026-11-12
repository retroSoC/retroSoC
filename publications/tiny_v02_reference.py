"""Source-bound Tiny v0.2 additions; these records never generate hardware ABIs."""
from __future__ import annotations

import re
from pathlib import Path

from publications import register_reference as registers


def rcu_registers(fact: dict, root: Path) -> dict:
    from publications.tiny_reference import BOOK, SYSCTRL, field_rows, read

    sv = "rtl/tiny/top/tiny_rcu_regs.svh"
    header = "crt/include/retrosoc/hal/rcu_regs.h"
    definitions = (root / sv).read_text(encoding="utf-8")
    offsets = {name: int(value, 16) for name, value in
               re.findall(r"`define APB4_TINY_RCU__(\w+) 32'h([0-9a-fA-F]+)", definitions)}
    c_offsets = {name: int(value, 16) for name, value in re.findall(
        r"#define RS_TINY_RCU_(\w+)_OFFSET\s+UINT32_C\(0x([0-9a-fA-F]+)\)",
        (root / header).read_text(encoding="utf-8"))}
    spec = read(root / BOOK / "rcu-registers.json")
    if offsets != c_offsets or offsets != {r["name"]: r["offset"] for r in spec}:
        raise ValueError("Tiny RCU SV/C/publication register parity changed")
    text = (root / SYSCTRL).read_text(encoding="utf-8")
    aliases = dict(re.findall(r"localparam logic \[31:0\] (\w+)\s*= `APB4_TINY_RCU__(\w+);", text))
    decode = text.split("unique case (s_rcu_offset)")[1].split("endcase")[0]
    actual = {aliases[a] for a in re.findall(r"^\s*(\w+):", decode, re.M) if a in aliases}
    if actual != set(offsets):
        raise ValueError("Tiny RCU read decode coverage changed")
    rows = []
    for row in spec:
        fields = field_rows([tuple(f) for f in row["fields"]])
        reset = row["reset"]
        if row["name"] == "CAPABILITY":
            reset = hex(0x1A01 | (0x10C if fact["profile"]["HAVE_PLL"] == "YES" else 2))
        try:
            value = registers.number(reset)
        except ValueError:
            value = None
        for field in fields:
            field["reset"] = (hex((value >> field["lsb"]) & ((1 << (field["msb"] - field["lsb"] + 1)) - 1))
                              if value is not None else "0" if field["name"] == "Reserved" else reset)
        rows.append(dict(key="main." + row["name"], name=row["name"], symbol="APB4_TINY_RCU__" + row["name"],
                         offset=row["offset"], group="main", width=32, access=row["access"], reset=reset,
                         description=row["description"], fields=fields, source=sv,
                         line=definitions[:definitions.index("`define APB4_TINY_RCU__" + row["name"] + " ")].count("\n") + 1,
                         c_source=header, review=None, readback=["Tiny SYSCTRL AON register decode"]))
    return dict(id="rcu", groups=[dict(id="main", title="RCU offsets relative to SYSCTRL", base=0, stride=0, count=1)],
                registers=rows, document="docs/ip/tiny-soc-r2-clock-reset.md",
                sources=[SYSCTRL, sv, header, "crt/include/retrosoc/hal/rcu.h", "crt/src/hal/rcu.c"])


def ppalite_registers(fact: dict, root: Path) -> dict:
    """Read the handwritten ABI and reject drift in reviewed field producers."""
    from publications.tiny_reference import BOOK, field_rows, read, require_snippets

    sv = "rtl/ip/ppalite/ppalite_define.svh"
    rtl = "rtl/ip/ppalite/ppalite_reg.sv"
    header = "crt/include/retrosoc/hal/ppalite_regs.h"
    definitions = (root / sv).read_text(encoding="utf-8")
    offsets = {name: int(value, 16) for name, value in re.findall(
        r"`define APB4_PPALITE__(\w+) 32'h([0-9a-fA-F]+)", definitions)
        if not name.endswith(("_VALUE", "_MASK"))}
    c_offsets = {name: int(value, 16) for name, value in re.findall(
        r"#define RS_PPALITE_ABI_APB4_(\w+)\s+UINT32_C\(0x([0-9a-fA-F]+)\)",
        (root / header).read_text(encoding="utf-8")) if not name.endswith(("_VALUE", "_MASK"))}
    spec = read(root / BOOK / "ppalite-registers.json")
    if offsets != c_offsets or offsets != {r["name"]: r["offset"] for r in spec}:
        raise ValueError("Tiny PPALite SV/C/publication register parity changed")
    text = (root / rtl).read_text(encoding="utf-8")
    decode = text.split("s_read_data = 32'd0;", 1)[1].split("endcase", 1)[0]
    actual = set(re.findall(r"`APB4_PPALITE__(\w+)\s*:", decode))
    if actual != set(offsets) - {"COMMAND"}:
        raise ValueError("Tiny PPALite read decode coverage changed")
    writes = text.split("if (apb4.pwrite) begin", 1)[1].split("endcase", 1)[0]
    writable = set(re.findall(r"`APB4_PPALITE__(\w+)\s*:", writes))
    if writable != {r["name"] for r in spec if r["access"] in {"RW", "RW1C", "WO"}}:
        raise ValueError("Tiny PPALite write decode coverage changed")
    rows = []
    for row in spec:
        for binding in row["bindings"]:
            require_snippets(root, binding["file"], [binding["text"]])
        fields = field_rows([tuple(f) for f in row["fields"]])
        reset = row["reset"]
        if row["name"] == "CAPABILITY":
            reset = hex(fact["ppalite"]["CapabilityValue"])
        try:
            value = registers.number(reset)
        except ValueError:
            value = None
        for field in fields:
            field["reset"] = (hex((value >> field["lsb"]) & ((1 << (field["msb"] - field["lsb"] + 1)) - 1))
                              if value is not None else "0" if field["name"] == "Reserved" else reset)
        rows.append(dict(key="main." + row["name"], name=row["name"], symbol="APB4_PPALITE__" + row["name"],
                         offset=row["offset"], group="main", width=32, access=row["access"], reset=reset,
                         description=row["description"], fields=fields, source=sv,
                         line=definitions[:definitions.index("`define APB4_PPALITE__" + row["name"] + " ")].count("\n") + 1,
                         c_source=header, review=None, readback=["Reviewed PPALite read decode / write-command contract"]))
    sources = {sv, rtl, header, "crt/include/retrosoc/hal/ppalite.h", "crt/src/hal/ppalite.c",
               "crt/src/hal/ppalite_math.c"}
    sources.update(b["file"] for r in spec for b in r["bindings"])
    return dict(id="ppalite", groups=[dict(id="main", title="PPALite capture and result registers", base=0, stride=0, count=1)],
                registers=rows, document="docs/ip/ppalite.md", sources=sorted(sources))


def apply_integration(reference: dict, fact: dict, root: Path) -> None:
    """Qualify live inputs and protect instance parameters from library defaults."""
    from publications.tiny_reference import require_snippets

    require_snippets(root, "rtl/ip/peripheral/gpio_pad_caps_pkg.sv", ["localparam bit HasInputCmos", "localparam bit HasPullUp"])
    for family, key in [("spi", "main.CLOCK_HZ"), ("uart", "main.CLOCK_HZ"),
                        ("i2c", "main.CLOCK_HZ"), ("ws2812", "main.CLOCK_HZ")]:
        for register in reference[family]["registers"]:
            if register["key"] != key:
                continue
            register.pop("rtl_reset", None)
            register["reset"] = "Dynamic (SAFE24: 24000000)"
            register["description"] = "Current peripheral clock rate in Hz; SAFE24 starts at 24000000. Read again after an RCU profile change."
            for field in register["fields"]:
                field["reset"] = "0" if field["name"] == "Reserved" else "Dynamic"
    dma = {r["name"]: r for r in reference["dma"]["registers"]}
    for key, value in [("IP_VERSION", fact["dma"]["IpVersion"]), ("SUPPORTED_REQUESTS", fact["dma"]["SupportedRequests"])]:
        if registers.number(dma[key]["reset"]) != value:
            raise ValueError("Tiny DMA discovery does not match selected integration")
    if reference["dma"]["groups"][1]["count"] != 8:
        raise ValueError("Tiny DMA channel coverage changed")


def validate_catalog(catalog: list, reference: dict, regions: list, topology: dict) -> list:
    """One owner per IRQ/region; one definition per expanded absolute address."""
    irq = [irq for row in catalog for irq in row["irqs"]]
    if len(irq) != len(set(irq)) or set(irq) != {r["name"] for r in topology["interrupts"]}:
        raise ValueError("Tiny interrupt catalog coverage changed")
    if any(r["id"] in {"uart1", "i2c1", "piolite"} for r in catalog):
        raise ValueError("Tiny catalog advertises an absent peripheral")
    addresses, rows = set(), []
    windows = {r["symbol"]: r for r in regions}
    for entry in catalog:
        family = entry["family"]
        bases = [r for r in entry["regions"] if r.startswith("APB4_")]
        if family == "rcu":
            if entry["regions"] or entry.get("register_region") != "APB4_SYSCTRL":
                raise ValueError("Tiny RCU must be a SYSCTRL subregion")
            bases = [entry["register_region"]]
        for symbol in bases:
            for group in reference[family]["groups"]:
                if family == "gpio" and not (group["id"] == "common" or
                   (group["id"] == "user" and symbol == "APB4_GPIO") or
                   (group["id"] == "admin" and symbol == "APB4_GPIO_ADMIN")):
                    continue
                for index in range(group["count"]):
                    for register in reference[family]["registers"]:
                        if register["group"] != group["id"]:
                            continue
                        offset = group["base"] + index * group["stride"] + register["offset"]
                        address = windows[symbol]["base"] + offset
                        if address in addresses or offset >= windows[symbol]["size"]:
                            raise ValueError("Tiny duplicate or out-of-window register address")
                        addresses.add(address)
                        rows.append(dict(ip=entry["id"], family=family, region=symbol, address=f"0x{address:08X}",
                                         key=register["key"], name=register["name"], access=register["access"],
                                         index=str(index) if group["count"] > 1 else "-"))
    return rows


def package_rows(root: Path) -> list:
    """Read the approved target table, separately from the executable pad map."""
    text = (root / "docs/ip/tiny-soc.md").read_text(encoding="utf-8")
    table = text.split("### Perimeter pin assignment", 1)[1].split("Boot Flash occupies", 1)[0]
    rows = [[int(a), b.strip(), int(c), d.strip()] for a, b, c, d in
            re.findall(r"^\| (\d+) \| ([^|]+) \| (\d+) \| ([^|]+) \|$", table, re.M)]
    if sorted(n for r in rows for n in (r[0], r[2])) != list(range(1, 65)):
        raise ValueError("Tiny approved QFN64 perimeter table changed")
    return rows
