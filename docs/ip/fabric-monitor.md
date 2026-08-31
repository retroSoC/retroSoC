# Mini Data-Plane Fabric Monitor

## Scope

The Fabric Monitor at `0x2000_B000` provides root-management visibility into
the native AXI64 data plane. It runs in the HP clock domain beside the
crossbar and is reached from PCLK through `apb4_async_bridge`. Hazard3 may
read and control it; the HP MMIO firewall denies writes to this root-only
window.

The monitor is observational. It does not change arbitration, admission,
target timeout, or reset behavior. Counters saturate at `0xFFFF_FFFF` and
never wrap. Software explicitly snapshots counter banks before reading them,
so a multi-register sample is stable while live counting continues.

## Global Register ABI

| Offset | Name | Access | Contract |
| ---: | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x44504D4E` (`DPMN`) |
| `0x004` | `IP_VERSION` | RO | `0x00010000` |
| `0x008` | `CAPABILITY` | RO | target count `[31:24]`, master count `[23:16]`, saturating/snapshot capability `[1:0]` |
| `0x00C` | `CONTROL` | RW | enable bit 0, freeze bit 1, clear pulse bit 2, snapshot pulse bit 3 |
| `0x010` | `STATUS` | RO | write outstanding `[23:16]`, read outstanding `[15:8]`, flush busy bit 2, recovery bit 1, idle bit 0 |
| `0x014` | `FAULT` | RO | reason `[11:8]`, target `[7:5]`, master `[4:2]`, write bit 1, valid bit 0 |
| `0x018` | `FAULT_ADDRESS` | RO | address of the first retained fault |
| `0x01C` | `FLUSH_COUNT` | RO | snapshotted warm-flush rising-edge count |
| `0x020` | `FAULT_COUNT` | RO | live count of all observed fault events |

`CONTROL.CLEAR` clears both live and snapshot counters and the retained fault.
`CONTROL.SNAPSHOT` copies every live performance counter into its read bank.
Asserting both commands together is rejected with `PSLVERR`. Partial, unknown,
unaligned, and read-only writes are also rejected. Freeze stops collection but
does not clear state.

The first fault after reset or clear is sticky. Later faults increment
`FAULT_COUNT` but do not overwrite its identity or address. This preserves the
root cause across the PCLK-to-HP bridge and prevents a short data-plane pulse
from being missed by software.

## Master Counter Banks

Eight master banks start at `0x100 + master * 0x20`:

| Relative offset | Counter |
| ---: | --- |
| `0x00` | accepted read addresses |
| `0x04` | accepted write addresses |
| `0x08` | returned read beats |
| `0x0C` | accepted write-data beats |
| `0x10` | cycles with address or write-data backpressure |
| `0x14` | maximum consecutive wait cycles |
| `0x18` | starvation-aging promotions |
| `0x1C` | write high-water `[5:3]`, read high-water `[2:0]` |

Master indices are HP I-cache, HP D-cache, central DMA, I/O gateway A, I/O
gateway B, LP data gateway, reserved, and EXT-H. The reserved slot remains
visible so an integration defect cannot silently disappear from accounting.

## Target Counter Banks

Six target banks start at `0x300 + target * 0x20`:

| Relative offset | Counter/status |
| ---: | --- |
| `0x00` | accepted read addresses |
| `0x04` | accepted write addresses |
| `0x08` | returned read beats |
| `0x0C` | accepted write-data beats |
| `0x10` | cycles with any AXI channel backpressured |
| `0x14` | target-guard timeout events |
| `0x18` | current fail-closed isolation state bit 0 |
| `0x1C` | write high-water `[5:3]`, read high-water `[2:0]` |

Target indices are SRAM, SDRAM, QPI, OPI/HyperBus, XPI, and the finite-latency
error target. Isolation is live status; the performance fields come from the
last snapshot.

## Software and Verification

`<retrosoc/hal/fabric_monitor.h>` provides enable/freeze, clear, snapshot,
status, flush-count, sticky-fault, per-master, and per-target APIs. RTL and C
offsets are independently handwritten and checked for parity; no register
generator is used.

`tests/rtl/fabric_monitor_tb.sv` verifies collection, maximum wait, promotion,
high-water, timeout, isolation, sticky fault retention, snapshot, and clear.
`tests/rtl/axi4_data_crossbar_tb.sv` verifies that the production arbitration
emits a promotion event. Full AXI formal proof, percentile histograms, trace
streaming, performance-counter interrupts, and silicon correlation remain
future delivery work.
