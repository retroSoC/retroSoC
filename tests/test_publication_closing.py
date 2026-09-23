"""A declared final page may omit furniture without weakening body-page checks."""
from __future__ import annotations

import copy
import hashlib
import json

import pytest

from publications.page_reference import (
    PAGE_ROLES_FILE, REPOSITORY_URL, collect_page_roles, read_page_roles,
    validate_footer_pages, validate_footer_text, validate_page_roles,
)
from publications import report_changes as changes


def markers():
    return [{"kind": "publication-closing-start", "page": 3, "total_pages": 3},
            {"kind": "publication-closing-end", "page": 3, "total_pages": 3}]


def test_only_the_declared_final_page_has_a_footer_exception():
    roles = collect_page_roles(markers())
    assert validate_page_roles(roles, 3) == {3}
    validate_footer_pages([1, 2], 3, roles)
    validate_footer_text(REPOSITORY_URL, 2, {3})
    validate_footer_text("", 3, {3})


@pytest.mark.parametrize("actual", [[1], [2], [1, 2, 3]])
def test_body_footer_omission_and_closing_footer_are_rejected(actual):
    with pytest.raises(ValueError, match="footer pages"):
        validate_footer_pages(actual, 3, collect_page_roles(markers()))


@pytest.mark.parametrize("text,number", [("", 1), ("3 / 3", 3), (REPOSITORY_URL, 3)])
def test_page_role_does_not_hide_incorrect_visible_footer_text(text, number):
    with pytest.raises(ValueError, match="footer"):
        validate_footer_text(text, number, {3})


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "reversed", "split", "not_last", "different_count"])
def test_closing_markers_must_describe_one_complete_final_page(mutation):
    values = markers()
    if mutation == "missing":
        values.pop()
    elif mutation == "duplicate":
        values += copy.deepcopy(values)
    elif mutation == "reversed":
        values.reverse()
    elif mutation == "split":
        values[0]["page"] = 2
    elif mutation == "not_last":
        for value in values:
            value["page"] = 2
    else:
        values[1]["total_pages"] = 4
    with pytest.raises(ValueError, match="closing"):
        collect_page_roles(values)


@pytest.mark.parametrize("roles", [None, [{"role": "body", "page": 3}], [{"role": "closing", "page": 2}],
                                    [{"role": "closing", "page": True}],
                                    [{"role": "closing", "page": 3}, {"role": "closing", "page": 3}]])
def test_invalid_roles_cannot_create_a_general_page_exception(roles):
    with pytest.raises(ValueError):
        validate_page_roles(roles, 3)


def test_legacy_manifest_has_no_footer_exception(tmp_path):
    assert read_page_roles(tmp_path, {}, 3) == []
    validate_footer_pages([1, 2, 3], 3, [])
    with pytest.raises(ValueError, match="footer pages"):
        validate_footer_pages([1, 2], 3, [])


@pytest.mark.parametrize("mutation", ["modified", "missing", "unbound", "empty"])
def test_page_role_record_is_bound_to_its_manifest(tmp_path, mutation):
    path = tmp_path / PAGE_ROLES_FILE
    path.write_text(json.dumps(collect_page_roles(markers())), encoding="utf-8")
    manifest = {"page_roles_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    assert read_page_roles(tmp_path, manifest, 3) == [{"role": "closing", "page": 3}]
    if mutation == "modified":
        path.write_text('[{"role":"closing","page":2}]', encoding="utf-8")
    elif mutation == "missing":
        path.unlink()
    elif mutation == "empty":
        path.write_text("[]", encoding="utf-8")
        manifest["page_roles_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    else:
        manifest.clear()
    with pytest.raises(ValueError, match="page roles"):
        read_page_roles(tmp_path, manifest, 3)


def test_change_report_records_an_unprinted_viewer_page(tmp_path, monkeypatch):
    class Ref(dict):
        def get_object(self):
            return self

    class Page(dict):
        def extract_text(self):
            raise AssertionError("An unprinted closing page has no numeric footer to parse")

    class Reader:
        pages = [Page({"/Annots": [Ref({"/A": {"/URI": REPOSITORY_URL}, "/Rect": [54, 15, 230, 28]})]}) for _ in range(2)]
        pages += [Page({"/Annots": [Ref({"/A": {"/URI": REPOSITORY_URL}, "/Rect": [54, 72, 230, 81]})]})]

    pdf = tmp_path / "final.pdf"
    role_path = tmp_path / PAGE_ROLES_FILE
    role_path.write_text(json.dumps(collect_page_roles(markers())), encoding="utf-8")
    marker_path = tmp_path / "change-markers.json"
    marker_path.write_text(json.dumps([
        {"kind": "publication-change-start", "id": "closing-page", "title": "Closing", "category": "added", "page": 3},
        {"kind": "publication-change-end", "id": "closing-page", "page": 3},
    ]), encoding="utf-8")
    manifest = {"page_roles_sha256": changes.digest(role_path), "change_markers_sha256": changes.digest(marker_path)}
    (tmp_path / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    monkeypatch.setattr(changes, "verified_pdf", lambda path: (Reader(), "a" * 64))
    result = changes.report_changes(pdf, pdf)
    assert result["unnumbered_viewer_pages"] == [3]
    assert result["ranges"][0] == {"id": "closing-page", "title": "Closing", "category": "added",
                                    "start_page": 3, "end_page": 3, "printed_start": None,
                                    "printed_end": None, "numbering": "unprinted"}
    assert result["printed_pages_equal_viewer_pages"] is True
