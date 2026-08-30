# AXI4 SDRAM Controller

The Mini SoC SDRAM block exposes a 64 MiB AXI4 data window and a separate APB4
management window. It is a fixed-geometry 16-bit SDR SDRAM controller with a
native-burst frontend, per-bank open-row tracking, and programmable JEDEC
timings expressed in SDRAM-clock cycles.

## Scope and Integration

| Property | Value |
| --- | --- |
| AXI4 data window | `0x38000000` - `0x3BFFFFFF` |
| Data window size | 64 MiB |
| APB4 configuration window | `0x1000D000` - `0x1000DFFF` |
| SoC data boundary | 64-bit AXI/ID6 from HP into the stable memory domain |
| Controller frontend | local 64-to-32 adaptation, then 32-bit AXI over SDRAM x16 |
| Address organization | 2-bit bank, 13-bit row, 10-bit column |
| Physical interface | `sdram_if` (`BA[1:0]`, `A[12:0]`, `DQ[15:0]`) |
| Clocking | One edge updates control/data; the opposite edge samples |

Configuration requests cross PCLK into the stable memory domain through the
timed `sdram_cfg` APB4 port exported by `apb4_periph`. AXI64 data requests cross
directly from HP to memory and are adapted locally; AXI32 requests then enter
`axi4` and are queued by `sdram_axi4`
into native multi-beat commands for `sdram_core`. Register accesses stay on the
APB4 window and do not share the data-path arbiter. The physical SDRAM instance
remains in the SoC top.

`axi4_sdram` composes four blocks:

- `sdram_reg`: handwritten APB4 ABI, interrupt state, and performance counters.
- `sdram_axi4`: independent AR/AW/W/R/B queues and native burst fragments.
- `sdram_core`: init/reinit, bank machines, timing scoreboard, and command engine.
- `sdram_clkgen`: divided SDRAM clock plus `fir_edge` / `sec_edge`.

The implementation excludes DDR/DFI PHYs, FR-FCFS, QoS, ECC, interleaved MRS
bursts, self-refresh, a new SoC IRQ, and a register generator.

## AXI4 Contract

The frontend accepts one outstanding AXI read and one outstanding AXI write.
Independent Common `fifo` queues isolate the channels: AR/AW/B depth 2 and
W/R depth 8. `ARREADY` / `AWREADY` remain `!full`, so early firmware traffic
can land in the address queues during auto-init.

`accept_enable` is `CTRL.ENABLE && CTRL.MEMORY_ENABLE`. `core_ready` is
`STATUS.READY && !STATUS.INIT_BUSY`. Legal in-window requests stall in the
address queue until `core_ready` and then complete with `OKAY`. Illegal,
out-of-window, or disabled-window requests are popped immediately and complete
with `SLVERR`:

- out-of-window: `LAST_ERROR = AXI_DECODE`
- illegal beat or `!accept_enable`: `LAST_ERROR = AXI_ILLEGAL`

Supported transactions are aligned beats, `FIXED` / `INCR` / legal `WRAP`, at
most sixteen beats, no exclusive access, and no 4 KiB crossing. `FIXED` stays
per-word, `WRAP` splits at the wrap boundary, and `INCR` coalesces until a row
boundary.

Relative byte address bits map as `bank = addr[25:24]`, `row = addr[23:11]`,
`column = {addr[10:2], 1'b0}` after subtracting `SOC_ADDR_SDRAM_BASE`.

## Timing and Initialization

All timing registers are SDRAM-clock cycle counts. After reset the controller
auto-initializes with 36 MHz / CAS2 / BL2 / write-burst / close-page defaults
so current firmware can use the window without a software reinit. Software may
later write timings and issue `COMMAND.INIT` or `COMMAND.REINIT`.

`rs_sdram_timing_from_hz(source_hz, clkdiv, &timing)` converts Micron sg75
nanosecond limits with `ceil(ns * sdram_hz / 1e9)` and a minimum of one cycle.
`CLKDIV=0` yields `sdram_hz = source_hz / 2`.

## Register ABI

