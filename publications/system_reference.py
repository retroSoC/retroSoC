"""Validate publication-only system guidance and its evidence dependencies."""
from __future__ import annotations

import json
import re
from pathlib import Path

from publications.programming_reference import collect_programming, dependencies
from publications.implementation_reference import collect_details, dependencies as detail_dependencies

REFERENCE = "publications/datasheets/system-reference.json"


def source_paths(reference: dict) -> set[str]:
    paths = set(reference["sources"])
    paths.update(dependencies(reference.get("programming", {})))
    paths.update(detail_dependencies(reference.get("product_details", {})))
    for row in [*reference["support"], *reference["limitations"]]:
        paths.update(row["sources"])
        paths.update(row.get("tests", []))
        for report in row.get("reports", []):
            paths.update((report["path"], report["profile"]))
    return paths


def validate_reference(reference: dict, expected_ids: set[str], root: Path) -> None:
    if reference.get("schema_version") != 1:
        raise ValueError("unsupported system-reference schema")
    if not re.fullmatch(r"[0-9a-f]{40}", reference.get("source_revision", "")):
        raise ValueError("system-reference requires reviewed source revision")
    for collection in ("support", "limitations"):
        ids = [row["id"] for row in reference[collection]]
        if len(ids) != len(set(ids)):
            raise ValueError(f"duplicate system-reference {collection} identifier")
        if collection == "support" and set(ids) != expected_ids:
            raise ValueError("system-reference IP coverage mismatch")
        for row in reference[collection]:
            if not row.get("sources"):
                raise ValueError(f"missing system-reference sources: {row['id']}")
            if collection == "support":
                if row.get("implementation") not in {"Integrated", "Partial", "MPW only"}:
                    raise ValueError(f"invalid implementation status: {row['id']}")
                if row.get("verification") not in {"Source reviewed", "Tests available", "Reported pass"}:
                    raise ValueError(f"invalid verification status: {row['id']}")
                if row["verification"] == "Tests available" and not row.get("tests"):
                    raise ValueError(f"verification requires test sources: {row['id']}")
                if row["verification"] == "Reported pass" and not row.get("reports"):
                    raise ValueError(f"verification requires a report: {row['id']}")
            for report in row.get("reports", []):
                if not all(report.get(k) for k in ("path", "profile", "revision", "stage", "result")):
                    raise ValueError("report requires path, profile, revision, stage and result")
                if report["stage"] not in {"simulation", "fpga", "silicon"} or report["result"] != "pass":
                    raise ValueError("invalid report stage or result")
                if not re.fullmatch(r"[0-9a-f]{40}", report["revision"]):
                    raise ValueError("report revision must be a full commit")
                if report["revision"] != reference["source_revision"]:
                    raise ValueError("report does not cover the reviewed snapshot")
    for relative in source_paths(reference):
        path = root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"system-reference path escapes repository: {relative}")
        if not path.is_file():
            raise ValueError(f"missing system-reference source: {relative}")


def collect_system_reference(root: Path, revision: str) -> dict:
    reference = json.loads((root / REFERENCE).read_text(encoding="utf-8"))
    index = json.loads((root / "publications/datasheets/chapter-index.json").read_text(encoding="utf-8"))
    validate_reference(reference, {row["id"] for row in index}, root)
    if reference["source_revision"] != revision:
        raise ValueError("system-reference snapshot differs from document snapshot")
    header = (root / "app/apps/hp_boot/hp_boot_bundle.h").read_text(encoding="utf-8")
    layout = []
    for identifier, title in (("OPENSBI", "OpenSBI FW_JUMP"), ("DTB", "Device tree"),
                              ("LINUX", "Linux Image"), ("INITRAMFS", "initramfs")):
        values = {}
        for suffix in ("ADDRESS", "MAX_SIZE"):
            found = re.search(rf"^#define\s+RS_HP_BOOT_{identifier}_{suffix}\s+UINT32_C\((0x[0-9A-Fa-f]+)\)", header, re.M)
            if found is None:
                raise ValueError(f"missing boot layout constant: {identifier}_{suffix}")
            values[suffix] = int(found[1], 16)
        layout.append({"name": title, "address": f"0x{values['ADDRESS']:08X}",
                       "max_size_kib": values["MAX_SIZE"] // 1024})
    reference["boot_layout"] = layout
    reference["programming"] = collect_programming(root, reference["programming"], {row["id"] for row in index}, revision)
    reference["product_details"] = collect_details(root, reference["product_details"], {row["id"] for row in index}, {row["id"] for row in reference["limitations"]})
    return reference
