"""Cold shallow dependencies must support immutable publication snapshots."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest
import yaml

import publication_history as history
from scripts import setup_helpers


def git(repository: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repository), *args], text=True).strip()


def init(repository: Path) -> None:
    repository.mkdir(parents=True)
    git(repository, "init")
    git(repository, "config", "user.name", "Fixture")
    git(repository, "config", "user.email", "fixture@example.com")
    git(repository, "config", "commit.gpgsign", "false")


def commit(repository: Path, path: str, content: str) -> str:
    target = repository / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content)
    git(repository, "add", path)
    git(repository, "commit", "-m", "fixture")
    return git(repository, "rev-parse", "HEAD")


@pytest.fixture
def shallow_dependency(tmp_path: Path):
    upstream = tmp_path / "upstream"
    init(upstream)
    old = commit(upstream, "value.txt", "historical interface\n")
    current = commit(upstream, "value.txt", "current interface\n")
    checkout = tmp_path / "project/rtl/managed/pwm"
    setup_helpers.ensure_git_repo(upstream.as_uri(), checkout, current)
    assert git(checkout, "rev-parse", "--is-shallow-repository") == "true"
    assert subprocess.run(["git", "-C", str(checkout), "cat-file", "-e", old + "^{commit}"],
                          capture_output=True).returncode != 0
    return upstream, checkout, old, current


def test_prepare_uses_historical_lock_and_preserves_active_checkout(
    shallow_dependency, tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    upstream, checkout, old, current = shallow_dependency
    root = tmp_path / "project"
    # The dependency directory already exists; initialize only the parent repo.
    git(root, "init")
    git(root, "config", "user.name", "Fixture")
    git(root, "config", "user.email", "fixture@example.com")
    git(root, "config", "commit.gpgsign", "false")
    spec = {"url": upstream.as_uri(), "destination": "rtl/managed/pwm", "revision": old}
    lock_path = "dependencies/dependencies.lock.json"
    historical = commit(root, lock_path, json.dumps({"sources": {"cluster_pwm": spec}}))
    spec["revision"] = current
    commit(root, lock_path, json.dumps({"sources": {"cluster_pwm": spec}}))
    lock_before = (root / lock_path).read_bytes()
    monkeypatch.setattr(history, "HISTORICAL_REVISIONS", (historical,))
    monkeypatch.setattr(history, "HISTORICAL_SOURCES", ("cluster_pwm",))

    # Reproduce CI: root history exists, but the old PWM object does not.
    missing = subprocess.run(["git", "-C", str(checkout), "archive", old], capture_output=True)
    assert missing.returncode != 0 and b"not a tree object" in missing.stderr
    (checkout / "value.txt").write_text("user staged edit\n")
    git(checkout, "add", "value.txt")
    (checkout / "value.txt").write_text("user unstaged edit\n")
    (checkout / "note.txt").write_text("user untracked file\n")
    status_before = git(checkout, "status", "--porcelain")
    index_before = git(checkout, "write-tree")
    fetch_before = (checkout / ".git/FETCH_HEAD").read_bytes()

    history.prepare(root)
    assert git(checkout, "rev-parse", "HEAD") == current
    assert git(checkout, "write-tree") == index_before
    assert git(checkout, "status", "--porcelain") == status_before
    assert (checkout / ".git/FETCH_HEAD").read_bytes() == fetch_before
    assert (checkout / "value.txt").read_text() == "user unstaged edit\n"
    assert (checkout / "note.txt").read_text() == "user untracked file\n"
    assert (root / lock_path).read_bytes() == lock_before
    history.export(checkout, old, tmp_path / "historical-export")
    assert (tmp_path / "historical-export/value.txt").read_text() == "historical interface\n"

    def no_fetch(*args, **kwargs):
        pytest.fail("cached historical commits must be usable offline")

    monkeypatch.setattr(setup_helpers, "run", no_fetch)
    history.prepare(root)


def test_prepare_can_restore_history_from_local_reference(
    shallow_dependency, tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    upstream, checkout, old, current = shallow_dependency
    root = tmp_path / "project"
    git(root, "init")
    git(root, "config", "user.name", "Fixture")
    git(root, "config", "user.email", "fixture@example.com")
    spec = {"url": upstream.as_uri(), "destination": "rtl/managed/pwm", "revision": old}
    historical = commit(
        root,
        "dependencies/dependencies.lock.json",
        json.dumps({"sources": {"cluster_pwm": spec}}),
    )
    monkeypatch.setattr(history, "HISTORICAL_REVISIONS", (historical,))
    monkeypatch.setattr(history, "HISTORICAL_SOURCES", ("cluster_pwm",))
    reference_root = tmp_path / "reference"
    reference = reference_root / "rtl/managed/pwm"
    subprocess.run(
        ["git", "clone", "-q", "--no-local", str(upstream), str(reference)],
        check=True,
    )
    git(reference, "remote", "set-url", "origin", upstream.as_uri())
    index_before = git(checkout, "write-tree")
    history.prepare(root, reference_root=reference_root)
    assert git(checkout, "cat-file", "-e", old + "^{commit}") == ""
    assert git(checkout, "rev-parse", "HEAD") == current
    assert git(checkout, "write-tree") == index_before


def test_failed_historical_fetch_preserves_checkout(shallow_dependency, tmp_path: Path) -> None:
    _, checkout, old, current = shallow_dependency
    with pytest.raises(subprocess.CalledProcessError):
        setup_helpers.ensure_git_commit((tmp_path / "missing-upstream").as_uri(), checkout, old)
    assert git(checkout, "rev-parse", "HEAD") == current
    assert git(checkout, "status", "--porcelain") == ""
    assert (checkout / "value.txt").read_text() == "current interface\n"


@pytest.mark.parametrize("revision", ["main", "1234", "x" * 40, "--all"])
def test_historical_fetch_rejects_unpinned_revision(tmp_path: Path, revision: str) -> None:
    with pytest.raises(ValueError, match="full Git commit"):
        setup_helpers.ensure_git_commit("unused", tmp_path / "uncreated", revision)
    assert not (tmp_path / "uncreated").exists()


def test_quality_prepares_history_before_offline_pytest() -> None:
    root = Path(__file__).resolve().parents[1]
    workflow = yaml.safe_load((root / ".github/workflows/quality.yml").read_text())
    steps = workflow["jobs"]["fixtures"]["steps"]
    checkout = next(step for step in steps if step["name"] == "Check out repository")
    assert checkout["with"]["fetch-depth"] == 0
    dependencies = next(step for step in steps if step["name"] == "Set up locked RTL dependencies")
    preparation = next(step for step in steps
                       if step.get("run") == "python3 tests/publication_history.py prepare")
    tests = next(step for step in steps if step["name"] == "Test scripts and RTL fixtures")
    assert steps.index(dependencies) < steps.index(preparation) < steps.index(tests)
    assert "if" not in preparation and not preparation.get("continue-on-error", False)


def test_prepare_entrypoint_restores_locked_fonts_on_a_cold_checkout(tmp_path, monkeypatch):
    upstream = tmp_path / "media-upstream"
    init(upstream)
    font_path = "fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    revision = commit(upstream, font_path, "fixture font bytes\n")
    root = tmp_path / "project"
    (root / "dependencies").mkdir(parents=True)
    lock = root / "dependencies/dependencies.lock.json"
    lock.write_text(json.dumps({"sources": {"publication_media": {
        "url": upstream.as_uri(), "destination": "publications/media", "revision": revision,
    }}}))
    before = lock.read_bytes()
    monkeypatch.setattr(history, "HISTORICAL_REVISIONS", ())
    history.main(["prepare"], root=root)
    media = root / "publications/media"
    assert (media / font_path).read_text() == "fixture font bytes\n"
    assert git(media, "rev-parse", "HEAD") == revision
    assert lock.read_bytes() == before
    history.main(["prepare"], root=root)
    (media / font_path).write_text("retained user changes\n")
    with pytest.raises(RuntimeError, match="local changes"):
        history.main(["prepare"], root=root)
    assert (media / font_path).read_text() == "retained user changes\n"
    assert lock.read_bytes() == before


def test_media_restore_uses_a_private_locked_local_reference(tmp_path, monkeypatch):
    reference_root = tmp_path / "reference"
    reference = reference_root / "publications/media"
    init(reference)
    revision = commit(reference, "font.ttf", "font\n")
    url = "https://example.invalid/locked-media.git"
    git(reference, "remote", "add", "origin", url)
    root = tmp_path / "project"
    (root / "dependencies").mkdir(parents=True)
    lock = root / "dependencies/dependencies.lock.json"
    spec = {"url": url, "destination": "publications/media", "revision": revision}
    lock.write_text(json.dumps({"sources": {"publication_media": spec}}))
    monkeypatch.setattr(history, "HISTORICAL_REVISIONS", ())
    history.main(["prepare", "--reference-root", str(reference_root)], root=root)
    media = root / "publications/media"
    assert git(media, "rev-parse", "HEAD") == revision
    assert not (media / ".git/objects/info/alternates").exists()
    assert (media / "font.ttf").read_bytes() == (reference / "font.ttf").read_bytes()
    spec["destination"] = "../outside"
    lock.write_text(json.dumps({"sources": {"publication_media": spec}}))
    with pytest.raises(ValueError, match="escapes checkout"):
        history.main(["prepare"], root=root)
