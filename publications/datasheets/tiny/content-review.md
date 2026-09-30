# Tiny Gen1 v0.1 DRAFT content review

The publication describes the independent IHP130 Tiny profile: one RV32IMC
Hazard3 with A disabled, RV32IM default firmware, 128 KiB SRAM, 24 MHz target,
four DMA channels and AXI32/APB4. Rill (清溪) is the selected prototype brand.
The font/palette/grid are inherited as design rules; product facts are not
inherited from Mini's descriptions or qualification records.

| Area | Review and publication decision | Follow-up boundary |
| --- | --- | --- |
| CPU and startup | Publish the actual C/M extensions, disabled A, CSR-enabled firmware and Tiny guard around PSRAM setup. | Keep compiler target separate from implemented ISA; a reset vector is not a completed boot. |
| Fabric | Document one globally active CPU/DMA read or write, saved ownership, naturally aligned bounded bursts and terminal response/drain. | Do not claim arbitrary AXI4 features, independent read/write concurrency or unrestricted liveness. |
| Address/IRQ/pads | Derive all 20 regions, 14 allocated core causes and 52 logical signal pads; retain 32 GPIO alternate entries. | Logical pads are not package pin numbers or a board schematic. |
| IP/register scope | Fourteen chapters, thirteen unique register families; Tiny SYSCTRL is decoded independently and ARCHINFO overrides the SoC identity. | Reject missing/extra decode and defaults belonging to other products. |
| DMA | Four channels, request mask 0x07F9, no stream modes, 64-byte descriptors and source-derived field layout. | **Discovery discrepancy:** the four-bit maximum-burst field reads zero after truncating 16. Publish that value and the actual 16-beat limit separately; propose a future ABI/RTL review, do not change RTL here. |
| SRAM | 32 x 4 KiB banks, four data bytes, no reset erase. | Local FIXED/WRAP capability bits do not override the narrower Tiny fabric subset. |
| UART/I2C/timers | Reused family ABI with actual instances, routing and 24 MHz engine clock. UART1 is PIO/IRQ without a Tiny DMA route. | Generic UART HAL example is UART0; peripheral command acceptance is not necessarily completed I/O. |
| Supervision | RTC and watchdog share the system clock; WDG requests system reset and retains its own reset observation. | No independent sleep clock, battery-backed retention or clock-failure watchdog guarantee. |
| Acceptance | The application source performs CPU, fault, DMA, timer, RTC and I/O checks, then watchdog reboot. | A nonzero pre-existing watchdog reset count takes an early pass branch; controlled initial state is required. |
| Verification | Retain the dated repository narrative, including slow-corner setup WNS -455.18 ns at a 41.666666667 ns constraint. | Raw matching artifacts are not present in this publication workspace; no current-commit qualification is promoted. |
| Electrical/package/power | Preserve explicit missing-evidence tables and required measurement context. | No numerical production limits, die area, thermal rating or silicon claim is invented. |

The existing Tiny verification document reports an originally uncommitted run
and a later path-migration follow-up. Neither automatically qualifies the source
SHA selected for this document. The final publication validation report records
only checks executed for this build; hardware campaign repair is separate work.

The [chapter review](chapter-review.md) covers all frozen entries and gives
source/evidence/maintenance advice. Full registers and software guidance are
retained even when a board or physical result is unavailable. No Mini document,
version, review or PDF is updated by this addition.
