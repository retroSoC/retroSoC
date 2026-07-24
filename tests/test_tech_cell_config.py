from __future__ import annotations

import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
    ("profile", "pdk"),
    (
        ("configs/ci/hazard3-rv32im-gf180.mk", "GF180"),
        ("configs/ci/hazard3-rv32im-sky130.mk", "SKY130"),
    ),
)
def test_unqualified_pll_profiles_are_rejected(profile: str, pdk: str) -> None:
    result = subprocess.run(
        ("make", f"CONFIG={profile}", "HAVE_PLL=YES", "config"),
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert f"HAVE_PLL=YES requires a qualified crystal pad and is unsupported for PDK={pdk}" in (
        result.stdout + result.stderr
    )
