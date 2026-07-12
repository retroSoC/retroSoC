#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


DEFAULT_SUCCESS = "retroSoC: A Customized ASIC for Retro Stuff"
DEFAULT_FAILURE = re.compile(
    r"(?:\bFAILED?\b|\bFATAL\b|assertion failed|%Error)", re.IGNORECASE
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a retroSoC simulation log")
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--require", action="append", default=[])
    parser.add_argument("--reject", action="append", default=[])
    args = parser.parse_args()

    if not args.log.is_file():
        raise SystemExit(f"simulation log not found: {args.log}")
    content = args.log.read_text(encoding="utf-8", errors="replace")
    required = args.require or [DEFAULT_SUCCESS]
    missing = [marker for marker in required if marker not in content]
    rejected = [pattern for pattern in args.reject if re.search(pattern, content)]
    default_failure = DEFAULT_FAILURE.search(content)
    if default_failure:
        rejected.append(default_failure.group(0))

    passed = not missing and not rejected
    report = {
        "schema_version": 1,
        "status": "passed" if passed else "failed",
        "log": str(args.log.resolve()),
        "required_markers": required,
        "missing_markers": missing,
        "rejected_matches": sorted(set(rejected)),
    }
    atomic_write(args.result, json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"simulation check: {report['status']} ({args.result.resolve()})")
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
