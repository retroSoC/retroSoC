# HP RV64 Migration Validation

The active contract is [HP platform](ip/hp-platform.md). LP remains RV32
Hazard3 (hart 0); HP is the locked, pre-generated T-Head OpenC906 (hart 1,
RV64GC with Zicsr/Zifencei, M/S/U modes, Sv39, 32-bit SoC physical
addresses). No upstream CPU or RT-Thread source is modified.

## Current status after the OpenC906 core swap

All simulation evidence below was gathered with the previous generated
VexiiRiscv HP core and is historical: it must not be presented as OpenC906
qualification. Current evidence requires, at minimum:

- `make setup-openc906` (part of `make setup`) restoring the locked
  [openc906](https://github.com/XUANTIE-RV/openc906) checkout, and
  `make openc906-prepare` emitting
  `build/<variant>/generated/openc906/openc906.fl` and its manifest under the
  pinned upstream sha256 guard, with the reviewed
  `rtl/mini/ip_overrides/aq_sysio_kid.v` hart-ID override applied by filelist
  generation rather than by editing the vendored checkout.
- Verilator compile of the OpenC906 HP subsystem, including the serializing
  `axi4_downsizer_128to64` and `axi4_mmio_demux` path.
- Fresh `hp-smoke-sim`, `hp-rtthread-sim`, and `hp-linux-sim` runs from their
  committed IHP130 profiles with all contract markers and
  `SIM_TEST_PASS code=0`, exercising the internal C906 CLINT/PLIC and the
  `time`-CSR mtime delivery.
- The IHP130 behavioral PR regression on the swapped design.

### OpenC906 evidence gathered (2026-10-10)

- `hp-smoke-sim` on `configs/ci/ihp130-hp.mk` (Verilator): `HP_LINUX_READY`,
  `HP_GA2D_PASS`, `HP_GA2D_CACHE_CLEAN`, `SIM_TEST_PASS code=0`;
  3,629,906 cycles in 285 s. This exercises C906 boot at 0x38000000, the
  128-to-64 downsizer and MMIO demux, the mailbox protocol, the GA2D engine
  through the HP data path, and the T-Head `dcache.cva`/`dcache.iva` cache
  lifecycle handshake.
- `hp-rtthread-sim` on `configs/ci/ihp130-rtthread.mk` (Verilator): all
  selftest markers (`RTTHREAD_RV64_PASS`, `RTTHREAD_TIMEOUT_PASS`,
  `RTTHREAD_PREEMPT_PASS`, `RTTHREAD_CONTEXT_PASS`, `RTTHREAD_IPC_PASS`,
  `RTTHREAD_MAILBOX_IRQ_PASS`, `RTTHREAD_TEST_PASS`) plus `HP_RTTHREAD_PASS`
  and `SIM_TEST_PASS code=0`; 6,373,952 cycles in 542 s. This exercises the
  C906 internal CLINT timer tick and MSIP IPI, the internal PLIC mailbox
  doorbell (MEIP), and the full cached SDRAM fill path.
- `hp-linux-sim` on `configs/ci/ihp130-hp.mk` (Verilator, bounded 2 h wall,
  83.5 M emulator cycles / 41.8 M HP cycles): OpenSBI v1.9 completes fully on
  the C906 with the repo-owned platform (custom timer device reading the
  `time` CSR plus internal-CLINT MSWI IPI, custom UART1 console), and
  `fw_jump` hands off to the kernel Image at `0x38400000` with the DTB at
  `0x38080000` (bundle segments byte-identical to the built images,
  CRC-checked). The kernel enters S-mode, brings Sv39 up, executes past
  `set_cpu_online()`'s first AMO, and prints `Linux version 6.12.105+` on the
  SBI console: the earlier boot blocker is fixed (see the MAEE entry below).
  A longer bounded run (8 h wall) with the STIMECMP fix additionally boots
  the kernel through console init, BogoMIPS calibration, devtmpfs, and the
  switch to the riscv_clocksource with a healthy periodic tick. The 12 h run
  then probes the internal PLIC successfully at runtime (`riscv-plic:
  interrupt-controller@8000000: mapped 31 interrupts`, validating the
  OpenSBI `fdt_irqchip_init` hook) and completes the initramfs unpack
  (`Unpacking initramfs...` / `Freeing initrd memory: 292K`). Userspace
  acceptance (`HP_LINUX_READY`) is not yet reached: see the write-wedge
  frontier entry below. The target stays unqualified until that acceptance
  completes.
- The remaining boot frontier is a write-channel wedge, reproduced
  deterministically by a bare-metal payload (dcache-dirty eviction traffic
  interleaved with fenced MMIO polls wedges it at ~22 rounds in ~1.5 M HP
  cycles) and by the kernel late in boot: the C906 issues a write AW whose W
  data never leaves the core (zero W beats presented at the 128-bit port, and
  at the stuck point the LSU store-buffer and victim-buffer write-valids and
  the BIU write buffers are all empty, so the data vanished inside the core
  after its AW was accepted), so the demux write FSM is parked in Active, the
  SDRAM core sits in its write-data state waiting for the missing W stream,
  the concurrent read fill's R never returns behind it, and the core freezes
  at the next fenced MMIO poll (`retrosoc_hp_console_putc`). This is
  independent of the fence instructions (the no-fence control payload wedges
  identically), of the dcache write mode (write-back, write-through, and
  dcache-off all wedge), and of the MAEE/cacheability work above. The
  integration manual's write-channel contract (INCR only, len 1/4, 16
  outstanding with one per ID, no write interleave, bufferable responses) is
  honored by our fabric; the violation is inside the core's LSU data release,
  exposed by the slow-SDRAM window. A guard write timeout does not cover the
  source-stalled W stream, so the wedge is permanent. Root-causing it needs
  C906 LSU debugging (store-buffer/victim-buffer data release) or an
  interconnect that buffers a full write burst before engaging the SDRAM
  command engine; both are out of this round's scope. An sdram_axi4-side
  gate-the-command-on-full-burst prototype recovered the blocked read but
  not the C906's withheld W, so it is not a fix and was not kept.
