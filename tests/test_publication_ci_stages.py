"""Installation success must not hide missing or failing runtime evidence."""
import copy

import pytest

from publications.dev_reference import validate_ci_snapshot

REVISION = "b" * 40


def snapshot():
    url = "https://github.com/retroSoC/retroSoC/actions/runs/123"
    stages = [dict(name=name, scope=scope, status="completed", conclusion=outcome, url=url + "/job/456")
              for name, scope, outcome in [("Docker build", "installation", "success"),
                                           ("Nix flake", "environment-check", "success"),
                                           ("IHP130 runtime", "runtime-regression", "failure")]]
    return dict(revision=REVISION, checked_date="2026-09-22", checked_at="2026-09-22T14:49:18Z",
                boundary="Workflow-level observations only", runs=[dict(name="development-environment", run_id=123,
                status="completed", conclusion="failure", url=url, scope="Environment and behavioral execution",
                note="No physical qualification inferred", observations=stages)])


def test_separate_successful_installation_and_failed_runtime_are_preserved():
    value = snapshot()
    before = copy.deepcopy(value)
    validate_ci_snapshot(value, REVISION)
    assert value == before
    assert value["runs"][0]["observations"][-1]["conclusion"] == "failure"


@pytest.mark.parametrize("kind,reason", [("pending", "unfinished"), ("scope", "boundary"),
                                         ("url", "recorded run"), ("utc", "UTC")])
def test_ci_stage_cannot_borrow_conclusion_scope_or_identity(kind, reason):
    value = snapshot()
    stage = value["runs"][0]["observations"][-1]
    if kind == "pending":
        stage["status"] = "in_progress"
    elif kind == "scope":
        stage["scope"] = "silicon-qualified"
    elif kind == "url":
        stage["url"] = stage["url"].replace("/runs/123", "/runs/124")
    else:
        value["checked_at"] = "2026-09-22"
    with pytest.raises(ValueError, match=reason):
        validate_ci_snapshot(value, REVISION)
