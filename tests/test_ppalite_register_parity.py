"""Independent PPALite APB1.0 handwritten mirror and standalone boundary."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
NAMES = """IP_ID IP_VERSION CAPABILITY BUFFER_CAPABILITY CLOCK_HZ ROUTE COMMAND STATUS CONFIG
INPUT_SIZE SAMPLING DMA_BINDING DESTINATION CAPACITY_BYTES OUTPUT_SIZE ROW_BYTES STRIDE_BYTES
VALID_BYTES TRANSPORT_BYTES EXPECTED_WORDS JOB_SEQUENCE SOURCE_SEQUENCE INPUT_WORDS INPUT_PIXELS
INPUT_LINES SELECTED_PIXELS OUTPUT_WORDS OUTPUT_LINES INPUT_STALL_CYCLES OUTPUT_STALL_CYCLES
FIFO_LEVELS IRQ_STATE IRQ_ENABLE IRQ_STATUS FIRST_ERROR ERROR_POSITION SOURCE_ERROR DMA_ERROR
RESULT_CONFIG SOURCE_GEOMETRY""".split()


def mirrors():
    rtl_text = (ROOT / "rtl/ip/ppalite/ppalite_define.svh").read_text()
    header = (ROOT / "crt/include/retrosoc/hal/ppalite_regs.h").read_text()
    rtl = {}
    for prefix, name, width, hexadecimal, decimal in re.findall(
            r"^`define\s+(APB4_PPALITE__|PPALITE_)(\w+)\s+(?:(\d+)'h([0-9a-f]+)|(\d+))\s*$",
            rtl_text, re.M):
        key = ("APB4_" if prefix.startswith("APB4") else "") + name
        assert key not in rtl
        rtl[key] = int(hexadecimal, 16) if width else int(decimal)
    c = {name: int(hexadecimal, 16) if hexadecimal else int(decimal)
         for name, hexadecimal, decimal in re.findall(
             r"^#define\s+RS_PPALITE_ABI_(\w+)\s+"
             r"(?:UINT32_C\(0x([0-9a-f]+)\)|(\d+)U)\s*$", header, re.M)}
    return rtl, c


def test_exact_dictionary_offsets_and_values():
    rtl, c = mirrors()
    assert rtl == c
    assert {name: rtl["APB4_" + name] for name in NAMES} == {
        name: index * 4 for index, name in enumerate(NAMES)}
    assert len(NAMES) == 40
    assert rtl["APB4_ID_VALUE"] == 0x5050414C
    assert rtl["APB4_VERSION_VALUE"] == 0x00010000
    assert rtl["APB4_CAPABILITY_VALUE"] == 0xFF
    assert rtl["APB4_CAPABILITY_VALUE"] & 0x300 == 0
    assert rtl["APB4_BUFFER_VALUE"] == (32 << 16) | (8 << 8) | 2
    assert rtl["APB4_DMA_BINDING_VALUE"] == (1 << 16) | (11 << 8) | 2
    assert rtl["APB4_IRQ_MASK"] == 0x1F
    for index, name in enumerate("ARM FINALIZE RELEASE ABORT RECOVER RESET".split()):
        assert rtl["COMMAND_" + name] == index
    for index, name in enumerate("IDLE ARMED RUNNING DRAINING VERIFY COMPLETE CLOSING".split()):
        assert rtl["STATE_" + name] == index


def test_no_product_integration_or_hal_is_advertised():
    assert not (ROOT / "crt/include/retrosoc/hal/ppalite.h").exists()
    assert not (ROOT / "crt/src/hal/ppalite.c").exists()
    for profile in ("ics55-tiny.mk", "ihp130-tiny.mk"):
        assert "PPALITE" not in (ROOT / "configs/ci" / profile).read_text().upper()
    assert all("/ppalite/" not in path.read_text() for path in (ROOT / "rtl/tiny/filelist").glob("*.fl"))
