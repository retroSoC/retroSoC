"""Independent frozen PIO-lite APB1.0/ISA1.0 handwritten mirror checks."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
GLOBALS = {
    "IP_ID": 0x000, "IP_VERSION": 0x004, "ISA_VERSION": 0x008,
    "CAPABILITY": 0x00C, "ROUTABLE_MASK": 0x010, "CLOCK_HZ": 0x014,
    "FLAGS": 0x018, "FLAG_SET": 0x01C, "FLAG_CLEAR": 0x020,
    "IRQ_STATUS": 0x024, "IRQ_ENABLE": 0x028, "TX_BIND": 0x02C,
    "RX_BIND": 0x030, "TRANSPORT_STATUS": 0x034, "IMEM_VALID": 0x038,
    "OWNED_MASK": 0x03C, "START": 0x040, "PAUSE": 0x044, "RESUME": 0x048,
    "DISABLE": 0x04C, "ABORT": 0x050, "SM_RESET": 0x054, "BLOCK_RESET": 0x058,
}
SM_REGISTERS = {
    name: index * 4 for index, name in enumerate(
        "STATUS CONFIG DIV PROGRAM WRAP IN_PINS OUT_PINS SET_PINS CLAIM_MASK OUTPUT_MASK "
        "INITIAL_VALUE INITIAL_OE INITIAL_XY SHIFT_LIMITS TEST_SELECT WATERMARKS TXDATA "
        "RXDATA FIFO_LEVELS EVENTS EVENT_ENABLE FAULT PC ISR OSR XY SHIFT_COUNTS "
        "TICK_COUNT TX_STALL_COUNT RX_STALL_COUNT RETIRED_COUNT EXEC_PHASE".split()
    )
}


def _mirrors():
    sv = (ROOT / "rtl/ip/piolite/piolite_define.svh").read_text()
    header = (ROOT / "crt/include/retrosoc/hal/piolite_regs.h").read_text()
    rtl = {}
    pattern = r"^`define\s+(APB4_PIOLITE__|PIOLITE_)(\w+)\s+(?:(\d+)'h([0-9a-f]+)|(\d+))\s*$"
    for prefix, name, width, hexadecimal, decimal in re.findall(pattern, sv, re.M):
        key = ("APB4_" if prefix.startswith("APB4") else "") + name
        assert key not in rtl
        rtl[key] = int(hexadecimal, 16) if width else int(decimal)
    c = {
        name: int(hexadecimal, 16) if hexadecimal else int(decimal)
        for name, hexadecimal, decimal in re.findall(
            r"^#define\s+RS_PIOLITE_ABI_(\w+)\s+"
            r"(?:UINT32_C\(0x([0-9a-f]+)\)|(\d+)U)\s*$", header, re.M
        )
    }
    return rtl, c, header


def test_exact_svh_c_dictionary_and_frozen_matrix():
    rtl, c, _ = _mirrors()
    assert rtl == c
    for name, offset in GLOBALS.items():
        assert rtl["APB4_" + name] == offset
    for name, offset in SM_REGISTERS.items():
        assert rtl["APB4_SM_" + name] == offset
    assert rtl["APB4_SM0_BASE"] == 0x200
    assert rtl["APB4_SM1_BASE"] == 0x280
    assert rtl["APB4_SM_STRIDE"] == 0x80
    assert rtl["APB4_IMEM_BASE"] == 0x100
    assert rtl["APB4_IMEM_END"] == 0x17C
    assert rtl["APB4_IMEM_WORDS"] == 32
    assert rtl["APB4_IMEM_WORD_STRIDE"] == 4
    matrix = list(GLOBALS.values())
    matrix += [0x100 + index * 4 for index in range(32)]
    matrix += [base + offset for base in (0x200, 0x280) for offset in SM_REGISTERS.values()]
    assert len(matrix) == len(set(matrix)) == 119
    assert sorted(matrix) == sorted(GLOBALS.values()) + sorted(set(matrix) - set(GLOBALS.values()))


def test_independent_resets_fields_and_isa_enums():
    rtl, _, header = _mirrors()
    assert rtl["APB4_ID_VALUE"] == 0x50494F4C
    assert rtl["APB4_VERSION_VALUE"] == rtl["APB4_ISA_VALUE"] == 0x00010000
    assert rtl["APB4_CAPABILITY_VALUE"] == 0x08082002
    assert rtl["APB4_ROUTES_VALUE"] == 0xFFFFFFFF
    assert rtl["APB4_DIV_RESET"] == 1
    assert rtl["APB4_SHIFT_LIMITS_RESET"] == 0x2020
    assert rtl["APB4_WATERMARKS_RESET"] == 0x100
    assert rtl["APB4_IRQ_MASK"] == 0x03030F03
    fields = {
        "STATUS_STATE": 0, "STATUS_STALL": 4, "STATUS_LAST_FIFO_FAILED": 8,
        "PROGRAM_BASE": 0, "PROGRAM_LEN": 8, "PROGRAM_ENTRY": 16,
        "WRAP_BOTTOM": 0, "WRAP_TOP": 8, "SHIFT_LIMITS_TX_BITS": 0,
        "SHIFT_LIMITS_RX_BITS": 8, "WATERMARKS_TX_LOW": 0,
        "WATERMARKS_RX_HIGH": 8, "FAULT_CODE": 0, "FAULT_PC": 8,
        "SHIFT_COUNTS_ISR": 0, "SHIFT_COUNTS_OSR": 8,
        "EXEC_PHASE_DIV": 0, "EXEC_PHASE_DELAY": 16,
        "TX_BIND_SM": 0, "TX_BIND_CHANNEL": 8, "TX_BIND_ENABLE": 31,
        "RX_BIND_SM": 0, "RX_BIND_CHANNEL": 8, "RX_BIND_ENABLE": 31,
        "IRQ_STATUS_SM0": 0, "IRQ_STATUS_SM1": 1, "IRQ_STATUS_FLAGS": 8,
        "IRQ_STATUS_TX_LEVEL": 16, "IRQ_STATUS_RX_LEVEL": 24,
    }
    for name, bit in fields.items():
        assert rtl[name] == bit
    for index, name in enumerate("AUTOPULL AUTOPUSH TX_RIGHT RX_RIGHT TEST_PIN_ENABLE".split()):
        assert rtl["CONFIG_" + name] == index
    for index, name in enumerate("HALT ABORT FAULT TX_STALL RX_STALL FIFO_FAIL".split()):
        assert rtl["EVENTS_" + name] == rtl["EVENT_ENABLE_" + name] == index
    expected = {}
    expected.update({f"OPCODE_{name}": value for value, name in enumerate(
        "CTRL SET_PIN SET_DIR SET_COUNT IN OUT MOVE FIFO WAIT BRANCH FLAG".split())})
    expected.update({f"CTRL_{name}": value for value, name in enumerate(
        "NOP HALT CLEAR_ISR CLEAR_OSR".split())})
    expected.update({f"IN_{name}": value for value, name in enumerate("PINS X Y ZERO".split())})
    expected.update({f"OUT_{name}": value for value, name in enumerate(
        "PINS DIRECTIONS X Y DISCARD".split())})
    expected.update({f"MOVE_{name}": value for value, name in enumerate(
        "ISR OSR X Y ZERO ONES".split())})
    expected.update({"FIFO_PULL": 0, "FIFO_PUSH": 1, "FIFO_NONBLOCKING": 0, "FIFO_BLOCKING": 1})
    expected.update({"WAIT_PIN": 0, "WAIT_FLAG": 1, "FLAG_CLEAR": 0, "FLAG_SET": 1})
    expected.update({f"BRANCH_{name}": value for value, name in enumerate(
        "ALWAYS X_ZERO Y_ZERO DEC_X_NONZERO DEC_Y_NONZERO TEST_PIN_HIGH "
        "FIFO_FAILED TEST_FLAG_SET".split())})
    for name, value in expected.items():
        assert rtl[name] == value
    c_enums = {
        name: int(value) for name, value in re.findall(
            r"\b(RS_PIOLITE_(?:OPCODE|CTRL|IN|OUT|MOVE|FIFO|WAIT|FLAG|BRANCH)_\w+)"
            r"\s*=\s*(\d+)(?=\s*[,}])",
            header
        )
    }
    assert c_enums == {"RS_PIOLITE_" + name: value for name, value in expected.items()}


def test_p2_has_no_product_or_hal_integration():
    assert not (ROOT / "crt/include/retrosoc/hal/piolite.h").exists()
    for profile in ("ics55-tiny.mk", "ihp130-tiny.mk"):
        assert "PIOLITE" not in (ROOT / "configs/ci" / profile).read_text().upper()
    assert all("/piolite/" not in path.read_text() for path in (ROOT / "rtl/tiny/filelist").glob("*.fl"))
