"""Materialize immutable, locally available publication test inputs.

This is a test fixture, never a publication promotion or a current-RTL verdict.
Each exported tree keeps its own adapter, technical contract, tests and lock.
"""
from __future__ import annotations

import io
import json
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_BOOK = "2805ea91833a6bede32f3a82df3d17d20eb5ec77"
P5_CONTRACT = "b3b30a72cd6ef5340c28e5044c96cd13258ec5a6"


def export(repository: Path, revision: str, destination: Path, paths: list[str] = ()) -> None:
    data = subprocess.check_output(["git", "-C", str(repository), "archive", revision, *paths])
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination.resolve()) or member.issym() or member.islnk():
                raise ValueError("unsafe publication fixture archive member")
        archive.extractall(destination)


def snapshot(destination: Path, revision: str) -> Path:
    export(ROOT, revision, destination, ["publications", "scripts", "rtl", "crt", "app",
                                       "configs", "docs", "dependencies", "LICENSE",
                                       "Makefile", "README.md", "tests"])
    lock = json.loads((destination / "dependencies/dependencies.lock.json").read_text())
    for name in ("cluster_common", "cluster_archinfo", "cluster_pwm", "cluster_rtc",
                 "cluster_wdg", "hazard3"):
        source = lock["sources"][name]
        export(ROOT / source["destination"], source["revision"], destination / source["destination"],
               ["hdl"] if name == "hazard3" else [])
    return destination
