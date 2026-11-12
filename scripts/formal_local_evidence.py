#!/usr/bin/env python3
"""Collect existing formal results into revision-bound local CI evidence."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import git_output, read_json  # noqa: E402


def collect(
    root: Path,
    variant: Path,
    proof: str,
    profile: str,
    pdk: str,
    since: str,
    output: Path,
) -> dict[str, Any]:
    root = root.resolve()
    variant = variant if variant.is_absolute() else root / variant
    variant = variant.resolve()
    output = output if output.is_absolute() else root / output
    output = output.resolve()
    if not variant.is_relative_to(root / "build"):
        raise ValueError("formal variant must be inside the repository build directory")
    if not output.is_relative_to(root):
        raise ValueError("formal evidence output must be inside the repository")
    if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", proof) is None:
        raise ValueError("proof must be a lowercase task name")

    manifest = read_json(variant / "meta/manifest.json")
    repository = manifest.get("repository", {})
    if repository.get("dirty") is not False:
        raise RuntimeError("local formal evidence requires a clean source worktree")
    revision = git_output(root, "rev-parse", "HEAD")
    if repository.get("commit") != revision:
        raise RuntimeError("formal manifest revision does not match the source worktree")
    expected_profile = f"configs/ci/{manifest['profile']}.mk"
    if profile != expected_profile:
        raise RuntimeError(f"formal profile must be {expected_profile}")
    if pdk != manifest.get("configuration", {}).get("PDK"):
        raise RuntimeError("formal PDK does not match the manifest")

    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/formal/formal_results.py"),
            "--output",
            str(variant / "meta/formal.json"),
            "--proof",
            f"{proof}={variant}/formal/{proof}",
        ],
        cwd=root,
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/ci_summary.py"),
            "collect",
            "--root",
            str(root),
            "--build-root",
            str(root / "build"),
            "--since",
            since,
            "--label",
            f"formal-{proof}",
            "--profile",
            profile,
            "--pdk",
            pdk,
            "--suite",
            "formal",
            "--executed-formal",
            "--require-formal",
            "--run-status",
            "success",
            "--output",
            str(output),
        ],
        cwd=root,
        check=True,
    )
    summary = read_json(output)
    if summary.get("overall_status") != "PASS":
        raise RuntimeError(f"local formal evidence did not pass: {output}")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--variant", type=Path, required=True)
    parser.add_argument("--proof", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--since", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        summary = collect(args.root, args.variant, args.proof, args.profile, args.pdk, args.since, args.output)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"local formal evidence: {error}", file=sys.stderr)
        return 2
    print(f"local formal evidence: PASS: {summary['source_revision']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
