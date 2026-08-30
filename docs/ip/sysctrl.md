# APB4 System Control

SystemCtrl is the Mini SoC control-plane peripheral at
`0x1000B000`. It owns legacy user-core/IP compatibility, PLL and clock requests,
memory-pad mode,
bus-fault retention, performance-counter snapshots, RTC wake observation, and
the terminal simulation result. In the HP profile it also owns HP reset release
and shared-JTAG selection. The integration wrapper is `apb4_sysctrl`;
the implementation is separated into `sysctrl_reg`, `sysctrl_core`, and
`sysctrl_if`.

## Integration

`sysctrl_if` is the SoC-facing contract. It drives the selected user core,
per-core reset mask, user-bus enable, selected user IP, performance
enable/clear, and sticky terminal test result. It receives user-bus idle,
fault metadata, ten wait counters (including independent SDIO0 and SDIO1
master wait counters), and asynchronous RTC wake. `sysctrl_core`
synchronizes RTC wake with the Common `cdc_sync` primitive before storing its
sticky state.

`pll_ctrl_if` carries a one-request PLL configuration handshake. SystemCtrl
asserts `req_valid_o` after a valid `PLL_CMD.APPLY`, holds `busy` until the
PLL response is accepted, and always asserts `rsp_ready_o`. See
[PLL Clock Control](../pll-clock-control.md) for the required software
quiesce sequence. `clock_ctrl_if` independently carries LP/PCLK, force-safe,
timeout, gate, memory-pad, status, and fault requests between PCLK and AON.

## APB4 contract

SystemCtrl accepts an APB4 access in the ACCESS phase when `psel` and
`penable` are high and the registered `pready` is still low. It completes in
the following cycle and captures read data on accepted reads. Reads of an
unmapped register retain the previously captured read value. Product writes to
retired user-core/IP controls and rejected concurrent clock commands assert
`pslverr`. Writes use the existing byte strobe
qualification for each field; software must use full-word writes for
`TEST_STATUS`.

The offset map remains generated from
`rtl/mini/address_map/memory_map.json`. RTL aliases are in
`rtl/ip/peripheral/sysctrl_define.svh`; neither file changes the generated C
offset macros.

## Register ABI

