#!/usr/bin/env python3
"""Classify build artifacts and retain evidence without broad cache deletion."""

from __future__ import annotations

import fnmatch
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from scripts.agent_control import read_json
from scripts.flow_control import file_digest, utc_now, write_json

RULE_FIELDS = {"name", "class", "patterns", "retain", "retention_days", "on_expiry", "rebuildable"}


def load_policy(path: Path) -> dict[str, Any]:
    policy = read_json(path)
    if policy.get("schema_version") != 1:
        raise ValueError("artifact retention policy requires schema_version=1")
    if not isinstance(policy.get("minimum_free_bytes"), int) or policy["minimum_free_bytes"] < 0:
        raise ValueError("artifact retention minimum_free_bytes must be non-negative")
    rules = policy.get("rules")
    if not isinstance(rules, list) or not rules:
        raise ValueError("artifact retention requires ordered rules")
    names = set()
    for rule in rules:
        if not isinstance(rule, dict) or set(rule) != RULE_FIELDS:
            raise ValueError("artifact retention rule fields are incomplete")
        if not isinstance(rule["name"], str) or rule["name"] in names:
            raise ValueError("artifact retention rule names must be unique")
        names.add(rule["name"])
        if not isinstance(rule["class"], str) or not rule["class"]:
            raise ValueError("artifact retention class must be non-empty")
        if not isinstance(rule["patterns"], list) or not rule["patterns"] or any(
            not isinstance(pattern, str) or not pattern for pattern in rule["patterns"]
        ):
            raise ValueError("artifact retention patterns must be non-empty")
        if not isinstance(rule["retain"], bool) or not isinstance(rule["rebuildable"], bool):
            raise ValueError("artifact retention retain/rebuildable flags must be Boolean")
        days = rule["retention_days"]
        if days is not None and (not isinstance(days, int) or isinstance(days, bool) or days <= 0):
            raise ValueError("artifact retention days must be positive or null")
        if rule["on_expiry"] not in {"review", "retain", "retain_until_gap_resolved"}:
            raise ValueError("artifact expiry must require review or retention")
    fallback = rules[-1]
    if fallback["patterns"] != ["**"] or not fallback["retain"] or fallback["retention_days"] is not None:
        raise ValueError("artifact retention must end with a permanent unclassified catch-all")
    return policy


def matches(path: str, pattern: str) -> bool:
    return fnmatch.fnmatchcase(path, pattern) or (
        pattern.startswith("**/") and fnmatch.fnmatchcase(path, pattern.removeprefix("**/"))
    )


def classify(path: str, policy: dict[str, Any]) -> dict[str, Any]:
    for rule in policy["rules"]:
        if any(matches(path, pattern) for pattern in rule["patterns"]):
            return rule
    raise ValueError(f"artifact retention has no catch-all for {path}")


def inventory(source: Path, policy: dict[str, Any]) -> dict[str, Any]:
    if source.is_symlink() or not source.is_dir():
        raise RuntimeError(f"artifact root must be a real directory: {source}")
    source = source.resolve()
    retained = []
    skipped_symlinks = []
    categories: dict[tuple[str, str, int | None, bool], dict[str, Any]] = {}
    file_count = 0
    total_bytes = 0

    def observe(rule: dict[str, Any], size: int) -> None:
        key = (rule["class"], rule["on_expiry"], rule["retention_days"], rule["rebuildable"])
        category = categories.setdefault(
            key,
            {
                "class": rule["class"],
                "on_expiry": rule["on_expiry"],
                "retention_days": rule["retention_days"],
                "rebuildable": rule["rebuildable"],
                "file_count": 0,
                "bytes": 0,
                "retained_file_count": 0,
                "retained_bytes": 0,
            },
        )
        category["file_count"] += 1
        category["bytes"] += size
        if rule["retain"]:
            category["retained_file_count"] += 1
            category["retained_bytes"] += size

    for directory, dirnames, filenames in os.walk(source, followlinks=False):
        parent = Path(directory)
        for name in [*dirnames, *filenames]:
            path = parent / name
            if not path.is_symlink():
                continue
            relative = path.relative_to(source).as_posix()
            rule = classify(relative, policy)
            if rule["retain"] or not rule["rebuildable"]:
                raise RuntimeError(f"artifact symlinks require manual review: {path}")
            size = path.lstat().st_size
            file_count += 1
            total_bytes += size
            observe(rule, size)
            skipped_symlinks.append({"path": relative, "bytes": size, "class": rule["class"]})
        for name in filenames:
            path = parent / name
            if path.is_symlink():
                continue
            if not path.is_file():
                raise RuntimeError(f"artifact is not a regular file: {path}")
            relative = path.relative_to(source).as_posix()
            rule = classify(relative, policy)
            size = path.stat().st_size
            file_count += 1
            total_bytes += size
            observe(rule, size)
            if rule["retain"]:
                retained.append(
                    {
                        "path": relative,
                        "bytes": size,
                        "sha256": file_digest(path),
                        "class": rule["class"],
                        "rule": rule["name"],
                        "retention_days": rule["retention_days"],
                        "on_expiry": rule["on_expiry"],
                        "rebuildable": rule["rebuildable"],
                    }
                )
    return {
        "file_count": file_count,
        "bytes": total_bytes,
        "retained_file_count": len(retained),
        "retained_bytes": sum(item["bytes"] for item in retained),
        "retained_files": sorted(retained, key=lambda item: item["path"]),
        "categories": sorted(categories.values(), key=lambda item: (item["class"], item["on_expiry"])),
        "skipped_symlinks": skipped_symlinks,
        "symlink_policy": "only known rebuildable classes are skipped without following their targets",
    }


def preserve(source: Path, destination: Path, policy_path: Path, identity: dict[str, Any]) -> dict[str, Any]:
    policy = load_policy(policy_path)
    document = inventory(source, policy)
    if destination.exists():
        raise RuntimeError(f"artifact destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(destination.parent).free
    required = document["retained_bytes"] + policy["minimum_free_bytes"]
    if free < required:
        raise RuntimeError(f"insufficient artifact capacity: need {required} bytes including free-space reserve")
    document.update(
        artifact_identity=identity,
        source_worktree=str(source.parent),
        source_build=str(source),
        policy_sha256=file_digest(policy_path),
    )
    staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}-", dir=destination.parent))
    try:
        for item in document["retained_files"]:
            origin = source / item["path"]
            target = staging / item["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            if file_digest(origin) != item["sha256"]:
                raise RuntimeError(f"artifact changed during preservation: {origin}")
            shutil.copy2(origin, target)
        document.update(
            schema_version=1,
            status="PRESERVED",
            created_at=utc_now(),
            destination=str(destination),
            free_bytes_before=free,
            minimum_free_bytes=policy["minimum_free_bytes"],
            expiry_deletion="not automatic; every expiry requires review or explicit retention",
        )
        document["evidence_files"] = [
            item for item in document["retained_files"] if item["class"] == "evidence"
        ]
        write_json(staging / "artifact-manifest.json", document)
        staging.replace(destination)
    except Exception:
        write_json(
            staging / "artifact-manifest.json",
            {**document, "schema_version": 1, "status": "PARTIAL", "destination": None},
        )
        raise
    return document
