"""A same-version revision must not repeat the previous edition's added claims."""
import copy

import pytest

from publications.report_changes import REPOSITORY_URL, page_ranges, printed_page_number, validate_change_scope


def markers(identifier, category="modified"):
    return [dict(kind="publication-change-start", id=identifier, page=2, title="Reviewed content", category=category),
            dict(kind="publication-change-end", id=identifier, page=3)]


def test_current_content_and_shared_navigation_keep_separate_scopes():
    values = markers("v05-refresh-hp-boot") + markers("contents", "navigation")
    before = copy.deepcopy(values)
    validate_change_scope(values, {"change_prefix": "v05-refresh-"})
    assert values == before
    assert {row["category"] for row in page_ranges(values, 3)} == {"modified", "navigation"}


@pytest.mark.parametrize("identifier", ["v05-npu", "ga2d-chapter", "dev-software", "soc-functional"])
def test_previous_round_content_cannot_reappear_in_current_change_record(identifier):
    with pytest.raises(ValueError, match="earlier publication round"):
        validate_change_scope(markers(identifier, "added"), {"change_prefix": "v05-refresh-"})


def test_shared_navigation_cannot_be_relabelled_as_added_content():
    with pytest.raises(ValueError, match="navigation marker"):
        validate_change_scope(markers("contents", "added"), {"change_prefix": "v05-refresh-"})


def test_historical_manifest_without_change_policy_remains_readable():
    validate_change_scope(markers("v05-npu", "added"), {})


def test_body_ratios_are_not_ambiguous_footer_numbers():
    text = f"CAS 2/3, BL 2/8, write-burst, sequential only.\n{REPOSITORY_URL} 204 / 779 2026-09-22"
    assert printed_page_number(text, 779) == 204


@pytest.mark.parametrize("text", [
    "CAS 2/3, BL 2/8", "204 / 779", REPOSITORY_URL,
    f"{REPOSITORY_URL} 204 / 778", f"{REPOSITORY_URL} 0 / 779",
    f"{REPOSITORY_URL} 780 / 779", f"{REPOSITORY_URL} 204 / 779 205 / 779",
])
def test_footer_scope_still_rejects_missing_wrong_or_duplicate_labels(text):
    with pytest.raises(ValueError, match="printed footer"):
        printed_page_number(text, 779)
