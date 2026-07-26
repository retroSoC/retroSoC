#!/usr/bin/env python3
"""Collect formal flow result records into one variant-level verdict."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from scripts.setup_helpers import atomic_write  # noqa: E402


STEPS = ("sv2v", "prove", "cover")


def read_result(path: Path) -> dict[str, object]:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read formal result {path}: {error}") from error
    if result.get("status") != "passed":
        raise RuntimeError(f"formal step did not pass: {path}")
    return result


def read_sby_status(path: Path) -> str:
    try:
        fields = path.read_text(encoding="utf-8").split()
    except OSError as error:
        raise RuntimeError(f"cannot read SymbiYosys status {path}: {error}") from error
    status = fields[0] if fields else ""
    if status != "PASS":
        raise RuntimeError(f"SymbiYosys task did not pass: {path} ({status or 'missing'})")
    return status


def parse_proof(value: str) -> tuple[str, Path]:
    name, separator, directory = value.partition("=")
    if not separator or not name or not directory:
        raise argparse.ArgumentTypeError("proof must use NAME=DIRECTORY")
    return name, Path(directory)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--proof", type=parse_proof, action="append", required=True)
    args = parser.parse_args()

    proofs: dict[str, dict[str, object]] = {}
    for name, directory in args.proof:
        resolved = directory.resolve()
        proof: dict[str, object] = {"sv2v": read_result(resolved / "result-sv2v.json")}
        for step in ("prove", "cover"):
            proof[step] = {
                "result": read_result(resolved / f"result-{step}.json"),
                "sby_status": read_sby_status(resolved / step / "status"),
            }
        proofs[name] = proof
    atomic_write(
        args.output.resolve(),
        json.dumps(
            {"schema_version": 2, "status": "passed", "proofs": proofs}, indent=2, sort_keys=True
        )
        + "\n",
    )
    print(f"formal results: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
