#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "dependencies/dependencies.lock.json"
DEFAULT_FLAKE_LOCK = ROOT / "flake.lock"
NIX_SRI_HASH = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")
OCI_DIGEST = re.compile(r"sha256:[0-9a-f]{64}")


class LockError(ValueError):
    pass


def load_lock(path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    path = path.resolve()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise LockError(f"cannot read dependency lock {path}: {error}") from error
    validate_lock(data)
    return data


def validate_lock(data: dict[str, Any]) -> None:
    if data.get("schema_version") != 1:
        raise LockError("dependency lock schema_version must be 1")
    for section in ("sources", "archives", "container_images", "nix_inputs", "toolchains"):
        if not isinstance(data.get(section), dict) or not data[section]:
            raise LockError(f"dependency lock section is missing or empty: {section}")
    for name, source in data["sources"].items():
        _require_fields("source", name, source, ("url", "revision", "destination", "license"))
        if not re.fullmatch(r"[0-9a-f]{40}", source["revision"]):
            raise LockError(f"source {name} revision must be a full 40-character commit")
        _validate_url(f"source {name}", source["url"])
        _validate_relative_path(f"source {name} destination", source["destination"])
        _validate_source_submodules(name, source)
    for name, archive in data["archives"].items():
        _validate_archive("archive", name, archive)
    for name, image in data["container_images"].items():
        _require_fields("container image", name, image, ("image", "digest", "url", "license"))
        if not re.fullmatch(r"[a-z0-9]+(?:[._/-][a-z0-9]+)*", image["image"]):
            raise LockError(f"container image {name} has an invalid image name")
        if OCI_DIGEST.fullmatch(image["digest"]) is None:
            raise LockError(f"container image {name} digest must be a SHA-256 OCI digest")
        _validate_url(f"container image {name}", image["url"])
    for name, nix_input in data["nix_inputs"].items():
        _require_fields("nix input", name, nix_input, ("url", "revision", "nar_hash", "license"))
        if not re.fullmatch(r"[0-9a-f]{40}", nix_input["revision"]):
            raise LockError(f"nix input {name} revision must be a full 40-character commit")
        _validate_url(f"nix input {name}", nix_input["url"])
        if NIX_SRI_HASH.fullmatch(nix_input["nar_hash"]) is None:
            raise LockError(f"nix input {name} nar_hash must be a SHA-256 SRI hash")
    for platform, tools in data["toolchains"].items():
        if not isinstance(tools, dict) or not tools:
            raise LockError(f"toolchain platform is empty: {platform}")
        for name, tool in tools.items():
            _require_fields("toolchain", name, tool, ("version", "url", "sha256", "archive", "path"))
            _validate_sha(f"toolchain {platform}/{name}", tool["sha256"])
            _validate_url(f"toolchain {platform}/{name}", tool["url"])
            _validate_relative_path(f"toolchain {platform}/{name} archive", tool["archive"])
            _validate_relative_path(f"toolchain {platform}/{name} path", tool["path"])


def _validate_archive(kind: str, name: str, value: dict[str, Any]) -> None:
    _require_fields(kind, name, value, ("url", "sha256", "destination", "license"))
    _validate_sha(f"{kind} {name}", value["sha256"])
    _validate_url(f"{kind} {name}", value["url"])
    _validate_relative_path(f"{kind} {name} destination", value["destination"])


def _validate_source_submodules(name: str, value: dict[str, Any]) -> None:
    submodules = value.get("submodules")
    if submodules is None:
        return
    if value.get("recursive") is not True:
        raise LockError(f"source {name} submodules require recursive=true")
    if not isinstance(submodules, list) or not submodules:
        raise LockError(f"source {name} submodules must be a non-empty list")
    for submodule in submodules:
        if not isinstance(submodule, str):
            raise LockError(f"source {name} submodules must contain paths")
        _validate_relative_path(f"source {name} submodule", submodule)


def _require_fields(kind: str, name: str, value: Any, fields: tuple[str, ...]) -> None:
    if not isinstance(value, dict):
        raise LockError(f"{kind} {name} must be an object")
    missing = [field for field in fields if not value.get(field)]
    if missing:
        raise LockError(f"{kind} {name} missing fields: {', '.join(missing)}")


def _validate_sha(label: str, value: str) -> None:
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise LockError(f"{label} sha256 must be 64 lowercase hexadecimal characters")


def _validate_url(label: str, value: str) -> None:
    if not value.startswith("https://"):
        raise LockError(f"{label} URL must use HTTPS")


def _validate_relative_path(label: str, value: str) -> None:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise LockError(f"{label} must be a repository-relative path")


def validate_flake_lock(data: dict[str, Any], path: Path = DEFAULT_FLAKE_LOCK) -> None:
    try:
        flake = json.loads(path.read_text(encoding="utf-8"))
        nodes = flake["nodes"]
        root = nodes[flake["root"]]
    except (KeyError, OSError, json.JSONDecodeError) as error:
        raise LockError(f"cannot read flake lock {path}: {error}") from error
    if not isinstance(nodes, dict) or not isinstance(root, dict):
        raise LockError("flake lock nodes and root must be objects")

    for name, expected in data["nix_inputs"].items():
        try:
            node = nodes[root["inputs"][name]]
            locked = node["locked"]
            owner = locked["owner"]
            repository = locked["repo"]
        except (KeyError, TypeError) as error:
            raise LockError(f"flake lock is missing nix input {name}") from error
        actual_url = f"https://github.com/{owner}/{repository}"
        if actual_url != expected["url"]:
            raise LockError(f"flake lock URL mismatch for nix input {name}")
        if locked.get("rev") != expected["revision"]:
            raise LockError(f"flake lock revision mismatch for nix input {name}")
        if locked.get("narHash") != expected["nar_hash"]:
            raise LockError(f"flake lock narHash mismatch for nix input {name}")


def lock_digest(path: Path = DEFAULT_LOCK) -> str:
    return hashlib.sha256(path.resolve().read_bytes()).hexdigest()


def source(name: str, path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    data = load_lock(path)
    try:
        return data["sources"][name]
    except KeyError as error:
        raise LockError(f"unknown source dependency: {name}") from error


def archive(name: str, path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    data = load_lock(path)
    try:
        return data["archives"][name]
    except KeyError as error:
        raise LockError(f"unknown archive dependency: {name}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the retroSoC dependency lock")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--flake-lock", type=Path, default=DEFAULT_FLAKE_LOCK)
    parser.add_argument("--digest", action="store_true")
    args = parser.parse_args()
    data = load_lock(args.lock)
    validate_flake_lock(data, args.flake_lock)
    if args.digest:
        print(lock_digest(args.lock))
    else:
        print(
            f"dependency lock valid: {len(data['sources'])} sources, "
            f"{len(data['archives'])} archives, {len(data['container_images'])} container images, "
            f"{len(data['nix_inputs'])} Nix inputs"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
