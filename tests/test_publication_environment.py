"""Environment descriptions follow executable sources, without claiming a run."""
from pathlib import Path
import shutil

import pytest

from publications.environment_reference import ENVIRONMENT_SOURCES, development_environment

ROOT = Path(__file__).resolve().parents[1]


def test_environment_reports_current_locked_runtime_versions():
    result = development_environment(ROOT)
    assert (result["platform"], result["ubuntu"], result["python"], result["java"], result["sbt"]) == (
        "Linux x86_64", "22.04", "3.10", "17", "1.10.0")
    assert not {"passed", "qualified", "performance"} & result.keys()


@pytest.mark.parametrize("path,old,new,reason", [
    ("docker/Dockerfile", "openjdk-17-jre-headless", "openjdk-21-jre-headless", "runtime/platform"),
    ("flake.nix", "python310Full", "python3Full", "runtime/platform"),
    (".github/workflows/development-environment.yml", "--behavioral-only", "--full", "evidence boundary"),
])
def test_environment_drift_requires_publication_review(tmp_path, path, old, new, reason):
    for relative in ENVIRONMENT_SOURCES:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    target = tmp_path / path
    original = target.read_text(encoding="utf-8")
    assert old in original
    target.write_text(original.replace(old, new), encoding="utf-8")
    with pytest.raises(ValueError, match=reason):
        development_environment(tmp_path)
