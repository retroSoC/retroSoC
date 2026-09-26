# HP RV64 Migration Validation

The active contract is [HP platform](ip/hp-platform.md), phases 2–5. LP remains
RV32 Hazard3. All PRODUCT profiles select RV64IMAFDC with Zicbom, Sv39 and
32-bit physical addresses. No upstream CPU or RT-Thread source is modified.

## Reproduction

```sh
make setup-vexiiriscv setup-hp-rtthread setup-hp-linux
make CONFIG=configs/ci/ihp130-hp.mk SIMU=VERILATOR hp-smoke-sim
make CONFIG=configs/ci/ihp130-rtthread.mk SIMU=VERILATOR hp-rtthread-sim
make CONFIG=configs/ci/ihp130-hp.mk SIMU=VERILATOR hp-linux-sim
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --behavioral-only
```

`HP_CROSS` is independent of LP `CROSS` and resolves to the compiler in the
dependency lock. RT-Thread is official v5.3.0 at
`99428a1e7f7447955aa860f7c969273a12095b8f`, compiled with RV64 `lp64d`.
Its selftest qualifies integer contexts; it does not qualify FCSR preservation
or floating-point tasks. Linux uses its Buildroot RV64 Linux compiler, Sv39,
static musl/BusyBox and a small uncompressed CPIO with a dedicated `/init`.

V2 flash bundles discriminate Linux (1, four entries), smoke (2, one executable)
and RT-Thread (3, one executable). Rebuild V1 bundles. The loader checks strict
flags, workload/count/types, fixed addresses, bounds, non-overlap, unused slots
and CRC. Only smoke enters the GA2D/cache lifecycle protocol. LP alone owns
the final SYSCTRL TEST_STATUS write for all workloads.

## Measured runs

Initial RV64 validation uses `configs/ci/ihp130-hp.mk` and
`BUILD_TIMESTAMP=2026-09-25-11-42`, producing
`build/ihp130-hp-2026-09-25-11-42-bb2e93b39338/`.

| Run | Result | Evidence below variant |
| --- | --- | --- |
| RV64 generated core and Verilator compile | Pass | `generated/vexiiriscv/manifest.json`, `sim/verilator/result-compile.json` |
| GA2D/cache lifecycle smoke | `SIM_TEST_PASS code=0`, 3,446,054 cycles, 191 seconds | `sim/verilator/sim.log`, `result-hp-smoke-sim-check.json` in the same directory |
| RT-Thread kernel/platform | All required markers and `SIM_TEST_PASS code=0`, 6,412,946 cycles, 360 seconds | `sim/verilator/hp-rtthread/sim.log`, `result-sim-check.json` |

The final dedicated `configs/ci/ihp130-rtthread.mk` profile passed all markers
and TEST_STATUS at 6,395,372 cycles in 357 seconds, using
`BUILD_TIMESTAMP=2026-09-25-12-18`. Its evidence is
`build/ihp130-rtthread-2026-09-25-12-18-bb2e93b39338/sim/verilator/hp-rtthread/`.
The final context probe compares registers against an original 64-bit sentinel
stored on each task's stack, catching identical truncation of multiple registers.
The final smoke also passed at 3,460,934 cycles in 195 seconds, with evidence
in `sim/verilator/hp-smoke/` under the initial variant.

Linux Image is 2,152,448 bytes; the static, uncompressed CPIO is 302,080 bytes.
BusyBox is expanded from `allnoconfig` and an explicit allowlist; effective
options and static ELF linkage are checked. Linux acceptance is still running
without an emulator wall-clock timeout; no Linux pass is claimed yet. New workload runs
write logs to `sim/verilator/hp-{smoke,rtthread,linux}/`. Structured results
start as `running`; failures/interruption replace old passes. A UART banner is
diagnostic, never the final verdict.

The affected Python and publication bindings pass 177 tests; one PDF-inspection
test is skipped because `pypdf` is not installed. C format, C policy and host
tests, Ruff, dependency-lock validation, `setup-hp-rtthread` and the dedicated
profile's Verilator doctor pass. The final publication-focused run passes 193
tests with one missing-`pypdf` skip. The full Python run reports 974 passed and
5 skipped; its two missing-FLAC-corpus failures were resolved by installing the
checksum-locked corpus and rerunning both tests (2 passed). Thus 976 cases have
passing evidence. The other skips are optional P7 model/MFCC inputs; no test
expectation was weakened to hide a missing input. After the firmware-reservation
correction, all 62 affected platform and publication checks pass.

The IHP130 behavioral PR regression completed successfully with
`BUILD_TIMESTAMP=2026-09-25-12-14`: strict lint, firmware builds, Verilator
`ci_smoke` (6,783,746 cycles, 384 seconds), `DEBUG_GDB_PASS`, and Icarus
`SIM_TEST_PASS`. Artifacts use `build/ihp130-2026-09-25-12-14-*` and
`build/ihp130-debug-2026-09-25-12-14-*`. Warning-baseline comparisons report
new/increased signatures as non-blocking observations; baselines were not
modified. No synthesis or STA result is implied by this regression.

## RT-Thread first-schedule failure and correction

