"""Locked PLL acquisition is independent of product integration and other PDK setup."""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

import pytest

from physical.pdk import setup
from scripts import setup_helpers
from scripts.dependency_lock import source


def git(directory: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(directory), *args], text=True).strip()


def commit(directory: Path) -> str:
    git(directory, "add", ".")
    git(directory, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "-c", "user.name=PLL fixture", "-c", "user.email=fixture@example.invalid",
        "commit", "-qm", "PLL fixture")
    return git(directory, "rev-parse", "HEAD")


@pytest.fixture
def locked_pll(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, dict]:
    upstream = tmp_path / "upstream"
    upstream.mkdir()
    git(upstream, "init", "-q")
    for name in setup.PLL_VIEWS:
        path = upstream / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".v":
            content = "module PLL_TOP (input REFCLK, output CKOUT1); endmodule\n"
        elif path.suffix == ".lef":
            content = "MACRO PLL_TOP\nEND PLL_TOP\n"
        elif path.suffix == ".lib":
            content = "library (fixture) { cell (PLL_TOP) {} }\n"
        else:
            content = "PLL integration fixture; no timing qualification.\n"
        path.write_text(content)
    dependency = {"url": str(upstream), "revision": commit(upstream),
                  "destination": "cache/pll"}
    monkeypatch.setattr(setup, "ROOT", tmp_path)

    def selected(name: str) -> dict:
        assert name == "pdk_ics55_pll", "PLL-only setup touched another dependency"
        return dependency

    monkeypatch.setattr(setup, "source", selected)
    return upstream, dependency


def test_selected_pin_is_a_full_revision_outside_replaceable_liberty_cache() -> None:
    dependency = source("pdk_ics55_pll")
    assert dependency["revision"] == "6ebb1a8f7f4ccbccdb7f587664fdfe63cd39e61b"
    assert dependency["url"] == "https://github.com/openecos-projects/ics55_ecos_pll.git"
    assert dependency["destination"] == ".cache/retrosoc/sources/ics55_ecos_pll"
    assert dependency["license"] == "NOASSERTION"


def test_restore_records_hashes_and_reuses_clean_checkout_without_fetch(
    locked_pll, monkeypatch: pytest.MonkeyPatch
) -> None:
    upstream, dependency = locked_pll
    first = setup.setup_ics55_pll()
    destination = Path(first["destination"])
    assert git(destination, "rev-parse", "HEAD") == dependency["revision"]
    assert git(destination, "status", "--porcelain") == ""
    assert first["sha256"] == {
        name: hashlib.sha256((upstream / name).read_bytes()).hexdigest()
        for name in setup.PLL_VIEWS
    }
    monkeypatch.setattr(setup_helpers, "run", lambda *_args, **_kwargs: pytest.fail("unexpected mutation"))
    assert setup.setup_ics55_pll() == first


def test_dirty_checkout_is_preserved(locked_pll) -> None:
    record = setup.setup_ics55_pll()
    readme = Path(record["destination"]) / "README.md"
    readme.write_text("user changes\n")
    with pytest.raises(RuntimeError, match="local changes"):
        setup.setup_ics55_pll(update=True)
    assert readme.read_text() == "user changes\n"


def test_wrong_revision_requires_update_and_dirty_update_is_rejected(locked_pll) -> None:
    upstream, dependency = locked_pll
    record = setup.setup_ics55_pll()
    destination = Path(record["destination"])
    previous = dependency["revision"]
    (upstream / "README.md").write_text("next reviewed revision\n")
    dependency["revision"] = commit(upstream)
    with pytest.raises(RuntimeError, match="rerun with --update"):
        setup.setup_ics55_pll()
    assert git(destination, "rev-parse", "HEAD") == previous
    (destination / "README.md").write_text("local change\n")
    with pytest.raises(RuntimeError, match="dirty dependency"):
        setup.setup_ics55_pll(update=True)
    assert git(destination, "rev-parse", "HEAD") == previous


@pytest.mark.parametrize("missing", setup.PLL_VIEWS)
def test_missing_view_cannot_be_accepted(locked_pll, missing: str) -> None:
    upstream, dependency = locked_pll
    (upstream / missing).unlink()
    dependency["revision"] = commit(upstream)
    with pytest.raises(ValueError, match="missing or empty"):
        setup.setup_ics55_pll()


@pytest.mark.parametrize("view", ["verilog/PLL_TOP.blackbox.v", "lef/PLL_TOP.lef", "lib/PLL_TOP_typ.lib"])
def test_wrong_cell_identity_is_rejected(locked_pll, view: str) -> None:
    upstream, dependency = locked_pll
    path = upstream / view
    path.write_text(path.read_text().replace("PLL_TOP", "OTHER_CELL"))
    dependency["revision"] = commit(upstream)
    with pytest.raises(ValueError, match="does not define PLL_TOP"):
        setup.setup_ics55_pll()


@pytest.mark.parametrize("pdks", [[], ["IHP130"], ["ICS55", "IHP130"], ["ICS55", "ICS55"]])
def test_pll_component_rejects_ambiguous_or_wrong_pdk(pdks, monkeypatch) -> None:
    argv = ["setup.py", "--component", "pll"]
    for pdk in pdks:
        argv += ["--pdk", pdk]
    monkeypatch.setattr(sys, "argv", argv)
    monkeypatch.setattr(setup, "setup_ics55_pll", lambda **_: pytest.fail("invalid selection installed PLL"))
    with pytest.raises(SystemExit) as error:
        setup.main()
    assert error.value.code == 2


def test_pll_only_does_not_prepare_other_inputs(locked_pll, monkeypatch) -> None:
    monkeypatch.setattr(sys, "argv", ["setup.py", "--pdk", "ICS55", "--component", "pll"])
    monkeypatch.setattr(setup, "archive", lambda *_: pytest.fail("PLL-only setup requested an archive"))
    assert setup.main() == 0