- The Linux boot blocker was a doc/RTL mismatch in OpenC906, root-caused with
  bare-metal MMU payloads and locked by simulation evidence: the user manual
  states `mxstatus.MAEE` resets to 0, but the RTL (`aq_cp0_ext_csr.v`) resets
  it to 1. With MAEE set, S-mode page attributes come from the T-Head
  extended PTE bits [63:59], which a stock mainline kernel never programs, so
  every translated page is non-cacheable; the C906 then raises a store/AMO
  access fault (cause 7) for any AMO on such a page (`aq_lsu_ag.v`:
  `!mmu_ca && ag_pipe_amo`). The first victim is `set_cpu_online()`'s
  `amoor.d.aqrl` on `__cpu_online_mask`, after which the kernel enters the
  `do_trap_break` storm. Loads/stores and full Sv39 page-table walks
  (4 KiB three-level, 2 MiB megapage, high-half canonical VAs, cold fills from
  SDRAM after D$ eviction) were proven correct independently: the failure was
  purely the AMO-on-non-cacheable rule. The OpenSBI platform `early_init` now
  clears `mxstatus.MAEE` (`app/ports/linux/opensbi/retrosoc_hp/platform.c`),
  making translated accesses follow the sysmap override (RAM cacheable, MMIO
  strong-order device) so the stock kernel needs no T-Head PBMT errata. A
  directed payload then passes the full AMO battery (amoor/amoadd/amoswap/
  lr-sc, cold-line and high-half-VA variants).
- The post-`sched_clock` stall was a second doc/RTL trap of the same family:
  the C906 ORs the internal CLINT's hardware supervisor-timer line into
  `mip.STIP` (`aq_cp0_trap_csr.v`: `st_int && CLINTEE || stip_reg`) and the
  RTL resets `CLINTEE` to 1. Nobody parked the internal STIMECMP, and the
  compare registers' `0xFFFF_FFFF` reset values are not guaranteed to be
  applied (the HP hold-reset produces no async negedge in Verilator, leaving
  them at zero), so the hardware S-timer line fired continuously: the first
  `sie.STIE` enable in the kernel's `time_init` dropped it into an infinite
  supervisor-timer storm and starved the boot thread. M-mode firmware
  (RT-Thread, OpenSBI) is immune, which is why earlier targets were
  unaffected. The OpenSBI `early_init` now parks both internal-CLINT compare
  registers at cold boot, making the state deterministic on silicon and in
  simulation; probe evidence shows MTIMECMP armed exactly one jiffy out and
  MTIP firing exactly at the compare value on a healthy 288 kHz-cycle
  cadence.