All registers are 32-bit and naturally aligned. Invalid offsets return
`pslverr`; partial writes follow `pstrb`. Hardware and software offsets are
hand-aligned; there is no register generator. Applications include
`<retrosoc/hal/sdram.h>` and do not use `soc.h` register macros. `CLKDIV`
is `0x00` and `CTRL` is `0x04`.

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| `0x000` | `CLKDIV` | RW | `0` | Divider `[1:0]`; `0` toggles every source cycle. |
| `0x004` | `CTRL` | RW | `0x7` | Enable, memory enable, auto-init, open-page. |
| `0x008` | `COMMAND` | W1S | `0` | One-hot INIT, REINIT, PRECHARGE_ALL, REFRESH. |
| `0x00C` | `STATUS` | RO | init busy | INIT/AXI/PHY busy, READY, ERROR. |
| `0x010` | `MODE` | RW | CAS2/BL2/WR burst | CAS 2/3, BL 2/8, write-burst, sequential only. |
| `0x014` | `TIMING0` | RW | `0x03020101` | tRP, tRCD, tRAS, tRC. |
| `0x018` | `TIMING1` | RW | `0x02020301` | tWR, tRFC, tRRD, tWTR. |
| `0x01C` | `TIMING2` | RW | `0x00030201` | tRTP, tMRD, tXSR. |
| `0x020` | `REFRESH` | RW | tREFI=281, credit=7 | Refresh interval and postpone limit. |
| `0x024` | `POWERUP` | RW | 3600 | 100 µs at 36 MHz. |
| `0x028` | `LAST_ERROR` | RO | `0` | Sticky decoded error code. |
| `0x02C` | `LAST_ERROR_ADDR` | RO | `0` | Address associated with `LAST_ERROR`. |
| `0x080` | `INTR_STATE` | W1C | `0` | INIT_DONE, ERROR. No new SoC IRQ is wired. |
| `0x084` | `INTR_ENABLE` | RW | `0` | Interrupt enable mask. |
| `0x088` | `INTR_STATUS` | RO | `0` | `INTR_STATE & INTR_ENABLE`. |
| `0x08C` | `INTR_TEST` | WO | `0` | Set selected `INTR_STATE` bits. |
| `0x090` | `PERF_CTRL` | RW | `0` | Enable, freeze, clear. |
| `0x094` | `PERF_READ_BYTES` | RO | `0` | Saturating mapped-read byte count. |
| `0x098` | `PERF_WRITE_BYTES` | RO | `0` | Saturating mapped-write byte count. |
| `0x09C` | `PERF_ROW_HIT` | RO | `0` | Saturating row-hit count. |
| `0x0A0` | `PERF_ROW_MISS` | RO | `0` | Saturating row-miss count. |
| `0x0A4` | `PERF_REFRESH_STALL` | RO | `0` | Saturating refresh-stall count. |
| `0x0A8` | `PERF_BANK_CONFLICT` | RO | `0` | Saturating bank-conflict count. |
| `0x0F8` | `IP_VERSION` | RO | `0x00020000` | ABI version 2.0. |
| `0x0FC` | `CAPABILITY` | RO | `0x401010EF` | 64 MiB, 16-beat, x16, CAS2/3, BL2/8, open-page. |

`MODE` and timing registers take effect on `INIT` / `REINIT` and still return
`pslverr` when any busy bit is set. `CLKDIV` is live. `CTRL` may change after
init, including clearing `MEMORY_ENABLE` while PHY refresh is in progress.
`CTRL.OPEN_PAGE=0` uses auto-precharge; `=1` keeps the row open.
`COMMAND.PRECHARGE_ALL` closes every open row and returns to idle; it does not
issue `REFRESH`. `COMMAND.REFRESH` is the explicit refresh request. Both pulses
are accepted while AXI or PHY is busy and are consumed at the next idle slot.
`INIT` / `REINIT` still return `pslverr` when any busy bit is set.

## HAL Sequence

Applications include `<retrosoc/hal/sdram.h>` and use bounded APIs:

```c
rs_sdram_config_t config = {0};
if (rs_sdram_timing_from_hz(source_hz, 0, &config.timing) == RS_OK) {
    config.clkdiv = 0;
    config.cas_latency = RS_SDRAM_CAS_2;
    config.burst_length = RS_SDRAM_BURST_2;
    config.refresh_credit_max = 7;
    config.write_burst = true;
    config.memory_enable = true;
    if ((rs_sdram_configure(&config) == RS_OK) &&
        (rs_sdram_initialize(timeout) == RS_OK)) {
        /* mapped window is ready */
    }
}
```

Firmware may also poll `STATUS` / `INTR_STATE`, or issue
`rs_sdram_precharge_all()` / `rs_sdram_refresh()` as one-shot `COMMAND` writes.
The booter only prints the window and does not force a software reinit.

## Requirements

| ID | Requirement | Check |
| --- | --- | --- |
| SDRAM-001 | Auto-init after reset leaves the mapped window usable. | `tests/test_sdram.py`, IHP130 `ci_smoke` Verilator access, and `hello.s` Icarus access. |
| SDRAM-002 | Native INCR bursts preserve data and masks. | `sdram_data_tb` INCR4/8/16. |
| SDRAM-003 | Illegal AXI completes with `SLVERR`. | Exclusive-read case in `sdram_data_tb`. |
| SDRAM-004 | RTL and HAL register offsets remain synchronized. | `tests/test_sdram.py` ABI comparison. |
| SDRAM-005 | Timing helper matches 36 MHz Micron sg75 defaults. | `tests/c/test_runtime.c`. |
| SDRAM-006 | Legal traffic stalls until `STATUS.READY` instead of completing `SLVERR` during auto-init. | Immediate post-reset write/read in `sdram_data_tb`. |
| SDRAM-007 | `PRECHARGE_ALL` does not imply `REFRESH`; disabled-window legal reads return `SLVERR`. | End of `sdram_data_tb`. |
