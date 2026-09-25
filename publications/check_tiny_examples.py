"""Compile Tiny publication examples with Tiny-generated SDK metadata only."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.generate_tiny import generate_bindings, read_topology  # noqa: E402
from scripts.rtl.generate_memory_map import generate  # noqa: E402


def check_examples(compiler: str) -> int:
    with tempfile.TemporaryDirectory(prefix="retrosoc-tiny-examples-") as location:
        generated = Path(location)
        generate_bindings(read_topology(ROOT / "rtl/tiny/integration/soc_topology.json", ROOT / "rtl/tiny/address_map/memory_map.json"), generated)
        generate(ROOT / "rtl/tiny/address_map/memory_map.json", generated / "memory_map", "YES", 128)
        includes = [ROOT / "crt/include", generated / "include", generated / "memory_map/include"]
        includes += [ROOT / f"rtl/managed/clusterip/{name}/sw/include" for name in ("archinfo", "pwm", "rtc", "wdg")]
        command = [compiler, "-std=c11", "-ffreestanding", "-Wall", "-Wextra", "-Werror", "-fsyntax-only", "-DRS_SOC_TINY=1"]
        for path in includes:
            command += ["-I", str(path)]
        examples = sorted((ROOT / "publications/examples/tiny").glob("*.c"))
        if len(examples) != 13:
            raise ValueError("Tiny example inventory changed; review the complete set")
        for path in examples:
            subprocess.run([*command, str(path)], check=True, cwd=ROOT)
        print(f"Tiny SDK examples: {len(examples)} syntax checks passed")
        return len(examples)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default="gcc")
    check_examples(parser.parse_args().cc)
