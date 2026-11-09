from __future__ import annotations

from pathlib import Path

from scripts.engineering_metrics import normalize_pulls, normalize_runs, pr_category, summarize


RUNS = {
    "workflow_runs": [
        {
            "id": 1,
            "name": "quality",
            "event": "pull_request",
            "status": "completed",
            "conclusion": "success",
            "head_branch": "dev",
            "head_sha": "a" * 40,
            "created_at": "2026-11-01T00:00:00Z",
            "updated_at": "2026-11-01T01:00:00Z",
        },
        {
            "id": 2,
            "name": "quality",
            "event": "pull_request",
            "status": "completed",
            "conclusion": "failure",
            "head_branch": "dev",
            "head_sha": "b" * 40,
            "created_at": "2026-11-02T00:00:00Z",
            "updated_at": "2026-11-02T02:00:00Z",
        },
        {
            "id": 3,
            "name": "nightly",
            "event": "schedule",
            "status": "completed",
            "conclusion": "cancelled",
            "created_at": "2026-11-03T00:00:00Z",
            "updated_at": "2026-11-03T00:30:00Z",
        },
    ]
}

PULLS = [
    {
        "number": 1,
        "baseRefName": "dev",
        "headRefName": "feat/agent-control",
        "createdAt": "2026-11-01T00:00:00Z",
        "closedAt": "2026-11-02T00:00:00Z",
        "mergedAt": "2026-11-02T00:00:00Z",
        "mergeCommit": {"oid": "c" * 40},
        "commits": [{}, {}],
        "reviews": [{}],
    },
    {
        "number": 2,
        "baseRefName": "dev",
        "headRefName": "dependabot/pip/requirements/dev/pytest-9",
        "createdAt": "2026-11-01T00:00:00Z",
        "closedAt": "2026-11-01T01:00:00Z",
        "mergedAt": "2026-11-01T01:00:00Z",
        "mergeCommit": {"oid": "d" * 40},
        "commits": [{}],
        "reviews": [],
    },
    {
        "number": 3,
        "baseRefName": "main",
        "headRefName": "dev",
        "createdAt": "2026-11-05T00:00:00Z",
        "closedAt": "2026-11-05T00:01:00Z",
        "mergedAt": "2026-11-05T00:01:00Z",
        "mergeCommit": {"oid": "e" * 40},
        "commits": [{}] * 10,
        "reviews": [],
    },
]


def test_metrics_summarize_duration_lead_time_and_reviews() -> None:
    runs = normalize_runs(RUNS)
    pulls = normalize_pulls(PULLS)
    result = summarize(runs, pulls)
    quality = next(item for item in result["workflows"] if item["name"] == "quality")
    assert quality["duration_seconds_median"] == 5400
    assert quality["duration_seconds_p95"] == 7200
    assert quality["failure_count"] == 1
    assert result["merged_pull_request_count"] == 3
    assert result["merged_without_review_count"] == 2
    assert result["commits_per_pull_request_median"] == 2
    assert result["merged_lead_time_seconds_median"] == 3600


def test_pull_request_categories_remain_separate() -> None:
    assert pr_category(PULLS[0]) == "topic"
    assert pr_category(PULLS[1]) == "dependabot"
    assert pr_category(PULLS[2]) == "release_integration"
    result = summarize(normalize_runs(RUNS), normalize_pulls(PULLS))
    categories = {item["category"]: item["count"] for item in result["pull_request_categories"]}
    assert categories == {"topic": 1, "dependabot": 1, "release_integration": 1}


def test_summarize_handles_empty_samples(tmp_path: Path) -> None:
    result = summarize([], [])
    assert result["run_count"] == 0
    assert result["merged_lead_time_seconds_median"] is None
    assert result["workflows"] == []
