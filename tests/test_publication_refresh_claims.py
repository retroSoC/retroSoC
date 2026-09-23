"""APU summary and rendered procedure follow deployed configuration and source order."""
from __future__ import annotations

import json
from pathlib import Path
import shutil

import pytest

from publications.dev_reference import (
    APU_CONFIGURATION_SOURCES,
    apu_acceptance_steps,
    apu_configurations,
    validate_accelerator_claims,
)

ROOT = Path(__file__).resolve().parents[1]
ACCEPTANCE = "app/apps/apu_release/main.c"


def copy_sources(destination: Path, sources: tuple[str, ...]) -> Path:
    for relative in sources:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return destination


def replace_source(root: Path, relative: str, before: str, after: str) -> None:
    path = root / relative
    text = path.read_text(encoding="utf-8")
    assert before in text
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def test_apu_profiles_follow_deployed_p5_and_committed_p7_selection():
    ordinary, acceptance = apu_configurations(ROOT)
    assert ordinary["formats"] == {"WAV": True, "FLAC": True, "MP3": False, "KWS": False}
    assert acceptance["formats"] == {"WAV": True, "FLAC": True, "MP3": False, "KWS": True}
    assert (ordinary["capability"], ordinary["digest"]) == (0x1BD, 0)
    assert (acceptance["capability"], acceptance["digest"]) == (0x1FD, 0xF5005D7C)


@pytest.mark.parametrize("relative,before,after,message", [
    ("rtl/ip/multimedia/apb4_apu.sv", ".EnableP5(1'b1)", ".EnableP5(1'b0)", "EnableP5"),
    ("rtl/mini/top/apb4_periph.sv", ".EnableP7(EnableP7)", ".EnableP7(1'b0)", "propagation"),
    ("Makefile", "APU_ENABLE_P7     ?= NO", "APU_ENABLE_P7     ?= YES", "identities"),
    ("configs/ci/ihp130-apu.mk", "APU_ENABLE_P7      := YES", "APU_ENABLE_P7      := NO", "identities"),
    ("rtl/ip/multimedia/apu_reg.sv", "32'h0000_01bd", "32'h0000_01b9", "format capability"),
    ("configs/ci/ihp130-apu.mk", "HAVE_CSR           := YES", "HAVE_CSR           := NO", "IRQ configuration"),
])
def test_changed_implementation_cannot_retain_apu_summary(tmp_path, relative, before, after, message):
    root = copy_sources(tmp_path, APU_CONFIGURATION_SOURCES)
    replace_source(root, relative, before, after)
    with pytest.raises(ValueError, match=message):
        apu_configurations(root)


def test_apu_rendered_acceptance_is_source_ordered_and_failure_checked():
    steps = apu_acceptance_steps(ROOT)
    assert [step["id"] for step in steps] == ["probe", "quiesce", "stage", "acl", "load", "handoff"]
    assert [step["failure_code"] for step in steps] == list(range(5, 11))
    assert all(step["source"] == ACCEPTANCE for step in steps)
    template = (ROOT / "publications/datasheets/sections/apu-release.typ").read_text(encoding="utf-8")
    assert "#enum(..data.system_reference.apu_implementation.acceptance_steps.map(r=>r.description))" in template


@pytest.mark.parametrize("before,after,message", [
    ("if (!rs_apu_release_quiesce())", "if (!rs_apu_release_stage_assets())", "call order"),
    ("rs_apu_release_fail(UINT8_C(6));", "rs_apu_release_fail(UINT8_C(7));", "failure checkpoint"),
    ("load_status = rs_apu_microcode_load(&mc_image", "load_status = rs_apu_kws_model_load(&mc_image", "image-load order"),
    ("rs_sysctrl_set_hp_release(true)", "rs_sysctrl_set_hp_release(false)", "publication/release order"),
])
def test_changed_acceptance_cannot_retain_published_steps(tmp_path, before, after, message):
    root = copy_sources(tmp_path, (ACCEPTANCE,))
    replace_source(root, ACCEPTANCE, before, after)
    with pytest.raises(ValueError, match=message):
        apu_acceptance_steps(root)


@pytest.mark.parametrize("stale", [False, True])
def test_summary_rejects_disabled_jobs_without_rejecting_qualification_limits(stale):
    folder = ROOT / "publications/datasheets"
    catalog, features, content = [json.loads((folder / name).read_text(encoding="utf-8")) for name in
                                  ("ip-catalog.json", "features.json", "ip-content.json")]
    reference = {"npu_implementation": {"capability": 0},
                 "apu_implementation": {"profiles": apu_configurations(ROOT)}}
    if stale:
        next(row for row in catalog if row["id"] == "apu")["summary"] = (
            "Partially implemented coreless audio subsystem; production codec jobs remain disabled.")
        with pytest.raises(ValueError, match="contradicts deployed WAV/FLAC"):
            validate_accelerator_claims(reference, catalog, features, content, {}, {})
    else:
        validate_accelerator_claims(reference, catalog, features, content, {}, {})
