"""Independent frozen SPI APB 1.0 constants and handwritten mirror checks."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REGISTERS = """IP_ID IP_VERSION CAPABILITY FIFO_CAPABILITY CLOCK_HZ ROUTABLE_MASK
COMMAND STATUS SESSION_CFG DIV CS_SETUP CS_HOLD CS_INACTIVE SEG_CONFIG FRAME_COUNT
DUMMY TX_BIND RX_BIND WATERMARKS CPU_TXDATA CPU_RXDATA DMA_TXDATA DMA_RXDATA
FIFO_LEVELS IRQ_STATE IRQ_ENABLE IRQ_STATUS FAULT_CODE FAULT_FRAME FRAMES_DONE
TRANSPORT_WORDS TX_WORDS_ACCEPTED RX_WORDS_PRODUCED RX_WORDS_REMOVED TX_STALL_CYCLES
RX_STALL_CYCLES SESSION_PINS DMA_STATUS PINS_READY PAYLOAD_BYTES""".split()


def test_frozen_spi_register_mirrors():
    sv = (ROOT / "rtl/ip/serial/spi_define.svh").read_text()
    header = (ROOT / "crt/include/retrosoc/hal/spi_regs.h").read_text()
    rtl = {}
    for name, width, hexadecimal, decimal in re.findall(
            r"^`define\s+APB4_SPI__(\w+)\s+(?:(\d+)'h([0-9a-f]+)|(\d+))\s*$", sv, re.M):
        rtl[name] = int(hexadecimal, 16) if width else int(decimal)
    c = {name: int(hexa, 16) if hexa else int(decimal)
         for name, hexa, decimal in re.findall(
             r"^#define\s+RS_SPI_ABI_(\w+)\s+(?:UINT32_C\((0x[0-9a-f]+)\)|(\d+)U)\s*$", header, re.M)}
    assert rtl == c
    assert {name: rtl[name] for name in REGISTERS} == {
        name: index * 4 for index, name in enumerate(REGISTERS)}
    assert rtl['ID_VALUE'] == 0x53504930
    assert rtl['VERSION_VALUE'] == 0x10000
    assert rtl['CAPABILITY_VALUE'] == 0x3f7f
    assert rtl['FIFO_VALUE'] == 0x200808
    assert rtl['ROUTES_VALUE'] == 0xd8000000
    for bit, name in enumerate('ENABLE DISABLE ARM START END ABORT RECOVER RELEASE RESET'.split()):
        assert rtl[name] == bit
    assert rtl['TIMING_RESET'] == 1 and rtl['DUMMY_RESET'] == 0xffff
    assert rtl['WATERMARK_RESET'] == 0x100
    for bit, name in enumerate('CPOL CPHA LSB_FIRST MISO_ENABLE DISPLAY_DC'.split()):
        assert rtl[name] == bit
    for number, name in enumerate('DISABLED IDLE ARMED SETUP SHIFT HOLD HELD GAP CLOSING'.split()):
        assert rtl['STATE_' + name] == number
    for number, name in enumerate('NONE ROUTE READINESS DMA CREDIT QUOTA'.split()):
        assert rtl['FAULT_' + name] == number
    for bit, name in enumerate('SEGMENT_DONE DONE ABORTED FAULT TX_STALL RX_STALL'.split()):
        assert rtl['IRQ_' + name] == bit
    for bit, name in enumerate(('CS_ACTIVE SESSION_OWNED SEGMENT_PENDING SEGMENT_CLEAN '
                               'TX_WAIT RX_WAIT BUS_IDLE TRANSPORT_IDLE GPIO_READY').split(), 4):
        assert rtl['STATUS_' + name] == bit
    assert [rtl[name] for name in ('TX_ONLY', 'FULL_DUPLEX', 'RX_ONLY')] == [0, 1, 2]
    assert [rtl[name] for name in ('FRAME16', 'DIRECTION', 'HOLD_CS', 'BIND_ENABLE')] == [0, 1, 3, 31]
    assert rtl['IRQ_TX_LEVEL'] == 8 and rtl['IRQ_RX_LEVEL'] == 9


def test_spi_is_advertised_only_by_tiny_product_integration():
    assert any('/serial/apb4_spi.sv' in path.read_text()
               for path in (ROOT / 'rtl/tiny/filelist').glob('*.fl'))
    assert all('/serial/apb4_spi.sv' not in path.read_text()
               for path in (ROOT / 'rtl/mini/filelist').glob('*.fl'))
    assert 'spi' in [row['name'] for row in __import__('json').loads(
        (ROOT / 'rtl/tiny/integration/soc_topology.json').read_text())['apb_targets']]
