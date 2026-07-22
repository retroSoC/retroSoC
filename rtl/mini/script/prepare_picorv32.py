#!/usr/bin/env python3

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


def main() -> int:
    picorv32_dir = ROOT / "rtl/managed/picorv32/rtl"
    source = picorv32_dir / "picorv32.v"
    destination = picorv32_dir / "picorv32_ver.v"
    content = source.read_text(encoding="utf-8")
    content = content.replace("// synopsys full_case parallel_case", "")
    content = content.replace("// synopsys parallel_case", "")
    changed = atomic_write(destination, content)
    print(f"{'updated' if changed else 'unchanged'}: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
