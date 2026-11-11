from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.formal_local_evidence import collect


def initialize_git(root: Path) -> str:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "formal@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "Formal"], check=True)
    (root / "tracked.txt").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "tracked.txt"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "fixture"], check=True)
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def write_result(variant: Path, step: str, revision: str) -> None:
    result = variant / f"formal/ga2d/result-{step}.json"
    log = variant / f"formal/ga2d/{step}.log"
    result.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("PASS\n", encoding="utf-8")
    result.write_text(
        json.dumps(
            {
                "tool": "formal-sv2v" if step == "sv2v" else f"formal-sby-{step}",
                "status": "passed",
                "exit_code": 0,
                "started_at": "2026-11-08T00:01:00Z",
                "finished_at": "2026-11-08T00:02:00Z",
                "duration_seconds": 1.0,
                "peak_rss_kib": 42,
                "log": str(log),
                "command": ["sby"],
            }
        ),
        encoding="utf-8",
    )
    (variant / f"formal/ga2d/{step}/status").parent.mkdir(parents=True, exist_ok=True)
    (variant / f"formal/ga2d/{step}/status").write_text("PASS\n", encoding="utf-8")
    (variant / "meta").mkdir(parents=True, exist_ok=True)
    (variant / "meta/manifest.json").write_text(
        json.dumps(
            {
                "profile": "ihp130",
                "configuration": {"PDK": "IHP130"},
                "repository": {"commit": revision, "dirty": False},
            }
        ),
        encoding="utf-8",
    )


def test_collects_existing_results_with_source_and_resource_identity(tmp_path: Path) -> None:
    revision = initialize_git(tmp_path)
    variant = tmp_path / "build/ihp130-test"
    write_result(variant, "prove", revision)
    write_result(variant, "cover", revision)
    write_result(variant, "sv2v", revision)
    output = tmp_path / "build/ci-summary/formal-ga2d.json"

    summary = collect(
        tmp_path,
        variant,
        "ga2d",
        "configs/ci/ihp130.mk",
        "IHP130",
        "2026-11-08T00:00:00Z",
        output,
    )

    assert summary["source_revision"] == revision
    assert summary["overall_status"] == "PASS"
    assert {item["stage"]: item["status"] for item in summary["coverage"]}["formal"] == "PASS"
    assert {result["tool"] for result in summary["results"]} == {
        "formal-sby-prove",
        "formal-sby-cover",
        "formal-sv2v",
    }
    assert {result["peak_rss_kib"] for result in summary["results"]} == {42}
    assert (variant / "meta/formal.json").is_file()


def test_rejects_dirty_or_mismatched_manifest_before_collecting(tmp_path: Path) -> None:
    revision = initialize_git(tmp_path)
    variant = tmp_path / "build/ihp130-test"
    write_result(variant, "prove", revision)
    manifest = json.loads((variant / "meta/manifest.json").read_text(encoding="utf-8"))
    manifest["repository"]["dirty"] = True
    (variant / "meta/manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    output = tmp_path / "build/ci-summary/formal-ga2d.json"

    with pytest.raises(RuntimeError, match="clean source worktree"):
        collect(tmp_path, variant, "ga2d", "configs/ci/ihp130.mk", "IHP130", "2026-11-08T00:00:00Z", output)
    assert not output.exists()

    manifest["repository"]["dirty"] = False
    manifest["repository"]["commit"] = "0" * 40
    (variant / "meta/manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(RuntimeError, match="does not match"):
        collect(tmp_path, variant, "ga2d", "configs/ci/ihp130.mk", "IHP130", "2026-11-08T00:00:00Z", output)
    assert not output.exists()