The first BSP run reached `HP_RTTHREAD_BOOT` and then reported
`RTTHREAD_TRAP cause=1 epc=deadbeee`, failure 92, followed by LP failure 18.
Evidence is retained in `sim/verilator/hp-rtthread-idle-stack-failure/` under
the initial variant. This was a BSP integration error:

1. The BSP used `RT_IDLE_THREAD_STACK_SIZE`; the locked upstream `src/idle.c`
   reads `IDLE_THREAD_STACK_SIZE` and otherwise selects 128 bytes without heap.
2. The failing ELF's `idle_thread_stack` was 128 bytes at `0x38004530`.
   Upstream `rt_hw_stack_init` reserves 512 bytes for 32 RV64 integer slots
   and 32 double-precision slots, filling them with `0xdeadbeef`.
3. That frame starts at `0x380043b0`, 384 bytes before the allocated stack,
   overwriting `_object_container`, interrupt-switch state, the scheduler's
   ready bitmap and other globals. This explains the invalid first-schedule
   state and is independent of the AXI crossbar.
4. The BSP now uses the correct macro with 2048 bytes and a compile-time lower
   bound. The same integrated test then passed scheduling, RV64 context, IPC,
   timer timeout, and mailbox IRQ checks. Vendor source stayed unchanged.

## Linux firmware reservation correction

The first RV64 run reached Linux 6.12.105 and memory initialization. Its log
reported no `/reserved-memory` node and included the full SDRAM range beginning
at `0x38000000`. OpenSBI's preceding PMP report protected its resident code/data
from S-mode. Static inspection confirmed that the custom platform has no generic
`fdt_fixups()` final-init hook; Linux `arch/riscv/mm/init.c:setup_bootmem` reserves
the kernel, initrd, DTB and DT-declared regions, not an implicit firmware window.
Thus the DT omitted a live firmware allocation. No resulting crash was observed;
the run was deliberately interrupted to correct this integration defect.

The retained log is `sim/verilator/hp-linux-before-firmware-reservation/` under
the initial variant. The DT now reserves the complete, already allocated
512 KiB OpenSBI window with `no-map`, and the effective-config guard requires
`CONFIG_OF_RESERVED_MEM=y`. The DTB test checks both the exact range and
`no-map`. The corrected runtime now prints
`0x0000000038000000..0x000000003807ffff (512 KiB) nomap non-reusable opensbi@38000000`,
confirming that Linux consumed the reservation. Userspace acceptance is still
in progress.

During the subsequent quiet `Initmem setup node 0` interval, two read-only host
debugger samples captured 64,772,063 and 66,503,381 emulator cycles. The sampled
Sv39 PCs resolve to `__init_single_page` and `memmap_init_range` in the actual
`vmlinux`; disassembly passes `s0` as the PFN and increments it at loop end.
`s0` advanced from `0x3b0c4` to `0x3b6ed`, toward the `s1=0x3c000` bound.
Privilege remained S-mode and SATP mode was 8. This establishes loop progress
during that interval, not a complete boot verdict. Samples and disassembly are
retained under `meta/hp-rv64-validation/`; no DUT state was written.
Later samples at 84,162,019 and 92,239,597 cycles resolve to
`should_skip_region` / `__next_mem_range` and `__free_pages_ok` called by
`memblock_free_all`, respectively. A further sample at 97,866,745 cycles is in
`__free_pages_core`, with a later page-descriptor block address. These locate
the later allocator work separately from the earlier page-descriptor loop.
After IRQ initialization, samples landed in timer handling. The interrupted
SEPC then moved from `memset` to `add_device_randomness`; the latter frame was
decoded from valid, matching-tag L1 data-cache lines and checked against the
RISC-V `pt_regs` layout. UART subsequently reported the 9-bit ASID allocator.
These observations avoid treating an IRQ-handler PC or stale raw SDRAM as
evidence of main-thread progress.

## Coverage limits

The repository's mechanical C format/policy checks are partial MISRA evidence;
no complete MISRA certification or new approved Required-rule deviation is
claimed. Board MMIO uses fixed, naturally aligned 32-bit accesses to declared
register windows; RV64 pointer width does not widen device accesses.

Synthesis, netlist simulation, STA and synthesis-dependent metrics are deferred
by explicit user instruction. PPA, CDC/RDC, physical SRAM mapping, hardware
board runs and silicon qualification are not established by these simulations.
The behavioral evidence is IHP130-specific; other PDK matrices and extended
nightly benchmarking were not rerun in this migration.
The GDB regression exercises LP Hazard3 debug; it is not independent RV64 HP
debug/JTAG qualification.
The minimal Linux configuration leaves `CONFIG_RISCV_ISA_ZICBOM` disabled.
The custom OpenSBI platform does not import Zicbom into its hart-extension mask,
so it leaves MENVCFG CBIE/CBCFE disabled. The cache-maintenance evidence here is
the M-mode smoke; enabling native Linux non-coherent DMA requires the matching
firmware extension/permission setup and a separate S-mode CBO acceptance test.
Publication source bindings are updated separately from the previously reviewed
PDF snapshot; a fresh PDF requires an explicitly reviewed committed snapshot.
