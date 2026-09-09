"""Cross-check published API behavior and byte-format tables against existing code."""
from __future__ import annotations

import copy
import json
import os
import re
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest

from publications import api_bundle_reference as ab
from publications.software_reference import function_body

ROOT = Path(__file__).resolve().parents[1]
SPEC = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))["software"]


def test_all_published_api_outcomes_are_bound_to_actual_functions():
    result = ab.validate_api(ROOT, SPEC["api_semantics"], function_body)
    assert (result["timeout_bits"], result["default_budget"]) == (32, 1000000)
    assert len(result["rows"]) == 10


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "digest", "recovery"])
def test_api_inventory_rejects_missing_or_unreviewed_semantics(mutation):
    rows = copy.deepcopy(SPEC["api_semantics"])
    if mutation == "missing":
        rows.pop()
    elif mutation == "duplicate":
        rows.append(rows[0])
    elif mutation == "digest":
        rows[0]["body_sha256"] = "0" * 64
    else:
        rows[0]["next"] = ""
    with pytest.raises(ValueError):
        ab.validate_api(ROOT, rows, function_body)


def test_semantic_digest_preserves_string_literal_bytes():
    assert ab.body_digest('return  RS_OK;') == ab.body_digest('return RS_OK;')
    assert ab.body_digest('log("a b");') != ab.body_digest('log("ab");')


def test_bundle_tables_and_example_match_actual_packager_output():
    data = ab.bundle_layout(ROOT, SPEC["boot_bundle"], function_body)
    assert (data["fixed_header_bytes"], data["entry_bytes"], data["header_bytes"], data["entry_count"]) == (32, 24, 128, 4)
    assert [f["offset"] for f in data["header_fields"]] == list(range(0, 32, 4))
    assert [f["offset"] for f in data["entry_fields"]] == list(range(0, 24, 4))
    entries = data["example"]["entries"]
    assert [e["descriptor_offset"] for e in entries] == [32, 56, 80, 104]
    assert [e["flash_offset"] for e in entries] == [0x101000, 0x102000, 0x103000, 0x104000]
    assert [e["size"] for e in entries] == [32, 33, 34, 35]
    for number, row in enumerate(entries, 1):
        assert row["crc32"] == zlib.crc32(bytes([number]) * (31 + number)) & 0xFFFFFFFF
    assert data["example"]["header"]["total_size"] == 0x5000
    assert data["example"]["image_bytes"] == 0x105000
    raw = bytearray.fromhex(data["example"]["header_hex"])
    assert raw[:4] == b"RSHP"
    crc = int.from_bytes(raw[20:24], "little")
    raw[20:24] = bytes(4)
    assert zlib.crc32(raw) & 0xFFFFFFFF == crc


@pytest.mark.parametrize("mutation", ["field-order", "field-name", "loader-digest"])
def test_bundle_metadata_cannot_silently_change_format_or_acceptance(mutation):
    spec = copy.deepcopy(SPEC["boot_bundle"])
    if mutation == "field-order":
        spec["header_fields"] = dict(reversed(list(spec["header_fields"].items())))
    elif mutation == "field-name":
        spec["entry_fields"]["unknown"] = "Unreviewed field"
    else:
        spec["loader_bindings"][0]["body_sha256"] = "0" * 64
    with pytest.raises(ValueError):
        ab.bundle_layout(ROOT, spec, function_body)


def test_c_structure_parser_rejects_an_array_before_header_fields():
    source = 'typedef struct {rs_hp_boot_entry_t entries[RS_HP_BOOT_BUNDLE_ENTRY_COUNT]; uint32_t magic;} rs_hp_boot_header_t;'
    with pytest.raises(ValueError, match="member type or order"):
        ab.c_members(source, "rs_hp_boot_header_t")


HARNESS = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/timer.h>
#include "hp_boot_bundle.h"

#define RS_SOC_FLASH_SIZE UINT32_C(0x01000000)
#define RS_SOC_SDRAM_BASE UINT32_C(0x38000000)
#define RS_SOC_SDRAM_SIZE UINT32_C(0x04000000)

