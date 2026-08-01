#!/usr/bin/env python3
"""Prepare the ICS55 H7CR functional standard-cell model for simulation."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write, sha256  # noqa: E402


EXPECTED_MUXI2_CELLS = {
    "MUXI2X0P5H7R",
    "MUXI2X0P7H7R",
    "MUXI2X1H7R",
    "MUXI2X1P4H7R",
    "MUXI2X2H7R",
    "MUXI2X3H7R",
    "MUXI2X4H7R",
}
BROKEN_IMPLEMENTATION = "  udp_mux2 u0(Y, A, B, S0);\n  not      u1(Y, Y);"
FIXED_IMPLEMENTATION = (
    "  wire muxi2_y;\n\n"
    "  udp_mux2 u0(muxi2_y, A, B, S0);\n"
    "  not      u1(Y, muxi2_y);"
)
MUXI2_MODULE = re.compile(
    r"(?P<header>\bmodule\s+(?P<name>MUXI2X[A-Za-z0-9]+H7R)"
    r"\s*\(Y,\s*A,\s*B,\s*S0\);)"
    r"(?P<body>.*?)"
    r"(?P<footer>\bendmodule\s*//\s*(?P=name))",
    re.DOTALL,
)


def patch_muxi2_models(content: str) -> tuple[str, tuple[str, ...]]:
    """Replace the self-referential MUXI2 model with an intermediate-net form."""

    cells: list[str] = []

    def patch(match: re.Match[str]) -> str:
        name = match["name"]
        body = match["body"]
        broken_count = body.count(BROKEN_IMPLEMENTATION)
        fixed_count = body.count(FIXED_IMPLEMENTATION)
        if broken_count == 1 and fixed_count == 0:
            body = body.replace(BROKEN_IMPLEMENTATION, FIXED_IMPLEMENTATION)
        elif broken_count != 0 or fixed_count != 1:
            raise ValueError(f"unexpected {name} functional implementation")
        cells.append(name)
        return f"{match['header']}{body}{match['footer']}"

    patched = MUXI2_MODULE.sub(patch, content)
    found = set(cells)
    if found != EXPECTED_MUXI2_CELLS:
        missing = ", ".join(sorted(EXPECTED_MUXI2_CELLS - found))
        unexpected = ", ".join(sorted(found - EXPECTED_MUXI2_CELLS))
        details = []
        if missing:
            details.append(f"missing {missing}")
        if unexpected:
            details.append(f"unexpected {unexpected}")
        raise ValueError("unexpected ICS55 H7CR MUXI2 cell set: " + "; ".join(details))
    return patched, tuple(sorted(cells))


def prepare(source: Path, output: Path, revision: str) -> None:
    source = source.resolve()
    if not source.is_file():
        raise FileNotFoundError(f"ICS55 H7CR Verilog model not found: {source}")

    patched, cells = patch_muxi2_models(source.read_text(encoding="utf-8"))
    output = output.resolve()
    metadata = f"{revision}\n{sha256(source)}\n{','.join(cells)}\n"
    changed = atomic_write(output, patched)
    atomic_write(output.with_suffix(output.suffix + ".revision"), metadata)
    state = "prepared" if changed else "ready"
    print(f"ICS55 H7CR functional model {state}: {output}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch the locked ICS55 H7CR MUXI2 functional models in the cache"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    prepare(args.source, args.output, args.revision)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
