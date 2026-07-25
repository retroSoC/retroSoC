#!/usr/bin/env python3
"""Adapt Yosys' legacy Bitwuzla invocation to the Bitwuzla 0.9 CLI."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def translate_arguments(arguments: list[str]) -> list[str]:
    """Replace obsolete Yosys solver flags with Bitwuzla 0.9 equivalents."""
    translated = [argument for argument in arguments if argument not in ("--smt2", "-i")]
    return ["--lang", "smt2", *translated]


def main() -> int:
    executable = os.environ.get("RETROSOC_BITWUZLA")
    if not executable:
        print("RETROSOC_BITWUZLA must name the Bitwuzla 0.9 executable", file=sys.stderr)
        return 2
    wrapper = Path(__file__).resolve()
    if Path(executable).resolve() == wrapper:
        print(
            "RETROSOC_BITWUZLA must name the Bitwuzla executable, not its compatibility wrapper",
            file=sys.stderr,
        )
        return 2
    os.execvp(executable, [executable, *translate_arguments(sys.argv[1:])])
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
