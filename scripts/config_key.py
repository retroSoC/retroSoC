#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, lock_digest, load_lock  # noqa: E402

TIMESTAMP_FORMAT = "%Y-%m-%d-%H-%M"
TIMESTAMP_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}")


def slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized or "manual"


def normalize_timestamp(value: str | None) -> str:
    if value is None:
        return datetime.now().astimezone().strftime(TIMESTAMP_FORMAT)
    if TIMESTAMP_RE.fullmatch(value) is None:
        raise ValueError(f"timestamp must use {TIMESTAMP_FORMAT}")
    try:
        datetime.strptime(value, TIMESTAMP_FORMAT)
    except ValueError as error:
        raise ValueError(f"timestamp must use {TIMESTAMP_FORMAT}") from error
    return value


def variant_id(
    profile: str,
    values: list[str],
    lock: Path,
    timestamp: str | None = None,
) -> str:
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
    return f"{slug(profile)}-{normalize_timestamp(timestamp)}-{digest}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a timestamped build variant ID")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--profile", default="manual")
    parser.add_argument("--value", action="append", default=[])
    parser.add_argument("--timestamp", help=f"creation time in {TIMESTAMP_FORMAT} format")
    args = parser.parse_args()
    load_lock(args.lock)
    try:
        print(variant_id(args.profile, args.value, args.lock, args.timestamp))
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
