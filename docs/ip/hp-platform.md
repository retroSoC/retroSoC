# HP RV64 Operating-System Platform

## Approved migration contract

The RV64 migration approved on 2026-09-25 extends the existing HP platform in
the phases below. These are requirements, not claims of completed validation.
LP remains the RV32 Hazard3 management hart (hart 0). HP is hart 1, a T-Head
OpenC906 core from [XUANTIE-RV/openc906](https://github.com/XUANTIE-RV/openc906)
(Apache-2.0), locked in `dependencies/dependencies.lock.json` and integrated
from its pre-generated `C906_RTL_FACTORY/gen_rtl` DEFAULT configuration:
RV64GC (RV64IMAFDC plus Zicsr and Zifencei) with M/S/U modes and Sv39,
32 KiB instruction and data caches with 64-byte lines, an eight-region PMP,
and a 16K-entry BHT. The earlier VexiiRiscv-based RV64 integration is
superseded; its validation evidence is retained only as historical in
[HP RV64 validation](../hp-rv64-validation.md). VexiiRiscv remains in the
repository solely as the frozen Std-series generator asset
(`scripts/vexiiriscv/GenerateRetroSocStd.scala`, driven by
`make std-vexii-generate`); Mini no longer consumes it and Mini profiles have
no `HP_CONFIG` selector.

The C906 drives 40-bit addresses; Mini physical addresses remain 32 bits and
the reset vector remains `0x38000000`. The core exposes a single 128-bit AXI4
master (8-bit IDs, `axim_clk_en` tied high for 1:1 clocking) that a
serializing `axi4_downsizer_128to64` and `axi4_mmio_demux` split into HP
data-fabric master slot 0 and the MMIO window `0x02000000-0x2FFFFFFF`; the
former separate I-cache/D-cache/MMIO port structure and crossbar master slot 1
are retired (slot 1 is tied idle, ID-prefix map preserved). MMIO continues
through the existing 64-to-32 downsizer/gate/CDC chain into the AXI32/APB32
control plane. Software accesses peripheral registers as 32-bit words,
including the two halves of CLINT timer registers. No new CDC or
hardware coherency is introduced. LP retains SYSCTRL and terminal-status
ownership, DMA channel 6, SDRAM initialization, and HP release control.

OpenC906 implements no Zicbom, Zicntr, or Zihpm; cache maintenance uses the
T-Head custom-0 `dcache.cva`/`dcache.iva` instructions. Debug uses the C906
internal Debug Module behind the external JTAG DTM (`tdt_dmi_top`).
OpenC906 hardwires `mhartid=0` upstream; retroSoC substitutes the reviewed
override `rtl/mini/ip_overrides/aq_sysio_kid.v` (only change:
`sysio_core_hartid = 3'd1`) during build-time filelist generation through
`scripts/generate_openc906.py`, which guards the pinned upstream sha256. A
second reviewed override, `rtl/mini/ip_overrides/sysmap.h`, replaces the
upstream default sysmap region table (which targets a 40-bit reference map
and would mark the Mini peripheral window cacheable/bufferable) with the Mini
address map: the MMIO window `0x02000000`-`0x2FFFFFFF` — including the
core-internal CLINT/PLIC window — is strong-order/non-cacheable device memory
as the OpenC906 user manual requires; SRAM/SDRAM/PSRAM/OPI and the flash/XIP
windows stay cacheable. The vendored checkout is never modified. Deferred
this phase: low-power support
(`core0_pad_lpmd_b` unconnected), DFT (scan/mbist tied off), the debug SBA AXI
master (unconnected), ASIC memory-macro replacement for the behavioral FPGA
SRAM models, and HP Linux re-qualification timing/performance evidence.

### Boot bundle V2

The little-endian header remains 128 bytes at flash offset `0x00100000`, with
four 24-byte entry slots and CRC32/ISO-HDLC protection. Version is 2. Header
word 7 identifies workload: 1 Linux, 2 GA2D smoke, 3 RT-Thread. Linux has four
entries (types 1 OpenSBI, 2 DTB, 3 Linux Image, 4 uncompressed CPIO), retaining
the established addresses and limits. Smoke and RT-Thread have one executable
entry of type 5, at `0x38000000`, at most 512 KiB; unused entries are zero.
Version 1, unknown workloads, incorrect entry counts/types/addresses, empty
payloads, overlaps, out-of-range sizes, and bad CRCs are rejected before HP
release. Build manifests record RV64, workload, sources and artifact hashes;
builders verify executable ELF class and RISC-V machine identity.

### Software acceptance protocol

Linux publishes event 1, argument `0x4c4e5801`, sequence 1 only after its
userspace acceptance succeeds. On a software failure it publishes event 3
with a nonzero error code. LP prints `HP_LINUX_READY` and terminates on Linux
success without entering the GA2D protocol.

RT-Thread publishes ready event 1, argument `0x52545401`, sequence 1 after
enabling the mailbox-doorbell PLIC ID (18) in the machine context. LP sends
command `0x52545402`,
argument `0x12345678`, sequence 1. Its ISR clears the HP mailbox source and
completes the PLIC claim; the test thread verifies the received message. Once
all tests pass, HP publishes event 2, argument `0x52545401`, sequence 2.
Event 3 reports a nonzero failure code at sequence 1 or 2. LP alone writes
SYSCTRL TEST_STATUS and prints `HP_RTTHREAD_PASS` on success. Publication is
code, argument, sequence, `fence iorw, iorw`, then doorbell. No shared cached
memory is used by this test protocol. Smoke retains the GA2D and cache-clean
handshake documented by its existing payload.

RT-Thread uses the official v5.3.0 commit
`99428a1e7f7447955aa860f7c969273a12095b8f` without vendor source modifications.
The BSP uses the common RISC-V M-mode port, static threads and IPC objects,
1000 Hz ticks, UART1, the internal CLINT MSIP/MTIMECMP pair, and the internal
PLIC plus the mailbox.
The first test image covers integer RV64 computation/context, preemption,
semaphore and message queue behavior, timeouts, and external mailbox IRQ.
RT-Smart, networking, filesystems, and floating-point task qualification are
outside this phase; hardware F/D support remains enabled.

Linux uses RV64 OpenSBI FW_JUMP, Sv39, and a static minimal BusyBox userspace.
The DT reserves `0x38000000..0x3807ffff` with `no-map` for resident OpenSBI;
Linux must never allocate or directly map that firmware window.
Its dedicated `/init` explicitly mounts devtmpfs, procfs, sysfs and tmpfs,
checks device nodes, file round trips and child execution, and reports through
the mailbox. Initial CPIO includes `/dev/console`. Effective kernel config,
not merely its fragment, must enable the required executable, console,
memory-management, filesystem and /dev/mem options. The acceptance CPIO is
uncompressed and does not run the full Buildroot services sequence.

### Development order and verification

#### Phase 2 - RV64 HP core and platform migration

Originally executed against a generated VexiiRiscv core; that integration is
superseded by the OpenC906 swap and its evidence is historical. The current
phase integrates the locked OpenC906 DEFAULT configuration, all PRODUCT
profiles, manifests and core reports. Use separate RV32 LP and RV64 HP tools.
Validate the 128-to-64 serializing downsizer, the MMIO demux, narrow MMIO
lanes, 64-bit memory accesses, and the migrated GA2D/cache-lifecycle smoke in
IHP130 Verilator.

#### Phase 3 - RT-Thread dependency, BSP and acceptance

Lock sources and build tools, add the self-owned BSP and V2 loader/packager,
and run `hp-rtthread-sim` from its committed IHP130 profile. All individual
test markers, `HP_RTTHREAD_PASS`, and `SIM_TEST_PASS code=0` are required.
Negative bundle and mailbox tests must demonstrate fail-closed behavior.

#### Phase 4 - RV64 Linux minimal-initramfs acceptance

Migrate OpenSBI, Linux, Buildroot and DTB together, verify effective configs,
then run real SoC `hp-linux-sim`. Required markers include Linux userspace
checks, `retroSoC HP Linux ready`, `HP_LINUX_READY`, and `SIM_TEST_PASS code=0`.
Unexpected console corruption remains a failure requiring diagnosis.

#### Phase 5 - Documentation and delivery evidence

Update architecture, guides and publication source bindings. Preserve prior
RV32 and pre-swap VexiiRiscv evidence as historical. Each workload writes
separate run logs and
structured results; an interrupted or ongoing run cannot reuse an old pass.
Run affected host/Python/C/RTL checks and IHP130 behavioral regressions.
Synthesis, netlist simulation, STA, and synthesis-dependent metrics are
explicitly deferred by user instruction, as are SRAM macro replacement,
CDC/RDC/physical signoff and commercial qualification. No PPA claim is made.

Reference boundaries: [RT-Thread v5.3.0](https://github.com/RT-Thread/rt-thread/releases/tag/v5.3.0)
supplies the OS/CPU port; the repository owns board integration. The C906
internal CLINT/PLIC (the `thead,c900-clint`/`thead,c900-plic` device-tree
bindings) and the locked OpenSBI platform supply the interrupt and supervisor
boot patterns; no third-party board register map is imported.

The LP/HP profile adds a bidirectional mailbox at `0x10019000` as a
self-owned APB4 peripheral. Its role in boot and lifecycle control is defined
by [LP/HP Architecture](../lp-hp-architecture.md).

## Interrupt and timer architecture

The former SoC-level HP ACLINT at `0x02000000` and HP PLIC at `0x0C000000`
are removed from the HP path; their self-owned RTL sources remain in the
repository but are no longer instantiated. Interrupt and timer delivery now
uses the CLINT and PLIC internal to the C906, which follow the T-Head c900
register layouts and are decoded inside the core BIU at the 128 MiB-aligned
window base `0x08000000`. That window never reaches the SoC fabric;
`rtl/mini/address_map/memory_map.json` reserves it as `HP_C906_SYS`:

| Address | Function |
| --- | --- |
| `0x08000000` | internal PLIC (`thead,c900-plic`) |
| `0x0C000000` | internal CLINT (`thead,c900-clint`): MSIP at +`0x0`, MTIMECMP at +`0x4000`, SSIP at +`0xC000`, STIMECMP at +`0xD000` |

The CLINT at `0x10020000` remains the LP/global CLINT and the mtime source.
Its mtime is delivered to the C906 through `pad_cpu_sys_cnt`; HP software
reads the `time` CSR and has no memory-mapped mtime.

SoC interrupt source numbers are unchanged at the boundary: source 1 is
UART1, source 2 is the HP-side mailbox doorbell, source 3 is EXT-H, and
sources 4 through 12 are central DMA, USB2, SDIO0, SDIO1, SPI-SD, JPEG, APU,
GA2D, and the NPU shell respectively. Sources 13 and above are reserved and
tied low. Resource-owned sources are suppressed unless HP is the exclusive
owner. The C906 maps external input *i* to PLIC ID *i*+16, so software claims
these sources as PLIC IDs 17 through 28; IDs 0-15 are reserved/internal.
LP-to-HP notification is exclusively the mailbox doorbell (PLIC ID 18); the
former LP-writes-HP-MSIP path no longer exists.

## Mailbox

LP writes the `LP_*` bank and rings `LP_DOORBELL`, which sets the HP interrupt
state. HP writes the `HP_*` bank and rings `HP_DOORBELL`, which sets the LP
interrupt state. State is sticky W1C and is qualified by a separate enable for
each destination.

| Offset | Register | Access | Purpose |
| --- | --- | --- | --- |
| `0x000` | `IP_VERSION` | RO | `0x00010000` |
| `0x004` | `CAPABILITY` | RO | `0x00000007` |
| `0x010` | `LP_COMMAND` | RW | LP-to-HP message code |
| `0x014` | `LP_ARG0` | RW | LP-to-HP argument |
| `0x018` | `LP_SEQUENCE` | RW | LP publication sequence; zero means none |
| `0x01C` | `LP_DOORBELL` | WO | Set HP interrupt state |
| `0x020` | `HP_EVENT` | RW | HP-to-LP event code |
| `0x024` | `HP_ARG0` | RW | HP-to-LP argument |
| `0x028` | `HP_SEQUENCE` | RW | HP publication sequence; zero means none |
| `0x02C` | `HP_DOORBELL` | WO | Set LP interrupt state |
| `0x030`/`0x034`/`0x038`/`0x03C` | LP interrupt state/enable/status/test | mixed | LP destination IRQ control |
| `0x040`/`0x044`/`0x048`/`0x04C` | HP interrupt state/enable/status/test | mixed | HP destination IRQ control |

The publication order is code, argument, sequence, memory fence, then
doorbell. `<retrosoc/hal/hp_mailbox.h>` supplies the LP-side API. The initial
Linux userspace acceptance script reports event 1, argument `0x4C4E5801`, and
sequence 1 after init; this is a bring-up verdict, not a general Linux mailbox
driver ABI.

`tests/rtl/hp_mailbox_tb.sv` covers mailbox register and interrupt behavior.
`tests/rtl/plic_tb.sv` covers the retained self-owned PLIC RTL, which is no
longer part of the HP interrupt path. `tests/test_hp_boot_bundle.py` enforces
the handwritten mailbox RTL/C offset parity. Production work still requires a
Linux mailbox driver, concurrent sequence/wrap policy, malformed-message
tests, lifecycle timeouts, and fault-injection coverage.
