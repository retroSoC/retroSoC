"""Bound the unnumbered closing-page exception to its rendered, hashed record."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

REPOSITORY_URL = "https://github.com/retroSoC/retroSoC"
CLOSING_TITLE = "Disclaimer and Copyright Notice"
PAGE_ROLES_FILE = "page-roles.json"


def validate_page_roles(roles: list[dict], page_count: int) -> set[int]:
    """Legacy PDFs have no exception; new PDFs may declare only one final page."""
    if not isinstance(roles, list):
        raise ValueError("publication page roles must be a list")
    if not roles:
        return set()
    if len(roles) != 1 or not isinstance(roles[0], dict):
        raise ValueError("publication requires a unique closing page")
    role = roles[0]
    if (set(role) != {"role", "page"} or role["role"] != "closing"
            or type(role["page"]) is not int or role["page"] != page_count
            or page_count < 2):
        raise ValueError("closing page must be the final page of the publication")
    return {role["page"]}


def collect_page_roles(items: list[dict]) -> list[dict]:
    markers = [item for item in items if isinstance(item, dict)
               and item.get("kind") in {"publication-closing-start", "publication-closing-end"}]
    if (len(markers) != 2
            or [item["kind"] for item in markers] != ["publication-closing-start", "publication-closing-end"]):
        raise ValueError("publication requires one paired closing-page marker")
    start, end = markers
    count = start.get("total_pages")
    if (type(count) is not int or end.get("total_pages") != count
            or type(end.get("page")) is not int or start.get("page") != end["page"]):
        raise ValueError("closing page markers span pages or disagree on page count")
    roles = [{"role": "closing", "page": start.get("page")}]
    validate_page_roles(roles, count)
    return roles


def read_page_roles(folder: Path, manifest: dict, page_count: int) -> list[dict]:
    path = folder / PAGE_ROLES_FILE
    expected = manifest.get("page_roles_sha256")
    if expected is None:
        if path.exists():
            raise ValueError("publication page roles are not bound to the manifest")
        return []
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError("publication page roles missing or changed; rebuild before checking")
    roles = json.loads(path.read_text(encoding="utf-8"))
    if not roles:
        raise ValueError("bound publication page roles must identify the closing page")
    validate_page_roles(roles, page_count)
    return roles


def validate_footer_pages(actual: list[int], page_count: int, roles: list[dict]) -> None:
    closing = validate_page_roles(roles, page_count)
    expected = [number for number in range(1, page_count + 1) if number not in closing]
    if actual != expected:
        raise ValueError("PDF repository footer pages do not match the declared page roles")


def validate_footer_text(text: str, number: int, closing_pages: set[int]) -> None:
    if number in closing_pages:
        if text.strip():
            raise ValueError("closing page must not have a visible footer")
    elif REPOSITORY_URL not in text:
        raise ValueError("PDF footer does not display the complete repository URL")