static uint32_t tx[8], tx_count, tx_limit = 8, rx_count, rx_available, uart_polls;
static uint32_t fake_uart_status(void) {
    ++uart_polls;
    return (tx_count >= tx_limit ? RS_UART_STATUS_TX_FULL : 0U) |
           (rx_count >= rx_available ? RS_UART_STATUS_RX_EMPTY : 0U);
}
static uint32_t *fake_tx(void) { return &tx[tx_count++]; }
static uint32_t fake_rx(void) { ++rx_count; return UINT32_C(0x341); }
#define RS_UART_STATUS fake_uart_status()
#define RS_UART_TXDATA (*fake_tx())
#define RS_UART_RXDATA fake_rx()

static uint32_t dma_words[8][32], dma_status_reads;
static volatile uint32_t *fake_dma_reg(uint32_t channel, uint32_t offset) {
    if (offset == RS_DMA_CH_REG_STATUS) ++dma_status_reads;
    return &dma_words[channel][offset / 4U];
}
#undef RS_DMA_CH_REG
#define RS_DMA_CH_REG(channel,offset) (*fake_dma_reg(channel,offset))

static uint32_t timer_words[2][16], timer_control_visits, timer_status_reads;
static bool timer_completed;
static volatile uint32_t *rs_timer_register(rs_timer_id_t timer, uint32_t offset) {
    if (offset == RS_TIMER_CTRL_OFFSET) ++timer_control_visits;
    if (offset == RS_TIMER_STATUS_OFFSET) {
        ++timer_status_reads;
        timer_words[timer][offset/4U] = timer_completed ? 0U : RS_TIMER_STATUS_ACTIVE_MASK;
    }
    return &timer_words[timer][offset/4U];
}
static rs_status_t rs_clock_get_active_hz(uint32_t *hz) { *hz = 72000000U; return RS_OK; }

/* REAL_FUNCTIONS */

