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
        "aon",
        "lp",
        "hp",
        "pclk",
        "memory",
        "audio",
        "jtag",
        "dvp",
        "usb2_ulpi",
    }
    assert {
        (crossing["name"], crossing["source"], crossing["destination"])
        for crossing in document["crossings"]
    } >= {
        ("clint_timebase", "aon", "lp"),
        ("jtag_dmi", "jtag", "lp"),
        ("hp_mmio", "hp", "lp"),
        ("data_plane_fault", "hp", "pclk"),
        ("io_dma_data", "pclk", "hp"),
        ("apu_data", "pclk", "hp"),
        ("ga2d_data", "pclk", "hp"),
        ("ga2d_source_idle", "pclk", "hp"),
        ("ga2d_source_quiesced", "pclk", "hp"),
        ("ga2d_hp_reset", "hp", "pclk"),
        ("ga2d_flush", "hp", "pclk"),
        ("ga2d_master_idle", "hp", "pclk"),
        ("ga2d_block_ack", "hp", "pclk"),
        ("npu_launch_mailbox", "pclk", "hp"),
        ("npu_result_mailbox", "hp", "pclk"),
        ("npu_snapshot_req_mailbox", "pclk", "hp"),
        ("npu_snapshot_resp_mailbox", "hp", "pclk"),
        ("npu_hp_reset", "hp", "pclk"),
        ("npu_hp_flush", "hp", "pclk"),
        ("npu_epoch_req", "pclk", "hp"),
        ("npu_epoch_ack", "hp", "pclk"),
        ("npu_quiesce_req", "pclk", "hp"),
        ("npu_quiesce_ack", "hp", "pclk"),
        ("npu_hp_busy", "hp", "pclk"),
        ("npu_hp_draining", "hp", "pclk"),
        ("npu_hp_pause_active", "hp", "pclk"),
        ("npu_source_idle", "pclk", "hp"),
        ("npu_source_quiesced", "pclk", "hp"),
    }
    clint = next(
        crossing for crossing in document["crossings"] if crossing["name"] == "clint_timebase"
    )
    assert clint["primitive"] == "edge_det"
    data_plane_fault = next(
        crossing for crossing in document["crossings"] if crossing["name"] == "data_plane_fault"
    )
    assert data_plane_fault["primitive"] == "async_reqack"
    assert data_plane_fault["instance"] == "u_fault_mailbox"
    assert data_plane_fault["unilateral_reset"] == {
        "source_reset": "abort_accepted_mailbox_item",
        "destination_reset": "abort_accepted_item_backpressure_unaccepted_source",
    }
    assert {
        "usb2_work",
        "usb2_result",
        "usb2_setup",
        "usb2_fill_command",
        "usb2_drain_command",
        "usb2_buffer_event",
        "usb2_view_request",
        "usb2_view_response",
        "usb2_fill_stream",
        "usb2_drain_stream",
        "usb2_role",
        "usb2_role_reset",
        "usb2_phy_reset",
        "usb2_high_speed",
        "usb2_enable",
        "usb2_device_addr",
        "usb2_endpoint_config",
        "usb2_timeout",
        "usb2_phy_status",
        "usb2_transaction_busy",
        "usb2_frame",
        "usb2_ecc_counts",
        "usb2_retry_event",
        "usb2_protocol_event",
    } <= {crossing["name"] for crossing in document["crossings"]}
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


def test_clock_reset_domain_inventory_rejects_invalid_sta_net_driver(tmp_path: Path) -> None:
    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    document["domains"][1]["sta"]["net"] = "invalid.net"
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "sta.net must be a SystemVerilog identifier" in result.stderr


def test_clock_reset_domain_inventory_requires_data_plane_fault_reset_contract(
    tmp_path: Path,
) -> None:
    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    data_plane_fault = next(
        crossing for crossing in document["crossings"] if crossing["name"] == "data_plane_fault"
    )
    data_plane_fault.pop("unilateral_reset")
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "unilateral_reset must declare the data-plane fault reset contract" in result.stderr

    document = json.loads(DOMAIN_MAP.read_text(encoding="utf-8"))
    data_plane_fault = next(
        crossing for crossing in document["crossings"] if crossing["name"] == "data_plane_fault"
    )
    data_plane_fault["instance"] = "u_other_mailbox"
    result = check(write_invalid_map(tmp_path, document))
    assert result.returncode != 0
    assert "must use async_reqack instance u_fault_mailbox" in result.stderr