| Offset | Register | Access | Semantics |
| --- | --- | --- | --- |
| `0x000` | `CORESEL` | RO/unsupported | Product reads zero; writes return `PSLVERR`. MPW retains selection. |
| `0x004` | `IPSEL` | RO/unsupported | Product reads zero; writes return `PSLVERR`. MPW retains selection. |
| `0x008` | `PLL_CFG` | RW | Requested PLL profile, bits `[2:0]`. |
| `0x00C` | `PLL_CMD` | WO | Bit 0 applies `PLL_CFG`; bit 1 clears sticky PLL error. |
| `0x010` | `FAULT_STATUS` | RW1C | Bit 0 pending, bit 1 write, bits `[4:2]` normalized reason. Write one to bit 0 clears pending. |
| `0x014` | `FAULT_ADDR` | RO | First fault address while pending. |
| `0x018` | `FAULT_COUNT` | RO | Saturating count of observed faults. |
| `0x01C` | `PLL_STATUS` | RO | Active profile, valid, busy, error/error reason, safe clock, lock, and capability. |
| `0x020` | `USER_CORE_RESET` | RO/unsupported | Product reads all ones and rejects writes. MPW retains its reset mask. |
| `0x024` | `USER_CORE_STATUS` | RO/unsupported | Product reports present=0, idle=1, and sticky unsupported-write error. |
| `0x028` | `FAULT_MASTER` | RO | First fault master, a three-bit AXI master ID (0..7); HP is 7. |
| `0x02C` | `FAULT_DETAIL` | RO | First raw RIB response code. |
| `0x040` | `PERF_CTRL` | RW | Bit 0 enable, bit 1 clear pulse, bit 2 snapshot pulse. |
| `0x044`-`0x098` | `PERF_*_WAIT_{LO,HI}` | RO | Snapshot of management, user, central DMA, SDIO0, SDIO1, APB4, SDRAM, PSRAM, and flash wait counters. |
| `0x08C`/`0x090` | `PERF_SDIO0_WAIT_LO/HI` | RO | Independent SDIO0 AXI master wait snapshot. |
| `0x094`/`0x098` | `PERF_SDIO1_WAIT_LO/HI` | RO | Independent SDIO1 AXI master wait snapshot. |
| `0x084` | `TEST_STATUS` | RW-once/RO | Full-word write with bit 31 set records sticky done, bit 0 pass, and bits `[15:8]` result code. |
| `0x088` | `RTC_WAKE_STATUS` | RW1C/RO | Bit 0 synchronized live wake; bit 1 sticky wake, cleared by writing one to bit 1. |
| `0x0A4` | `HP_CTRL` | RW | Bit 0 releases HP reset when the HP profile is present. Reset value 0. |
| `0x0A8` | `HP_STATUS` | RO | Bits 0/1/2 report present, released, and reset asserted. |
| `0x0AC` | `DEBUG_SELECT` | RW | Bit 0 selects HP on shared JTAG only while HP remains in reset. Reset value 0 selects LP. |
| `0x0B0` | `CLK_HP_REQ` | RW/WO command | HP P-state; bits 31/30 apply PLL/force safe. |
| `0x0B4` | `CLK_HP_CURRENT` | RO | Current HP source/P-state and LP/PCLK/gate configuration. |
| `0x0B8` | `CLK_LP_CFG` | RW | LP SAFE/AUTO/MANUAL mode and `/1,/2,/4` selection. |
| `0x0BC` | `CLK_PCLK_CFG` | RW | PCLK `/1,/2,/4,/8,/16` selector. |
| `0x0C0` | `CLK_STATUS` | RO | PLL fault, clock error, and busy state. |
| `0x0C4` | `CLK_FAULT` | RW1C/RO | AON PLL/clock fault summary and clear command. |
| `0x0C8` | `CLK_TIMEOUT` | RW | Nonzero AON transaction timeout. |
| `0x0CC` | `CLK_GATE` | RW | Reserved leaf-gate mask state. |
| `0x0D0` | `MEM_PAD_CTRL` | RW-once | QPI/OPI mode and lock. |
| `0x0D4` | `MEM_PAD_STATUS` | RO | Present, mode, lock, and fault. |
| `0x0D8` | `MEM_PAD_FAULT` | RW1C/RO | Illegal mode/locked-write fault. |

The first fault remains visible until software clears pending; later faults
increase only the saturating count. A hardware fault in the clear cycle
remains pending. `TEST_STATUS` accepts the first valid full-word write after
reset and ignores all later writes, allowing the simulator to use a stable
verdict.

## SDK contract

`<retrosoc/hal/sysctrl.h>` owns typed SystemCtrl access. It provides semantic
operations for legacy compatibility, PLL/clock configuration/status, fault
inspection and clear, performance control/counter reads, terminal status, and
RTC wake state. Legacy `reg_sysctrl_*` lvalue macros are intentionally absent
from `<retrosoc/core/soc.h>`.

Existing `<retrosoc/hal/clock.h>`, `<retrosoc/hal/user_core.h>`, and
`<retrosoc/hal/perf.h>` APIs retain their behavior and delegate their
SystemCtrl accesses to this HAL. `<retrosoc/service/test.h>` writes the
sticky terminal result through `rs_sysctrl_write_test_status()`.

## Verification

`tests/test_sysctrl.py` and `tests/rtl/sysctrl_tb.sv` check APB4 response
retention, reset values, retired-control errors, first-fault retention and
W1C behavior, performance snapshots, sticky terminal status, and RTC wake
live/sticky behavior. `sysctrl_formal` proves the user-core, PLL, fault, and
test-status invariants and covers normal/error paths. The separate PLL/RCU
test retains dynamic-clock and fallback coverage.