int main(int argc, char **argv) {
    assert(argc >= 2);
    int scenario = atoi(argv[1]);
    volatile uint32_t word = 5U;
    uint8_t bytes[] = {0x11,0x22,0x33};
    rs_uart_rx_data_t received[2] = {{0xEE,0xEE},{0xEE,0xEE}};
    uint32_t *ctrl = &dma_words[0][RS_DMA_CH_REG_CTRL/4U];
    uint32_t *status = &dma_words[0][RS_DMA_CH_REG_STATUS/4U];
    switch (scenario) {
    case 0:
        assert(rs_wait_mask(NULL,1,0,1)==RS_EINVAL);
        assert(rs_wait_mask(&word,0,0,1)==RS_EINVAL);
        assert(rs_wait_value(NULL,0,1)==RS_EINVAL);
        assert(rs_wait_not_value(NULL,0,1)==RS_EINVAL); break;
    case 1:
        assert(rs_wait_mask(&word,7,5,0)==RS_ETIMEOUT);
        assert(rs_wait_value(&word,5,0)==RS_ETIMEOUT);
        assert(rs_wait_not_value(&word,0,0)==RS_ETIMEOUT); break;
    case 2:
        assert(rs_wait_mask(&word,7,5,1)==RS_OK);
        assert(rs_wait_value(&word,5,1)==RS_OK);
        assert(rs_wait_not_value(&word,0,1)==RS_OK); break;
    case 3:
        assert(rs_wait_mask(&word,7,0,2)==RS_ETIMEOUT);
        assert(rs_wait_value(&word,0,2)==RS_ETIMEOUT);
        assert(rs_wait_not_value(&word,5,2)==RS_ETIMEOUT); break;
    case 4:
        assert(rs_uart_write(bytes,2,0)==RS_OK);
        assert(tx_count==2 && tx[1]==0x22 && uart_polls==2); break;
    case 5:
        tx_limit=1; assert(rs_uart_write(bytes,3,2)==RS_ETIMEOUT);
        assert(tx_count==1 && tx[0]==0x11 && uart_polls==4); break;
    case 6:
        assert(rs_uart_write(NULL,0,0)==RS_OK && rs_uart_read(NULL,0,0)==RS_OK);
        assert(tx_count==0 && rx_count==0 && uart_polls==0); break;
    case 7:
        rx_available=1; assert(rs_uart_read(received,2,1)==RS_ETIMEOUT);
        assert(rx_count==1 && received[0].data==0x41 && received[0].errors==3);
        assert(received[1].data==0xEE); break;
    case 8:
        rx_available=1; assert(rs_uart_read(received,1,0)==RS_OK);
        assert(rx_count==1 && received[0].errors==3); break;
    case 9:
        assert(rs_uart_write(NULL,1,2)==RS_EINVAL && rs_uart_read(NULL,1,2)==RS_EINVAL);
        assert(uart_polls==0); break;
    case 10:
        *status=RS_DMA_STATUS_BUSY; assert(rs_dma_start(0)==RS_OK);
        assert(*ctrl==RS_DMA_CH_CTRL_START && dma_status_reads==0);
        assert(dma_words[0][RS_DMA_CH_REG_EVENT_STATUS/4U]==RS_DMA_EVENT_ALL); break;
    case 11:
        *status=RS_DMA_STATUS_BUSY; assert(rs_dma_abort(0)==RS_OK);
        assert(*ctrl==RS_DMA_CH_CTRL_ABORT && dma_status_reads==0); break;
    case 12:
        *status=RS_DMA_STATUS_DONE; assert(rs_dma_wait(0,0)==RS_ETIMEOUT);
        assert(*ctrl==0 && dma_status_reads==0); break;
    case 13:
        *status=RS_DMA_STATUS_BUSY; assert(rs_dma_wait(0,2)==RS_ETIMEOUT);
        assert(*ctrl==0 && dma_status_reads==2); break;
    case 14:
        *status=RS_DMA_STATUS_ERROR|RS_DMA_STATUS_DONE; assert(rs_dma_wait(0,1)==RS_EIO); break;
    case 15:
        *status=RS_DMA_STATUS_DONE; assert(rs_dma_wait(0,1)==RS_OK); break;
    case 16:
        assert(rs_dma_abort_wait(0,0)==RS_ETIMEOUT);
        assert(*ctrl==RS_DMA_CH_CTRL_ABORT && dma_status_reads==0); break;
    case 17:
        *status=RS_DMA_STATUS_BUSY; assert(rs_dma_abort_wait(0,2)==RS_ETIMEOUT);
        assert(*ctrl==RS_DMA_CH_CTRL_ABORT && dma_status_reads==2); break;
    case 18:
        *status=0; assert(rs_dma_abort_wait(0,1)==RS_OK);
        assert(dma_status_reads==1); break;
    case 19:
        assert(rs_timer_delay_ms(RS_TIMER_0,0,0)==RS_OK);
        assert(timer_control_visits==0 && timer_status_reads==0); break;
    case 20:
        assert(rs_timer_delay_ms(RS_TIMER_0,1,0)==RS_ETIMEOUT);
        assert(timer_control_visits==3 && timer_status_reads==0);
        assert(!(timer_words[0][0]&RS_TIMER_CTRL_ENABLE_MASK)); break;
    case 21:
        assert(rs_timer_delay_ms(RS_TIMER_0,1,2)==RS_ETIMEOUT);
        assert(timer_control_visits==3 && timer_status_reads==2); break;
    case 22:
        timer_completed=true; assert(rs_timer_delay_ms(RS_TIMER_0,1,2)==RS_OK);
        assert(timer_control_visits==2 && timer_status_reads==1); break;
    case 23:
        assert(rs_timer_delay_ms((rs_timer_id_t)2,0,0)==RS_EINVAL);
        assert(timer_control_visits==0); break;
    default: {
        assert(argc==3);
        FILE *file=fopen(argv[2],"rb"); assert(file);
        rs_hp_boot_header_t header;
        assert(fread(&header,1,sizeof(header),file)==sizeof(header)); fclose(file);
        bool expected=true;
        switch(scenario) {
        case 30: break;
        case 31: header.reserved=0x1234; header.flags|=0x80; header.entries[0].flags|=0x80; break;
        case 32: header.entries[0].flash_offset+=4; break;
        case 33: header.entries[0].flash_offset+=1; expected=false; break;
        case 34: header.entries[0].flags=0; expected=false; break;
        case 35: header.header_crc32^=1; assert(!rs_hp_boot_header_valid(&header)); return 0;
        case 36: header.entries[1].flash_offset=header.entries[0].flash_offset; break;
        case 37: header.entries[0].size=0; expected=false; break;
        case 38: header.header_size+=4; expected=false; break;
        case 39: header.entry_count=3; expected=false; break;
        default: return 2;
        }
        header.header_crc32=0;
        header.header_crc32=rs_hp_boot_crc32((const uint8_t *)&header,sizeof(header));
        assert(rs_hp_boot_header_valid(&header)==expected);
        break;
    }}
    return 0;
}
'''


def real_definition(source: str, name: str) -> str:
    body = function_body(source, name)
    signature = re.search(r"\b((?:static\s+)?(?:bool|uint32_t|rs_status_t)\s+" + re.escape(name)
                          + r"\s*\([^;{}]*\))\s*\{", source)
    assert signature is not None
    return signature[1] + " {" + body + "}\n"


@pytest.fixture(scope="module")
def c_behavior(tmp_path_factory):
    if os.name == "nt":
        pytest.skip("MMIO-substitute C fixtures run in the Linux host environment")
    cc = shutil.which("cc") or shutil.which("gcc")
    if cc is None:
        pytest.skip("host C compiler unavailable")
    folder = tmp_path_factory.mktemp("publication-api")
    generated = folder / "retrosoc/generated"
    generated.mkdir(parents=True)
    (generated / "memory_map.h").write_text("/* No hardware addresses are used by this fixture. */\n")
    (generated / "user_extensions.h").write_text("/* No extension selectors are used. */\n")
    sources = {name: (ROOT / f"crt/src/hal/{name}.c").read_text(encoding="utf-8") for name in ("uart", "dma", "timer")}
    constants = "\n".join(line for line in sources["timer"].splitlines() if line.startswith("#define RS_TIMER_"))
    constants += "\n" + "\n".join(line for line in sources["uart"].splitlines()
                                   if re.match(r"#define RS_UART_STATUS_(?:TX_FULL|RX_EMPTY)\s", line))
    extracted = ""
    selections = {
        "uart": ["rs_uart_write", "rs_uart_read"],
        "dma": ["rs_dma_channel_valid", "rs_dma_start", "rs_dma_abort", "rs_dma_get_status", "rs_dma_abort_wait", "rs_dma_wait"],
        "timer": ["rs_timer_id_valid", "rs_timer_ctrl_from_config", "rs_timer_config_valid", "rs_timer_configure", "rs_timer_start", "rs_timer_stop", "rs_timer_delay_ms"],
    }
    for family, names in selections.items():
        extracted += "\n".join(real_definition(sources[family], name) for name in names)
    boot = (ROOT / "app/apps/hp_boot/main.c").read_text(encoding="utf-8")
    extracted += "\n".join(real_definition(boot, row["function"]) for row in SPEC["boot_bundle"]["loader_bindings"])
    source = folder / "behavior.c"
    source.write_text(constants + "\n" + HARNESS.replace("/* REAL_FUNCTIONS */", extracted), encoding="utf-8")
    exe = folder / "behavior"
    subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "crt/include"),
                    "-I", str(ROOT / "app/apps/hp_boot"), "-I", str(folder), str(source),
                    str(ROOT / "crt/src/hal/timer_math.c"), "-o", str(exe)], check=True, capture_output=True, text=True)
    layout = ab.bundle_layout(ROOT, SPEC["boot_bundle"], function_body)
    header = folder / "synthetic-header.bin"
    header.write_bytes(bytes.fromhex(layout["example"]["header_hex"]))
    return exe, header


@pytest.mark.parametrize("scenario", [*range(24), *range(30, 40)])
def test_existing_c_behavior_with_memory_backed_registers(c_behavior, scenario):
    exe, header = c_behavior
    subprocess.run([str(exe), str(scenario), str(header)], check=True, capture_output=True, text=True)