- The RT-Thread bring-up exposed and fixed three latent issues, each locked
  by directed regression. (a) The C906 resets with caches and the BPU
  disabled and does not initialize the cache/predictor RAMs: HP payloads must
  run the upstream `mcor` invalidate-then-`mhcr` enable sequence
  (`app/ports/rtthread/start.S`, OpenSBI `early_init`). Without it the 1 kHz
  tick ISR livelocked the uncached core, and enabling caches without
  invalidating first produced wild control flow. (b) `sdram_axi4` computed
  WRAP wrap-back addresses from the decrementing remaining-beat count,
  corrupting every cache-line fill starting mid-line (locked by WRAP cases in
  `tests/rtl/sdram_data_tb.sv`). (c) The data crossbar's `burst_legal`
  computed a WRAP burst's last address as if it were INCR, faulting fills
  that start in the last 64 bytes of a 4 KiB page (locked by the page-edge
  case in `tests/rtl/axi4_data_crossbar_tb.sv`). No previous master issued
  WRAP bursts, so (b) and (c) predated the swap.
- Focused `hp_c906_boot_tb` (pytest `test_hp_platform.py`): the real smoke
  payload runs on `hp_core_wrapper` plus the production MMIO chain
  (64-to-32 downsizer, address gate, HP-to-LP CDC bridge) and completes the
  full mailbox/GA2D-phase protocol.
- The swap exposed and fixed a latent integration bug: the merged HP port
  initially inherited the read-only I-cache slot's zero write credits in the
  data crossbar; `axi4_data_crossbar.sv` now grants the HP slot two write
  credits, locked by a new write/readback case in `ga2d_platform_tb`.
- The sysmap override is required for correctness: the upstream default marks
  the Mini MMIO window cacheable/bufferable, which absorbs device writes in
  the C906 store buffer; `rtl/mini/ip_overrides/sysmap.h` marks the MMIO and
  core-internal CLINT/PLIC windows strong-order non-cacheable per the user
  manual.
- The integration manual chapter 3 SRAM swap is validated in simulation: the
  eight `rtl/mini/ip_overrides/aq_spsram_*.v` overrides select IHP130
  `RM_IHPSG13_1P_*` macro combinations under `PDK_IHP130`+`HAVE_SRAM_MACRO`
  without `PDK_BEHAV`, and the focused boot testbench variant
  `test_c906_boots_smoke_payload_with_ihp130_sram_macros` boots the real
  smoke payload (cache maintenance plus GA2D data movement, which exercises
  the BHT/ICache/DCache/JTLB RAMs for real) on the macro path with the same
  `HP_C906_BOOT_TEST_PASS` verdict as the behavioral run.
- The wrappers also have an ICS55 macro path: under `PDK_ICS55`+
  `HAVE_SRAM_MACRO` without `PDK_BEHAV` each wrapper directly instantiates
  its exact-geometry `ics55_ecos_sram_<geom>_m4/m8` macro (locked
  `openecos-projects/ics55_ecos_sram` release assets materialized by
  `make setup-pdk`; polarity-identical ports, no stacking or padding). The
  focused boot testbench variant
  `test_c906_boots_smoke_payload_with_ics55_sram_macros` passes with the same
  verdict, the vendored MEM_INTF memory suite (manual section 3.2, adapted
  to Icarus) passes on the ICS55 path as well, and the `ics55.mk` CI profile
  smoke simulation (`APP=ci_smoke`, Verilator) passes with the macro path
  compiled into the SoC.
- The wrappers also have a GF180 macro path: under `PDK_GF180`+
  `HAVE_SRAM_MACRO` without `PDK_BEHAV` each wrapper is tiled from the GF180
  8-bit bit-write macros `gf180mcu_fd_ip_sram__sram{64,128,256,512}x8m8wm1`
  (identical active-low polarity; depth/width tiling with registered read
  muxes where stacked). The vendor verilog views are timing-only, so the
  simulation models are repo-owned in `rtl/tech/gf180_sram_sim_cells.sv`.
  The directed eight-wrapper equivalence bench and the MEM_INTF suite both
  pass on the GF180 path, and the focused boot testbench variant
  `test_c906_boots_smoke_payload_with_gf180_macros` passes with the SRAM
  tiles and the `icgtp_1` ICG active together. SKY130 stays behavioral: the
  locked OpenRAM SRAM has only a byte-granular write mask while the wrappers
  need per-bit write enable.
