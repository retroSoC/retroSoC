"""Prevent publication drift in HP acceptance and ready-only Linux integration."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from publications import boot_acceptance_reference as br
from publications.software_reference import function_body


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def source_tree(tmp_path):
    for relative in br.SOURCES:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


def replace(root: Path, relative: str, old: str, new: str) -> None:
    path = root / relative
    text = path.read_text(encoding="utf-8")
    assert old in text
    path.write_text(text.replace(old, new), encoding="utf-8")


def test_actual_boot_requires_bounded_complete_acceptance():
    result = br.collect_boot_acceptance(ROOT, function_body)
    assert result["event_poll_iterations"] == 64000000
    assert result["npu_defines"] == ["RS_NPU_P5_ACCEPTANCE", "RS_NPU_P6_ACCEPTANCE"]
    assert [(row["event"], row["argument"], row["sequence"]) for row in result["messages"]] == [
        (1, 0x4C4E5801, 1), (2, 0x47413244, 2), (4, 0x43424F4B, 3)]
    assert result["rootfs_ready_only"]
    assert result["terminal_requires_cache_handoff"]
    assert result["failure_reset_requires_no_hp_ga2d_owner"]


def test_mailbox_purposes_follow_registers_in_the_actual_write_order():
    rows = br.ready_mailbox(ROOT)
    assert [(row["address"], row["register"], row["purpose"]) for row in rows] == [
        ("0x10019020", "HP_EVENT", "Linux-ready event"),
        ("0x10019024", "HP_ARG0", "Ready-state argument"),
        ("0x10019028", "HP_SEQUENCE", "Publication sequence"),
        ("0x1001902C", "HP_DOORBELL", "LP interrupt request"),
    ]


@pytest.mark.parametrize("relative,old,new,match", [
    (br.HAL_SOURCE, "RS_HP_MAILBOX_HP_EVENT_OFFSET       UINT32_C(0x020)",
     "RS_HP_MAILBOX_HP_EVENT_OFFSET       UINT32_C(0x024)", "HAL/RTL"),
    (br.HAL_SOURCE, "message->code = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_EVENT_OFFSET);",
     "message->code = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_ARG0_OFFSET);", "field semantics"),
    (br.MAILBOX_SOURCE, "`APB4_HP_MAILBOX__HP_DOORBELL: s_lp_intr_state_d = 1'b1;",
     "`APB4_HP_MAILBOX__HP_DOORBELL: s_hp_intr_state_d = 1'b1;", "LP interrupt"),
    (br.READY_SOURCE, "0x10019024 32 0x4C4E5801", "0x10019024 32 0x4C4E5802", "sequence"),
    (br.READY_SOURCE, "        ;;", "        start_ga2d_responder\n        ;;", "ready-only"),
    (br.READY_SOURCE, "        ;;", "        devmem 0x10019020 32 2\n        ;;", "sequence"),
])
def test_mailbox_or_service_drift_requires_new_review(source_tree, relative, old, new, match):
    replace(source_tree, relative, old, new)
    with pytest.raises(ValueError, match=match):
        br.ready_mailbox(source_tree)


@pytest.mark.parametrize("old,new,match", [
    ("timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout", "; ++timeout", "bounded poll"),
    ("if (message.sequence == sequence)", "if (message.sequence != sequence)", "token/error"),
    ("if (!s_hp_boot_ga2d_owned_by_hp)", "if (s_hp_boot_ga2d_owned_by_hp)", "reset ownership"),
    ("rs_hp_boot_fail(UINT8_C(13));", "rs_hp_boot_fail(UINT8_C(11));", "completion condition"),
    ("cache_clean_completed = true;", "cache_clean_completed = false;", "phase or ordering"),
    ("rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_LP, false)",
     "rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_HP, false)", "phase or ordering"),
    ("#if defined(RS_NPU_P5_ACCEPTANCE) || defined(RS_NPU_P6_ACCEPTANCE)",
     "#if 1", "optional NPU"),
])
def test_inaccurate_boot_protocol_claims_fail_collection(source_tree, old, new, match):
    replace(source_tree, br.BOOT_SOURCE, old, new)
    with pytest.raises(ValueError, match=match):
        br.collect_boot_acceptance(source_tree, function_body)


def test_ready_marker_cannot_become_terminal_success_unnoticed(source_tree):
    replace(source_tree, br.BOOT_SOURCE, 'printf("HP_LINUX_READY\\n");',
            'printf("HP_LINUX_READY\\n");\n    rs_test_finish(RS_TEST_PASSED, UINT8_C(0));')
    with pytest.raises(ValueError, match="terminal pass"):
        br.collect_boot_acceptance(source_tree, function_body)


@pytest.mark.parametrize("old,new", [
    ("if (rs_hp_boot_wait_hp_held())", "if (!rs_hp_boot_wait_hp_held())"),
    ("rs_resource_acknowledge_cache_clean() == RS_OK", "rs_resource_acknowledge_cache_clean() != RS_OK"),
    ("if (rs_hp_boot_wait_cache_request())", "if (!rs_hp_boot_wait_cache_request())"),
    ("if (rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_CACHE_EVENT,", "if (!rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_CACHE_EVENT,"),
])
def test_inverted_cache_success_guard_cannot_qualify_handoff(source_tree, old, new):
    replace(source_tree, br.BOOT_SOURCE, old, new)
    with pytest.raises(ValueError, match="positive cache-handoff"):
        br.collect_boot_acceptance(source_tree, function_body)


@pytest.mark.parametrize("function,old,new,match", [
    ("rs_hp_boot_wait_hp_held", "&& hp_status.reset_asserted", "", "held-state"),
    ("rs_hp_boot_wait_hp_held", "!hp_status.released", "hp_status.released", "held-state"),
    ("rs_hp_boot_wait_hp_held", "!hp_status.draining", "hp_status.draining", "held-state"),
    ("rs_hp_boot_wait_hp_held", "!hp_status.forced_fault &&", "", "held-state"),
    ("rs_hp_boot_wait_hp_held", "rs_hp_boot_ga2d_idle(RS_RESOURCE_OWNER_HP)",
     "rs_hp_boot_ga2d_idle(RS_RESOURCE_OWNER_LP)", "held-state"),
    ("rs_hp_boot_wait_hp_held", "|| defined(RS_NPU_P6_ACCEPTANCE)", "", "held-state NPU"),
    ("rs_hp_boot_wait_hp_held", "&& rs_hp_boot_npu_idle(RS_RESOURCE_OWNER_HP)",
     "|| rs_hp_boot_npu_idle(RS_RESOURCE_OWNER_HP)", "held-state NPU"),
    ("rs_hp_boot_wait_cache_request", "cache_status.request && !cache_status.clean",
     "cache_status.request && cache_status.clean", "cache request/clean"),
    ("rs_hp_boot_ga2d_idle", "!ga2d_status.draining &&", "", "ga2d safe-idle"),
    ("rs_hp_boot_npu_idle", "RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING | RS_NPU_STATUS_RECOVERING",
     "RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING", "npu safe-idle"),
])
def test_weakened_held_observation_cannot_qualify_handoff(source_tree, function, old, new, match):
    path = source_tree / br.BOOT_SOURCE
    source = path.read_text(encoding="utf-8")
    body = function_body(source, function)
    assert old in body
    path.write_text(source.replace(body, body.replace(old, new), 1), encoding="utf-8")
    with pytest.raises(ValueError, match=match):
        br.collect_boot_acceptance(source_tree, function_body)


def test_poll_budget_is_derived_without_inventing_time_units(source_tree):
    replace(source_tree, br.STATUS_SOURCE, "((rs_timeout_t)1000000U)", "((rs_timeout_t)2000000U)")
    result = br.collect_boot_acceptance(source_tree, function_body)
    assert result["default_poll_iterations"] == 2000000
    assert result["event_poll_iterations"] == 128000000
    assert not any("milliseconds" in key or "seconds" in key for key in result)


def test_mailbox_address_is_derived_from_the_memory_map(source_tree):
    path = source_tree / br.MAP_SOURCE
    source = json.loads(path.read_text(encoding="utf-8"))
    mailbox = next(row for row in source["regions"] if row["symbol"] == "APB4_HP_MAILBOX")
    mailbox["base"] = "0x1001A000"
    path.write_text(json.dumps(source), encoding="utf-8")
    replace(source_tree, br.READY_SOURCE, "0x100190", "0x1001A0")
    rows = br.ready_mailbox(source_tree)
    assert rows[0]["address"] == "0x1001A020"
    assert rows[0]["purpose"] == "Linux-ready event"
