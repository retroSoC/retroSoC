#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from pathlib import Path

from filelist import atomic_write


SCRIPT_DIR = Path(__file__).resolve().parent
MINI_DIR = SCRIPT_DIR.parent
RTL_DIR = MINI_DIR.parent
ROOT_DIR = RTL_DIR.parent
DEFAULT_OUTPUT_DIR = MINI_DIR / ".generated_fl"

PATH_PREFIXES = {
    "cache": ROOT_DIR / ".cache",
    "pdk": ROOT_DIR / "pdk",
    "clusterip": RTL_DIR / "managed" / "clusterip",
    "ip": RTL_DIR / "ip",
    "third_party": RTL_DIR / "managed" / "third_party",
    "tech": RTL_DIR / "tech",
    "core": MINI_DIR / "core",
    "hazard3": RTL_DIR / "managed" / "hazard3" / "hdl",
    "mpw": RTL_DIR / "managed" / "mpw",
    "tb": MINI_DIR / "dv" / "tb",
    "model": MINI_DIR / "dv" / "model",
    "sva": MINI_DIR / "dv" / "sva",
    "top": MINI_DIR / "top",
}


def expand_filelist(content: str) -> str:
    output: list[str] = []
    for line in content.splitlines():
        expanded = line
        for prefix, directory in PATH_PREFIXES.items():
            expanded = re.sub(
                rf"(?<![^\s+])/{re.escape(prefix)}(?=/|\s|$)",
                str(directory),
                expanded,
            )
        output.append(expanded)
    return "\n".join(output) + "\n"


def expand_lint_config(content: str) -> str:
    expanded = content
    for prefix, directory in PATH_PREFIXES.items():
        expanded = expanded.replace(f",/{prefix}", f",{directory}")
        expanded = expanded.replace(f"=/{prefix}", f"={directory}")
    return expanded


def generate_all(output_dir: Path, defines: list[str]) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []

    templates = sorted((RTL_DIR / "filelist").glob("pdk_*.fl"))
    templates.extend(
        MINI_DIR / "filelist" / name
        for name in (
            "clusterip.fl",
            "commonip.fl",
            "core_hazard3.fl",
            "inc.fl",
            "ip.fl",
            "sys_def.fl",
            "tb.fl",
            "tech.fl",
            "top.fl",
        )
    )
    for source in templates:
        if not source.is_file():
            raise FileNotFoundError(f"canonical filelist not found: {source}")
        destination = output_dir / source.name
        atomic_write(
            destination,
            expand_filelist(source.read_text(encoding="utf-8")),
        )
        generated.append(destination)

    lint_source = MINI_DIR / "lint.msg"
    lint_destination = output_dir / lint_source.name
    atomic_write(
        lint_destination,
        expand_lint_config(lint_source.read_text(encoding="utf-8")),
    )
    generated.append(lint_destination)

    def_file = output_dir / "def.fl"
    atomic_write(def_file, " ".join(defines) + "\n")
    generated.append(def_file)
    return generated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate absolute RTL filelists")
    parser.add_argument(
        "--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="output directory"
    )
    parser.add_argument("--define", action="append", default=[], help="filelist +define+ token")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    invalid = [item for item in args.define if not item.startswith("+define+")]
    if invalid:
        raise SystemExit(f"invalid define token(s): {' '.join(invalid)}")
    generated = generate_all(args.output_dir.resolve(), args.define)
    print(f"generated {len(generated)} files in {args.output_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
