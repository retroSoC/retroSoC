#!/usr/bin/env python3
"""Emit the Mini HP OpenC906 filelist from the locked vendored source.

The OpenC906 repository ships pre-generated Verilog below
``C906_RTL_FACTORY/gen_rtl`` together with upstream filelists that use a
``${CODE_BASE_PATH}`` placeholder and mix compilation-unit macro headers with
sources. This script resolves the placeholder to the locked checkout and
substitutes the reviewed retroSoC overrides from ``rtl/mini/ip_overrides/``
for their vendored counterparts:

- ``aq_sysio_kid.v``: upstream hardwires mhartid to 0; the Mini LP/HP
  contract requires the HP core to report hart 1.
- ``sysmap.h``: the upstream default region table marks the Mini peripheral
  window cacheable/bufferable; the override maps the Mini address map with
  the MMIO window (including the core-internal CLINT/PLIC window) as
  strong-order non-cacheable, as the OpenC906 user manual requires.

All sources are concatenated into a single compilation unit
(``openc906_combined.v``) because gen_rtl relies on header macros being
visible in every source; one file preserves that semantics for tools with
per-file compilation units (slang/Yosys) and is equivalent for
Verilator/Icarus/VCS. The vendored checkout itself is never modified.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


GENERATED_MODULE = "openC906"
UPSTREAM_FILELISTS = (
    "C906_RTL_FACTORY/gen_rtl/filelists/C906_asic_rtl.fl",
    "C906_RTL_FACTORY/gen_rtl/filelists/tdt_dmi_top_rtl.fl",
)
# vendored relpath -> (override relpath below rtl/mini/ip_overrides/, sha256 of
# the vendored file at the locked revision). The sha256 pins force a review of
# the override whenever the locked OpenC906 revision moves.
OVERRIDE_DIR = Path("rtl/mini/ip_overrides")
OVERRIDES = {
    "C906_RTL_FACTORY/gen_rtl/cpu/rtl/aq_sysio_kid.v": (
        "aq_sysio_kid.v",
        "afb4d8da4c9fb01edf9286c69111c9799ccf0cc66c339dadad1705efdd35dd8c",
    ),
    "C906_RTL_FACTORY/gen_rtl/mmu/rtl/sysmap.h": (
        "sysmap.h",
        "0389089a42ef762768e57bbb4fdcbe6b95f33ab650b5bacc0de8122e0d8711d5",
    ),
}


def run(command: list[str], cwd: Path) -> str:
    result = subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def locked_revision(lock_path: Path) -> str:
    document: dict[str, Any] = json.loads(lock_path.read_text(encoding="utf-8"))
    source = document.get("sources", {}).get("openc906")
    if not isinstance(source, dict) or not isinstance(source.get("revision"), str):
        raise ValueError("dependency lock has no openc906 source revision")
    return source["revision"]


def validate_locked_source(source: Path, expected: str) -> str:
    actual = run(["git", "rev-parse", "HEAD"], source)
    if actual != expected:
        raise ValueError(f"OpenC906 revision mismatch: expected {expected}, found {actual}")
    status = run(["git", "status", "--short"], source)
    if status:
        raise ValueError("OpenC906 source has local changes:\n" + status)
    return actual


def collect_sources(root: Path, source: Path) -> tuple[list[Path], dict[str, str]]:
    """Resolve upstream filelists to absolute source paths with overrides."""
    files: list[Path] = []
    used: dict[str, str] = {}
    for filelist in UPSTREAM_FILELISTS:
        for line in (source / filelist).read_text(encoding="utf-8").splitlines():
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            resolved = Path(entry.replace("${CODE_BASE_PATH}", str(source / "C906_RTL_FACTORY")))
            if not resolved.is_file():
                raise FileNotFoundError(f"upstream filelist entry not found: {resolved}")
            if resolved.suffix != ".h" and resolved.suffix != ".v":
                raise ValueError(f"unexpected upstream filelist entry kind: {resolved}")
            relative = resolved.relative_to(source).as_posix()
            if relative in OVERRIDES:
                override_name, expected_sha256 = OVERRIDES[relative]
                if sha256(resolved) != expected_sha256:
                    raise ValueError(
                        f"vendored {Path(relative).name} digest changed; re-review the "
                        "override before updating OVERRIDES"
                    )
                resolved = (root / OVERRIDE_DIR / override_name).resolve()
                if not resolved.is_file():
                    raise FileNotFoundError(f"override not found: {resolved}")
                used[relative] = override_name
            files.append(resolved)
    missing = set(OVERRIDES) - set(used)
    if missing:
        raise ValueError(f"override target(s) not present in upstream filelists: {missing}")
    return files, used


def generate(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    source = args.source.resolve()
    output = args.output.resolve()
    expected = locked_revision(args.lock.resolve())
    actual = validate_locked_source(source, expected)

    files, used = collect_sources(root, source)
    output.mkdir(parents=True, exist_ok=True)

    combined = output / "openc906_combined.v"
    chunks = [
        "// retroSoC build-time concatenation of the locked OpenC906 RTL.\n",
        "// Do not edit; regenerate with `make openc906-prepare`.\n",
    ]
    for path in files:
        chunks.append(f"\n// ---- begin: {path.name} ----\n")
        chunks.append(path.read_text(encoding="utf-8"))
        chunks.append("\n")
    combined.write_text("".join(chunks), encoding="utf-8")
    (output / "openc906.fl").write_text(str(combined) + "\n", encoding="utf-8")

    manifest = {
        "schema_version": 1,
        "module": GENERATED_MODULE,
        "configuration": "openc906_default_rv64gc",
        "openc906_revision": actual,
        "source_status": [],
        "overrides": {
            target: {
                "override": str(OVERRIDE_DIR / override_name),
                "expected_upstream_sha256": OVERRIDES[target][1],
            }
            for target, override_name in sorted(used.items())
        },
        "file_count": len(files),
    }
    args.manifest.resolve().parent.mkdir(parents=True, exist_ok=True)
    args.manifest.resolve().write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    generate(parser.parse_args())


if __name__ == "__main__":
    main()
