"""Reviewed HP boot phases and mailbox semantics for the publication only."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Callable

from publications.implementation_reference import without_comments


BOOT_SOURCE = "app/apps/hp_boot/main.c"
READY_SOURCE = "app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp"
HAL_SOURCE = "crt/src/hal/hp_mailbox.c"
STATUS_SOURCE = "crt/include/retrosoc/core/status.h"
REGISTER_SOURCE = "rtl/ip/peripheral/hp_mailbox_define.svh"
MAILBOX_SOURCE = "rtl/ip/peripheral/apb4_hp_mailbox.sv"
MAP_SOURCE = "rtl/mini/address_map/memory_map.json"
SOURCES = {BOOT_SOURCE, READY_SOURCE, HAL_SOURCE, STATUS_SOURCE, REGISTER_SOURCE, MAILBOX_SOURCE, MAP_SOURCE}
NPU_DEFINES = ("RS_NPU_P5_ACCEPTANCE", "RS_NPU_P6_ACCEPTANCE")


def compact(source: str) -> str:
    return re.sub(r"\s+", "", without_comments(source))


def uint_constants(source: str) -> dict[str, int]:
    return {name: int(value, 0) for name, value in re.findall(
        r"^#define\s+(\w+)\s+UINT32_C\((0x[\da-fA-F]+|\d+)\)\s*$", source, re.M)}


def ready_mailbox(root: Path) -> list[dict]:
    """Resolve rootfs writes to register purposes, rather than positional labels."""
    hal = (root / HAL_SOURCE).read_text(encoding="utf-8")
    rtl = (root / REGISTER_SOURCE).read_text(encoding="utf-8")
    offsets = {name: int(value, 16) for name, value in re.findall(
        r"^`define\s+APB4_HP_MAILBOX__(\w+)\s+12'h([\da-fA-F]+)\s*$", rtl, re.M)}
    constants = uint_constants(hal)
    registers = ("HP_EVENT", "HP_ARG0", "HP_SEQUENCE", "HP_DOORBELL")
    if not set(registers) <= offsets.keys():
        raise ValueError("missing HP ready mailbox registers")
    for register in registers[:-1]:
        if constants.get(f"RS_HP_MAILBOX_{register}_OFFSET") != offsets[register]:
            raise ValueError("HP ready mailbox HAL/RTL offset mismatch")
    hal_bindings = (
        "message->code = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_EVENT_OFFSET);",
        "message->argument = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_ARG0_OFFSET);",
        "sequence = *rs_hp_mailbox_register(RS_HP_MAILBOX_HP_SEQUENCE_OFFSET);",
        "message->sequence = sequence;",
        "RS_SOC_APB4_HP_MAILBOX_BASE + offset",
    )
    if any(compact(binding) not in compact(hal) for binding in hal_bindings):
        raise ValueError("HP ready mailbox HAL field semantics changed")
    mailbox = (root / MAILBOX_SOURCE).read_text(encoding="utf-8")
    if "`APB4_HP_MAILBOX__HP_DOORBELL:s_lp_intr_state_d=1'b1;" not in compact(mailbox):
        raise ValueError("HP ready doorbell no longer requests the LP interrupt")
    address_map = json.loads((root / MAP_SOURCE).read_text(encoding="utf-8"))
    windows = [row for row in address_map["regions"] if row["symbol"] == "APB4_HP_MAILBOX"]
    if len(windows) != 1:
        raise ValueError("missing or ambiguous HP mailbox address window")
    base = int(windows[0]["base"], 0)
    boot_constants = uint_constants((root / BOOT_SOURCE).read_text(encoding="utf-8"))
    expected_values = [boot_constants[key] for key in (
        "RS_HP_BOOT_READY_EVENT", "RS_HP_BOOT_READY_ARG", "RS_HP_BOOT_MAILBOX_READY_SEQUENCE")] + [1]
    ready = (root / READY_SOURCE).read_text(encoding="utf-8")
    writes = [(int(address, 0), int(value, 0)) for address, value in re.findall(
        r"^\s*devmem\s+(0x[\da-fA-F]+)\s+32\s+(0x[\da-fA-F]+)\s*$", ready, re.M)]
    expected = [(base + offsets[register], value)
                for register, value in zip(registers, expected_values, strict=True)]
    if writes != expected or sum(line.lstrip().startswith("devmem ") for line in ready.splitlines()) != len(writes):
        raise ValueError("Linux ready mailbox sequence changed")
    message = 'echo "retroSoC HP Linux ready"'
    if message not in ready or ready.index(message) > ready.index("devmem"):
        raise ValueError("Linux ready message/publication order changed")
    # A newly added responder invalidates the documented ready-only service gap.
    shell_lines = [line.strip() for line in ready.splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
    scaffold = ['case "$1" in', "start)", message, ";;", "esac"]
    if [line for line in shell_lines if not line.startswith("devmem ")] != scaffold:
        raise ValueError("Linux ready-only service changed; review its acceptance coverage")
    purposes = {"HP_EVENT": "Linux-ready event", "HP_ARG0": "Ready-state argument",
                "HP_SEQUENCE": "Publication sequence", "HP_DOORBELL": "LP interrupt request"}
    register_by_address = {base + offsets[register]: register for register in registers}
    return [{"address": f"0x{address:08X}", "value": f"0x{value:08X}",
             "register": register_by_address[address], "purpose": purposes[register_by_address[address]]}
            for address, value in writes]


def split_npu_conditions(body: str) -> tuple[str, list[tuple[str, str]]]:
    """Keep unconditional acceptance separate from reviewed optional NPU blocks."""
    unconditional, blocks, current = [], [], []
    condition = None
    allowed = {f"defined({name})" for name in NPU_DEFINES}
    allowed.add("||".join(f"defined({name})" for name in NPU_DEFINES))
    for line in body.splitlines():
        directive = line.strip()
        if directive.startswith("#if "):
            if condition is not None or compact(directive[4:]) not in allowed:
                raise ValueError("HP boot optional NPU condition changed")
            condition = compact(directive[4:])
            current = []
        elif directive == "#endif":
            if condition is None:
                raise ValueError("unmatched HP boot preprocessor condition")
            blocks.append((condition, "\n".join(current)))
            condition = None
        elif directive.startswith("#"):
            raise ValueError("unreviewed HP boot preprocessor branch")
        elif condition is None:
            unconditional.append(line)
        else:
            current.append(line)
    if condition is not None:
        raise ValueError("unterminated HP boot optional NPU condition")
    return "\n".join(unconditional), blocks


def validate_cache_handoff(source: str, main: str, function_body: Callable[[str, str], str]) -> None:
    """Bind success to the complete positive cache/held branch, not call presence."""
    # Progress-only prints may change without changing the acceptance contract.
    without_progress = re.sub(r'\bprintf\("(?:\\.|[^"\\])*"\);', "", main)
    success_branch = compact("""
        if (rs_hp_boot_wait_cache_request()) {
            if (rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_CACHE_EVENT, RS_HP_BOOT_GA2D_CACHE_ARG,
                                       RS_HP_BOOT_MAILBOX_CACHE_SEQUENCE)) {
                if (rs_resource_acknowledge_cache_clean() == RS_OK) {
                    if (rs_hp_boot_wait_hp_held()) {
                        cache_clean_completed = true;
                    }
                }
            }
        }
    """)
    if without_progress.count(success_branch) != 1:
        raise ValueError("HP boot positive cache-handoff success guards changed")

    expected_request = compact("""
        rs_resource_cache_status_t cache_status;
        for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
            if (rs_resource_get_cache_status(&cache_status) != RS_OK) {
                return false;
            }
            if (cache_status.request && !cache_status.clean) {
                return true;
            }
        }
        return false;
    """)
    if compact(function_body(source, "rs_hp_boot_wait_cache_request")) != expected_request:
        raise ValueError("HP boot cache request/clean observation changed")

    held, gated = split_npu_conditions(function_body(source, "rs_hp_boot_wait_hp_held"))
    expected_held = compact("""
        rs_sysctrl_hp_status_t hp_status;
        for (uint32_t timeout = 0U; timeout < RS_HP_BOOT_EVENT_TIMEOUT; ++timeout) {
            if ((rs_sysctrl_get_hp_status(&hp_status) == RS_OK) && hp_status.reset_asserted &&
                !hp_status.released && !hp_status.draining && !hp_status.forced_fault &&
                rs_hp_boot_ga2d_idle(RS_RESOURCE_OWNER_HP)) {
                return true;
            }
        }
        return false;
    """)
    expected_npu_condition = "||".join(f"defined({name})" for name in NPU_DEFINES)
    if compact(held) != expected_held:
        raise ValueError("HP boot held-state reset/release/drain/fault or safe-idle condition changed")
    if [(condition, compact(body)) for condition, body in gated] != [
            (expected_npu_condition, "&&rs_hp_boot_npu_idle(RS_RESOURCE_OWNER_HP)")]:
        raise ValueError("HP boot held-state NPU safe-idle condition changed")

    expected_ga2d_idle = compact("""
        rs_ga2d_capability_t capability;
        rs_ga2d_status_t ga2d_status;
        rs_resource_status_t resource_status;
        return (rs_ga2d_get_capability(&capability) == RS_OK) &&
               (capability.features == RS_GA2D_CAPABILITY_P5) &&
               (capability.limits == RS_GA2D_LIMITS_P5) &&
               (capability.formats == RS_GA2D_FORMAT_CAPABILITY_P5) &&
               (rs_ga2d_get_status(&ga2d_status) == RS_OK) && !ga2d_status.busy &&
               !ga2d_status.draining && !ga2d_status.error && !ga2d_status.aborted &&
               !ga2d_status.recovery_required && ga2d_status.data_ready &&
               (rs_resource_get_status(RS_RESOURCE_GA2D, &resource_status) == RS_OK) &&
               (resource_status.owner == expected_owner) && resource_status.idle &&
               !resource_status.fault && !resource_status.blocked && !resource_status.quiesced &&
               !resource_status.in_reset;
    """)
    expected_npu_idle = compact("""
        rs_npu_status_t npu_status;
        rs_resource_status_t resource_status;
        return (rs_npu_get_status(&npu_status) == RS_OK) &&
               ((npu_status.flags &
                 (RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING | RS_NPU_STATUS_RECOVERING)) == 0U) &&
               (rs_resource_get_status(RS_RESOURCE_NPU, &resource_status) == RS_OK) &&
               (resource_status.owner == expected_owner) && resource_status.idle &&
               !resource_status.fault && !resource_status.blocked && !resource_status.quiesced &&
               !resource_status.in_reset;
    """)
    for name, expected in (("ga2d", expected_ga2d_idle), ("npu", expected_npu_idle)):
        if compact(function_body(source, f"rs_hp_boot_{name}_idle")) != expected:
            raise ValueError(f"HP boot {name} safe-idle predicate changed")


def collect_boot_acceptance(root: Path, function_body: Callable[[str, str], str]) -> dict:
    source = (root / BOOT_SOURCE).read_text(encoding="utf-8")
    status = (root / STATUS_SOURCE).read_text(encoding="utf-8")
    default = re.findall(r"^#define\s+RS_TIMEOUT_DEFAULT\s+\(\(rs_timeout_t\)(\d+)U\)\s*$", status, re.M)
    multiplier = re.findall(r"^#define\s+RS_HP_BOOT_EVENT_TIMEOUT\s+"
                            r"\(RS_TIMEOUT_DEFAULT\s*\*\s*UINT32_C\((\d+)\)\)\s*$", source, re.M)
    if len(default) != 1 or len(multiplier) != 1:
        raise ValueError("HP boot polling budget expression changed")
    iterations = int(default[0]) * int(multiplier[0])
    if iterations < 1 or iterations > 0xFFFFFFFF:
        raise ValueError("HP boot polling budget is not a positive uint32 bound")
    for name, bound in (
        ("sdram", "RS_TIMEOUT_DEFAULT"), ("ga2d_idle", "RS_HP_BOOT_EVENT_TIMEOUT"),
        ("npu_idle", "RS_HP_BOOT_EVENT_TIMEOUT"), ("message", "RS_HP_BOOT_EVENT_TIMEOUT"),
        ("cache_request", "RS_HP_BOOT_EVENT_TIMEOUT"), ("hp_held", "RS_HP_BOOT_EVENT_TIMEOUT"),
    ):
        body = compact(function_body(source, f"rs_hp_boot_wait_{name}"))
        loop = rf"for\((?:uint32_t)?timeout=0U;timeout<{bound};\+\+timeout\)"
        if len(re.findall(loop, body)) != 1 or body.count("for(") != 1:
            raise ValueError(f"HP boot {name} wait is no longer the reviewed bounded poll")
        if not body.endswith("returnfalse;") or "while(" in body or "do{" in body:
            raise ValueError(f"HP boot {name} wait termination changed")
    wait_body = compact(function_body(source, "rs_hp_boot_wait_message"))
    if ("if(message.sequence==sequence){return(message.code==code)&&(message.argument==argument);}" not in wait_body
            or "if(rs_hp_mailbox_receive_from_hp(&message)!=RS_OK){returnfalse;}" not in wait_body):
        raise ValueError("HP boot mailbox token/error matching changed")
    main, gated = split_npu_conditions(function_body(source, "main"))
    main = compact(main)
    phases = (
        "rs_hp_boot_read_header(&header);",
        "rs_hp_boot_dma_copy_entry(&header.entries[index])",
        "rs_resource_set_owner(RS_RESOURCE_GA2D,RS_RESOURCE_OWNER_HP,false)",
        "s_hp_boot_ga2d_owned_by_hp=true;",
        "rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_HP)",
        "rs_sysctrl_set_hp_release(true)",
        "rs_hp_boot_wait_message(RS_HP_BOOT_READY_EVENT,RS_HP_BOOT_READY_ARG,RS_HP_BOOT_MAILBOX_READY_SEQUENCE)",
        "message.code=RS_HP_BOOT_GA2D_START_COMMAND;",
        "rs_hp_mailbox_send_to_hp(&message)",
        "rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_PASS_EVENT,RS_HP_BOOT_GA2D_PASS_ARG,RS_HP_BOOT_MAILBOX_RESULT_SEQUENCE)",
        "release_status=rs_sysctrl_set_hp_release(false);",
        "rs_hp_boot_wait_cache_request()",
        "rs_hp_boot_wait_message(RS_HP_BOOT_GA2D_CACHE_EVENT,RS_HP_BOOT_GA2D_CACHE_ARG,RS_HP_BOOT_MAILBOX_CACHE_SEQUENCE)",
        "rs_resource_acknowledge_cache_clean()",
        "rs_hp_boot_wait_hp_held()",
        "cache_clean_completed=true;",
        "if(!cache_clean_completed){rs_hp_boot_fail(UINT8_C(16));}",
        "rs_resource_set_owner(RS_RESOURCE_GA2D,RS_RESOURCE_OWNER_LP,false)",
        "s_hp_boot_ga2d_owned_by_hp=false;",
        "rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_LP)",
        "rs_test_finish(RS_TEST_PASSED,UINT8_C(0));",
    )
    cursor = 0
    for phase in phases:
        position = main.find(phase, cursor)
        if position < 0:
            raise ValueError(f"HP boot required phase or ordering changed: {phase}")
        cursor = position + len(phase)
    if (main.count("rs_test_finish(RS_TEST_PASSED,") != 1 or not main.endswith(phases[-1])
            or re.findall(r"cache_clean_completed=(true|false);", main) != ["false", "true"]
            or re.findall(r"s_hp_boot_ga2d_owned_by_hp=(true|false);", main) != ["true", "false"]):
        raise ValueError("HP boot terminal pass or cache completion changed")
    validate_cache_handoff(source, main, function_body)
    for condition, code in (
        ("!" + phases[6], 11),
        (phases[8] + "!=RS_OK", 12),
        ("!" + phases[9], 13),
        ("!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_HP)", 14),
        (phases[17] + "!=RS_OK", 17),
        ("!rs_hp_boot_wait_ga2d_idle(RS_RESOURCE_OWNER_LP)", 17),
    ):
        if f"if({condition}){{rs_hp_boot_fail(UINT8_C({code}));}}" not in main:
            raise ValueError("HP boot required completion condition changed")
    npu_condition = "||".join(f"defined({name})" for name in NPU_DEFINES)
    npu_blocks = compact("\n".join(body for condition, body in gated if condition == npu_condition))
    for owner in ("HP", "LP"):
        operation = f"rs_resource_set_owner(RS_RESOURCE_NPU,RS_RESOURCE_OWNER_{owner},false)"
        if operation not in npu_blocks or operation in main:
            raise ValueError("HP boot NPU ownership is no longer acceptance-conditional")
    fail = compact(function_body(source, "rs_hp_boot_fail"))
    guard = "if(!s_hp_boot_ga2d_owned_by_hp){(void)rs_sysctrl_set_hp_release(false);}"
    if (not fail.startswith(guard) or fail.count("rs_sysctrl_set_hp_release(") != 1
            or not fail.endswith("rs_test_finish(RS_TEST_FAILED,code);")):
        raise ValueError("HP boot failure reset ownership guard changed")
    ready_writes = ready_mailbox(root)
    constants = uint_constants(source)
    messages = []
    for title, event, argument, sequence in (
        ("Initial ready", "READY_EVENT", "READY_ARG", "MAILBOX_READY_SEQUENCE"),
        ("GA2D acceptance result", "GA2D_PASS_EVENT", "GA2D_PASS_ARG", "MAILBOX_RESULT_SEQUENCE"),
        ("Cache-clean acknowledgement", "GA2D_CACHE_EVENT", "GA2D_CACHE_ARG", "MAILBOX_CACHE_SEQUENCE"),
    ):
        messages.append({"title": title, "event": constants[f"RS_HP_BOOT_{event}"],
                         "argument": constants[f"RS_HP_BOOT_{argument}"],
                         "sequence": constants[f"RS_HP_BOOT_{sequence}"]})
    return {"default_poll_iterations": int(default[0]), "event_poll_multiplier": int(multiplier[0]),
            "event_poll_iterations": iterations, "npu_defines": list(NPU_DEFINES),
            "messages": messages, "ready_writes": ready_writes,
            "rootfs_ready_only": True, "terminal_requires_cache_handoff": True,
            "failure_reset_requires_no_hp_ga2d_owner": True}
