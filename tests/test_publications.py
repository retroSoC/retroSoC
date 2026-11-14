"""Datasheet extraction rejects stale, ambiguous and incomplete engineering inputs."""
from __future__ import annotations

import copy
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from publications import build_datasheet as ds  # noqa: E402


def sample_catalog():
    return [{"id": "timer", "regions": ["TIM0"], "irqs": ["timer0"],
             "sources": ["docs/ip/timer.md"]}]


def test_catalog_rejects_missing_active_or_reserved_window():
    with pytest.raises(ValueError, match="undocumented regions"):
        ds.validate_catalog(sample_catalog(), [{"symbol": "TIM0"}, {"symbol": "RESERVED"}],
                            [{"name": "timer0"}])


def test_catalog_rejects_duplicate_region_between_different_ips():
    entries = sample_catalog()
    second = copy.deepcopy(entries[0])
    second["id"] = "other"
    entries.append(second)
    with pytest.raises(ValueError, match="duplicate catalog region"):
        ds.validate_catalog(entries, [{"symbol": "TIM0"}], [{"name": "timer0"}])


def test_catalog_rejects_lost_interrupt():
    with pytest.raises(ValueError, match="undocumented IRQs"):
        ds.validate_catalog(sample_catalog(), [{"symbol": "TIM0"}],
                            [{"name": "timer0"}, {"name": "timer1"}])


def test_catalog_rejects_unknown_interrupt():
    with pytest.raises(ValueError, match="unknown or duplicate catalog IRQ"):
        ds.validate_catalog(sample_catalog(), [{"symbol": "TIM0"}], [])


def test_profile_rejects_make_evaluation_and_duplicate_assignment(tmp_path):
    profile = tmp_path / "bad.mk"
    profile.write_text("SRAM_SIZE_KIB := $(shell echo 32)\n")
    with pytest.raises(ValueError, match="unsupported profile expression"):
        ds.profile_values(profile)
    profile.write_text("SRAM_SIZE_KIB := 32\nSRAM_SIZE_KIB := 128\n")
    with pytest.raises(ValueError, match="duplicate profile assignment"):
        ds.profile_values(profile)


def test_reviewed_profile_resolves_sram_instead_of_using_decoder_maximum():
    config = ds.read_json(ds.CONFIG)
    profile = ds.profile_values(ROOT / config["profile"])
    generator = ds.load_generator("test_datasheet_memory", "scripts/rtl/generate_memory_map.py")
    _, regions, _ = generator.read_map(ROOT / ds.MAP, int(profile["SRAM_SIZE_KIB"]))
    sram = next(r for r in regions if r["symbol"] == "SRAM")
    assert sram["size"] == 32768
    assert sram["end"] == 0x30007FFF
    assert next(r for r in regions if r["symbol"] == "SPISD")["kind"] == "reserved"


def test_gpio_label_preserves_index_and_collapses_bidirectional_pair():
    mode = SimpleNamespace(inputs=["u_opipsram_if.dq_i[4]"], do="u_opipsram_if.dq_o[4]")
    assert ds.gpio_label(mode) == "OPIPSRAM.DQ[4]"
    assert ds.gpio_label(SimpleNamespace(inputs=[], do="1'b0")) == "-"


def test_source_drift_does_not_silently_relabel_old_prose(monkeypatch):
    monkeypatch.setattr(ds, "git", lambda *args, **kwargs: "rtl/mini/top/retrosoc.sv")
    with pytest.raises(ValueError, match="technical sources differ"):
        ds.validate_source(ds.read_json(ds.CONFIG))


@pytest.fixture
def build_review(tmp_path, monkeypatch):
    import subprocess

    def git(*args):
        return subprocess.check_output([
            "git", "-C", str(tmp_path), "-c", "user.name=Publication Test",
            "-c", "user.email=publication@example.invalid", "-c", "commit.gpgsign=false", *args,
        ], text=True).strip()

    git("init", "--quiet")
    makefile = tmp_path / "Makefile"
    makefile.write_text("firmware:\n\t@true\n")
    git("add", "Makefile")
    git("commit", "--quiet", "-m", "test: product baseline")
    baseline = git("rev-parse", "HEAD")
    makefile.write_text("firmware:\n\t@true\nagent-help:\n\t@true\n")
    git("add", "Makefile")
    git("commit", "--quiet", "-m", "test: reviewed agent target")
    config = {"source_revision": baseline, "build_control_review": {
        "revision": git("rev-parse", "HEAD"), "makefile_blob": git("rev-parse", "HEAD:Makefile"),
        "reason": "Reviewed Agent target only; firmware rule unchanged.",
    }}
    monkeypatch.setattr(ds, "git", git)
    return config, makefile, git


def test_explicit_build_control_review_preserves_the_product_revision(build_review):
    config, _, _ = build_review
    assert ds.reviewed_build_control(config)
    assert config["source_revision"] != config["build_control_review"]["revision"]
    assert ds.reviewed_build_control({"source_revision": config["source_revision"]}) is False


@pytest.mark.parametrize("mutation", ["dirty", "later-commit", "blob", "reason", "baseline"])
def test_build_control_review_cannot_cover_unreviewed_changes(build_review, mutation):
    config, makefile, git = build_review
    if mutation in {"dirty", "later-commit", "baseline"}:
        makefile.write_text("firmware:\n\t@false\n")
        if mutation != "dirty":
            git("add", "Makefile")
            git("commit", "--quiet", "-m", "test: unreviewed product rule")
        if mutation == "baseline":
            config["source_revision"] = git("rev-parse", "HEAD")
    elif mutation == "blob":
        config["build_control_review"]["makefile_blob"] = "0" * 40
    else:
        config["build_control_review"]["reason"] = ""
    with pytest.raises(ValueError):
        ds.reviewed_build_control(config)


def test_build_control_review_never_waives_rtl_drift(monkeypatch):
    monkeypatch.setattr(ds, "git", lambda *args, **kwargs: "Makefile\nrtl/mini/top/retrosoc.sv")
    monkeypatch.setattr(ds, "reviewed_build_control", lambda config: True)
    with pytest.raises(ValueError, match="rtl/mini/top/retrosoc.sv"):
        ds.validate_source(ds.read_json(ds.CONFIG))


def test_missing_media_fails_without_attempting_network(tmp_path, monkeypatch):
    monkeypatch.setattr(ds, "ROOT", tmp_path)
    with pytest.raises(ValueError, match="media repository missing; run setup"):
        ds.check_assets({"sources": {"publication_media": {"destination": "publications/media"}}})


def test_compiler_version_is_checked_before_build(monkeypatch):
    monkeypatch.setattr(ds.subprocess, "check_output", lambda *a, **k: "typst 0.14.0 (test)")
    lock = {"publication_tools": {"typst": {"version": "0.15.1"}}}
    with pytest.raises(ValueError, match="expected Typst 0.15.1"):
        ds.resolve_typst("typst", lock)
