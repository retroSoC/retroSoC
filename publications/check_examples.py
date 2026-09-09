"""Syntax-check publication examples against the current SDK and managed headers."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from publications.build_datasheet import profile_values  # noqa: E402


def check_examples(compiler: str) -> int:
    config = json.loads((ROOT / "publications/datasheets/mini.json").read_text())
    profile = profile_values(ROOT / config["profile"])
    generated = ROOT / "build/datasheet-example-check/generated"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map",
            str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir",
            str(generated),
            "--have-sram-if",
            profile["HAVE_SRAM_IF"],
            "--sram-size-kib",
            profile["SRAM_SIZE_KIB"],
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/integration/generate_user_extensions.py"),
            "--map",
            str(ROOT / "rtl/mini/integration/user_extensions.json"),
            "--output-dir",
            str(generated),
        ],
        check=True,
    )
    includes = [ROOT / "crt/include", generated / "include"]
    includes += sorted((ROOT / "rtl/managed/clusterip").glob("*/sw/include"))
    command = [
        compiler,
        "-std=c11",
        "-ffreestanding",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fsyntax-only",
    ]
    for include in includes:
        command += ["-I", str(include)]
    examples = sorted((ROOT / "publications/examples").glob("*.c"))
    for example in examples:
        subprocess.run([*command, str(example)], cwd=ROOT, check=True)
    print(f"SDK examples: {len(examples)} syntax checks passed")
    return len(examples)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    check_examples(args.cc)
