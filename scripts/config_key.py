#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, lock_digest, load_lock  # noqa: E402


def slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized or "manual"


def variant_id(profile: str, values: list[str], lock: Path) -> str:
    parsed: dict[str, str] = {}
    for item in values:
        name, separator, value = item.partition("=")
        if not separator or not name or name in parsed:
            raise ValueError(f"invalid or duplicate configuration value: {item}")
        parsed[name] = value
    payload = {
        "schema_version": 1,
        "configuration": dict(sorted(parsed.items())),
        "dependency_lock_sha256": lock_digest(lock),
    }
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:12]
    return f"{slug(profile)}-{digest}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a deterministic build variant ID")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--profile", default="manual")
    parser.add_argument("--value", action="append", default=[])
    args = parser.parse_args()
    load_lock(args.lock)
    try:
        print(variant_id(args.profile, args.value, args.lock))
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