- The chapter 3 ICG swap is validated in simulation on all four PDKs: the
  `gated_clk_cell.v`/`tdt_gated_clk_cell.v`/`BUFGCE.v` overrides select
  `sg13g2_slgcp_1` (IHP130), `ICGX1H7R` (ICS55, scan enable ORed into `E`),
  `sky130_fd_sc_hd__sdlclkp_1` (SKY130), or
  `gf180mcu_fd_sc_mcu7t5v0__icgtp_1` (GF180; repo-owned sim model in
  `rtl/tech/gf180_seq_sim_cells.v` because the locked checkout never ships
  the vendor latch UDP the cell model references) under a `PDK_*` define
  without `PDK_BEHAV`. The vendored MEM_INTF `c906_icg_test_tb` gate sequence
  passes on all four cell paths (Icarus adaptation; the pass-through default
  fails it by design since it never gates). The focused boot testbench passes
  with real clock gating for all four PDKs — the IHP130/ICS55 modes run SRAM
  macros and ICG together, the SKY130/GF180 modes run ICG with behavioral
  SRAMs. One integration fix was required for two-state simulators:
  `hp_core_wrapper` asserts the C906/DTM ICG scan-enable while the core is
  held in reset, so flops behind closed gates initialize on running-clock
  edges (the DTM sleeps at boot and otherwise holds `hartreset_n` low);
  pass-through modes ignore the scan-enable input and stay bit-identical.

`hp-linux-sim` was run with a bounded wall-clock budget this round and its
current frontier is recorded above; the synthesis-dependent gates remain
unrun (synthesis, netlist simulation, STA, and the physical/LEC qualification
of the macro path; on Yosys the C906 ICS55 macros additionally need their
Liberty views registered in `physical/smoke/syn/yosys/script/init_tech.tcl`,
and the ICS55 smoke synthesis is already red without this work because
`npu_scheduler.sv` hard-codes IHP130 `sg13g2_dlygate4sd3_1` delay cells under
plain `SYNTHESIS`). The SoC-level macro-mode simulation now has passing
evidence: `make CONFIG=configs/ci/ihp130-hp.mk PDK_BEHAV=NO SIMU=VERILATOR
hp-smoke-sim` builds the whole SoC (C906 `aq_spsram_*` wrappers and
`tc_sram`) on the IHP130 macro models and passes with
`SIM_TEST_PASS code=0` plus the `HP_LINUX_READY`/`HP_GA2D_PASS`/
`HP_GA2D_CACHE_CLEAN` markers; with the ICG overrides the same run also
exercises the real `sg13g2_slgcp_1` clock gates. The same SoC smoke passes on
the ICS55 macro+ICG path (`PDK=ICS55 PDK_BEHAV=NO`, 3.64M cycles,
`SIM_TEST_PASS code=0` with the full GA2D cache-lifecycle marker sequence)
and on the GF180 macro+ICG path (`PDK=GF180 PDK_BEHAV=NO`, identical cycle
count), and the `sky130.mk` and `gf180.mk` CI profile smokes (`APP=ci_smoke`,
Verilator) pass with the SRAM tiles and the `sky130_fd_sc_hd__sdlclkp_1` /
`gf180mcu_fd_sc_mcu7t5v0__icgtp_1` ICG compiled in (the GF180 C906 SRAMs run
as macro tiles there too). The default 300 s
`HP_SMOKE_SIM_TIME` is only enough when the run is uncontended, and the bare
`ics55.mk` profile-default `sim` (no fast-flash) exceeds its 180 s default
budget in this environment, so these were run with CI-sized time budgets.
All stay required evidence for qualification.

Deferred this phase: low-power support (`core0_pad_lpmd_b` unconnected), DFT
(scan/mbist tied off), the debug SBA AXI master (unconnected), and HP Linux
re-qualification timing/performance evidence. The repo-owned OpenSBI platform
registers `fdt_irqchip_init` (v1.9 supports the `thead,c900-plic` match with
T-Head delegation fixups), so the C906-internal PLIC is initialized by
OpenSBI before the kernel probes it; the minimal Linux acceptance uses the
`hvc0` console, the SBI TIME timer, and the polled mailbox path.

## Historical VexiiRiscv evidence (pre-swap)

### Reproduction (VexiiRiscv)

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
and CRC. In ordinary builds only smoke enters the GA2D/cache lifecycle
protocol. LP alone owns the final SYSCTRL TEST_STATUS write for all workloads.

The private NPU-P6 acceptance build reuses workload 1's four-entry transport so
the frozen corpus shard occupies the existing `Image` slot. Its compile-time
`RS_NPU_P6_ACCEPTANCE` path deliberately continues beyond the Linux-ready
checkpoint into the same GA2D/cache lifecycle protocol; an ordinary Linux
build still terminates at Linux-ready. This does not add a workload number or
change the V2 header ABI.

The `ihp130-apu` evidence profile likewise uses workload 1 only as the existing
four-entry transport. Its application-specific `apu_release` LP loader owns the
APU acceptance semantics; that bundle label does not claim a Linux boot result.

### Measured runs (VexiiRiscv)

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

### RT-Thread first-schedule failure and correction

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

### Linux firmware reservation correction

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

### Coverage limits

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
