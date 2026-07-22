#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
MINI_DIR = SCRIPT_DIR.parent
ROOT_DIR = MINI_DIR.parent.parent
DEFAULT_MODELS = ROOT_DIR / "rtl" / "managed" / "third_party" / "norflash"
DEFAULT_FIRMWARE = ROOT_DIR / ".sw_build" / "retrosoc_fw.hex"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare NOR Flash simulation files")
    parser.add_argument("--sim-dir", type=Path, required=True)
    parser.add_argument("--models-dir", type=Path, default=DEFAULT_MODELS)
    parser.add_argument("--firmware", type=Path, default=DEFAULT_FIRMWARE)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sim_dir = args.sim_dir.resolve()
    models_dir = args.models_dir.resolve()
    firmware = args.firmware.resolve()
    sim_dir.mkdir(parents=True, exist_ok=True)

    model_names = ("SECSI.TXT", "SFDP.TXT", "SREG.TXT")
    missing_models = [name for name in model_names if not (models_dir / name).is_file()]
    if missing_models:
        raise FileNotFoundError(
            f"NOR Flash model files missing in {models_dir}: {', '.join(missing_models)}"
        )
    if not firmware.is_file():
        raise FileNotFoundError(
            f"firmware image not found: {firmware}; run 'make firmware' first"
        )

    for name in model_names:
        shutil.copy2(models_dir / name, sim_dir / name)

    memory = sim_dir / "MEM.TXT"
    if memory.is_symlink() or memory.exists():
        memory.unlink()
    memory.symlink_to(firmware)
    print(f"prepared NOR Flash files in {sim_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
