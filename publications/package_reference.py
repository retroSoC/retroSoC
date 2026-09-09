"""Version-qualified publication packages and their offline runtime import closure."""
from __future__ import annotations

import json
import re
from pathlib import Path

from scripts.setup_helpers import sha256

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10 uses the repository's pinned backport.
    import tomli as tomllib

ARCHIVES = (
    "typst_cetz", "typst_oxifmt", "typst_wavy", "typst_jogs",
    "typst_bytefield", "typst_rivet", "typst_blockcell", "typst_circuiteria",
    "typst_cetz_0_3_4", "typst_tidy", "typst_oxifmt_0_2_1",
)


def package_records(lock: dict) -> list[dict]:
    records, seen = [], set()
    for archive in ARCHIVES:
        spec = lock["archives"][archive]
        name = spec.get("package_name", archive.removeprefix("typst_"))
        version = spec["version"]
        if not re.fullmatch(r"[a-z][a-z0-9-]*", name) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError("invalid publication package name/version")
        identity = f"{name}:{version}"
        if identity in seen:
            raise ValueError("duplicate publication package name/version")
        destination = f".cache/retrosoc/publications/packages/preview/{name}/{version}"
        if spec["destination"] != destination:
            raise ValueError("publication package cache path differs from its name/version")
        seen.add(identity)
        records.append({**spec, "name": name, "identity": identity, "archive_key": archive})
    return records


def directory_hashes(directory: Path) -> dict[str, str]:
    return {p.relative_to(directory).as_posix(): sha256(p) for p in sorted(directory.rglob("*"))
            if p.is_file() and p.name != ".manifest.json"}


def checked_package(root: Path, record: dict) -> Path:
    directory = root / record["destination"]
    marker = directory / ".manifest.json"
    if not marker.is_file() or json.loads(marker.read_text(encoding="utf-8")) != {
        "archive": record["sha256"], "files": directory_hashes(directory),
    }:
        raise ValueError(f"package {record['identity']} missing or modified; run setup")
    meta = tomllib.loads((directory / "typst.toml").read_text(encoding="utf-8"))["package"]
    if (meta["name"], meta["version"]) != (record["name"], record["version"]):
        raise ValueError("cached package identity does not match its locked archive")
    return directory


def runtime_imports(directory: Path) -> set[str]:
    meta = tomllib.loads((directory / "typst.toml").read_text(encoding="utf-8"))["package"]
    pending, visited, imports = [directory / meta["entrypoint"]], set(), set()
    while pending:
        path = pending.pop().resolve()
        if path in visited:
            continue
        if not path.is_relative_to(directory.resolve()) or not path.is_file():
            raise ValueError("package runtime import is missing or escapes its package")
        visited.add(path)
        text = path.read_text(encoding="utf-8")
        # Anchoring excludes commented documentation examples. Walk only files
        # reached from the library entrypoint, never standalone manual sources.
        for ref in re.findall(r'^\s*#(?:import|include)\s+"([^"\n]+)"', text, re.M):
            if ref.startswith("@preview/"):
                imports.add(ref.removeprefix("@preview/"))
            elif ref.startswith("@"):
                raise ValueError("unreviewed package import namespace")
            else:
                pending.append(directory / ref.lstrip("/") if ref.startswith("/") else path.parent / ref)
    return imports


def validate_imports(text: str, records: list[dict]) -> None:
    allowed = {record["identity"] for record in records}
    for name, version in re.findall(r"@preview/([\w-]+):([0-9.]+)", text):
        if f"{name}:{version}" not in allowed:
            raise ValueError(f"unlocked Typst import: {name}:{version}")


def validate_package_closure(root: Path, records: list[dict]) -> dict[str, list[str]]:
    allowed = {record["identity"] for record in records}
    graph = {}
    for record in records:
        imports = runtime_imports(checked_package(root, record))
        if imports - allowed:
            raise ValueError(f"unlocked runtime package imports: {sorted(imports - allowed)}")
        graph[record["identity"]] = sorted(imports)
    return graph
