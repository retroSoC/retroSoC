"""Validate the locked APU-P7 KWS reference inputs without network access."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

REQUIRED_SOURCES = {
    "apu_mlperf_tiny": "4addd0fa08d216e20637637874e084895f289da4",
    "apu_kws_mfcc": "cf7c2f2634608a7c0ea7458ab7cb3379f2863424",
    "apu_tfds": "8997c4140cd4fc145f0693787b1da78691930459",
    "apu_tensorflow": "fcc4b966f1265f466e82617020af93670141b009",
    "apu_gemmlowp": "fda83bdc38b118cc6b56753bd540caa49e570745",
}
REQUIRED_ARCHIVE = {
    "apu_kws_pcm": "cc2a00c1147c2254e9be3fa0f779d8c17421dc349b86366567a8edfa9acd51df"
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    sources = lock.get("sources", {})
    archives = lock.get("archives", {})
    for name, revision in REQUIRED_SOURCES.items():
        if sources.get(name, {}).get("revision") != revision:
            raise SystemExit(f"missing or stale locked source: {name}")
    for name, checksum in REQUIRED_ARCHIVE.items():
        if archives.get(name, {}).get("sha256") != checksum:
            raise SystemExit(f"missing or stale locked archive: {name}")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = args.output_dir / "provenance.json"
    manifest.write_text(
        json.dumps(
            {"sources": REQUIRED_SOURCES, "archives": REQUIRED_ARCHIVE}, indent=2, sort_keys=True
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"APU-P7 locked references validated: {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
