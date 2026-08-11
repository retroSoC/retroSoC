"""Tests for the root clock/reset and CDC inventory checker."""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOMAIN_MAP = ROOT / "rtl/mini/integration/clock_reset_domains.json"
CHECKER = ROOT / "scripts/check_clock_reset_domains.py"


def check(domain_map: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--map", str(domain_map), "--root", str(ROOT)],
        text=True,
        capture_output=True,
    )


def write_invalid_map(tmp_path: Path, document: dict[str, object]) -> Path:
    path = tmp_path / "clock_reset_domains.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def test_clock_reset_domain_inventory_matches_the_rcu() -> None:
    result = check(DOMAIN_MAP)
    assert result.returncode == 0, result.stderr
    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    assert document["schema_version"] == 2
    assert {domain["name"] for domain in document["domains"]} == {
        "external",
        "system",
        "audio",
        "jtag",
        "dvp",
    }
    assert {
        (crossing["name"], crossing["source"], crossing["destination"])
        for crossing in document["crossings"]
    } >= {
        ("clint_timebase", "external", "system"),
        ("jtag_dmi", "jtag", "system"),
    }
    clint = next(
        crossing for crossing in document["crossings"] if crossing["name"] == "clint_timebase"
    )
    assert clint["primitive"] == "edge_det"
    assert {
        "rtc_command",
        "rtc_response",
        "rtc_event",
        "rtc_status",
        "rtc_interrupt_enable",
        "rtc_wake_enable",
        "rtc_wake_status",
    } <= {crossing["name"] for crossing in document["crossings"]}
    audio = next(domain for domain in document["domains"] if domain["name"] == "audio")
    assert math.isclose(audio["sta"]["period_ns"], 1_000_000_000 / 18_432_000)
    for profile in (ROOT / "configs").rglob("*.mk"):
        assert "AUD_CLK_HZ" in profile.read_text(encoding="utf-8")


def test_clock_reset_domain_inventory_rejects_unknown_domain_and_instance(tmp_path: Path) -> None:
    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    document["crossings"][0]["destination"] = "unknown"
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "references an unknown domain" in result.stderr

    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    document["domains"][0]["instance"] = "u_missing_rst_sync"
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "does not declare rst_sync instance" in result.stderr

    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    document["domains"][1]["sta"]["source_domain"] = "unknown"
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "STA source references unknown domain" in result.stderr
