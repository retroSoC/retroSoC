# HP RV64 Operating-System Platform

## Approved migration contract

The RV64 migration approved on 2026-09-25 extends the existing HP platform in
the phases below. These are requirements, not claims of completed validation.
LP remains the RV32 Hazard3 management hart (hart 0). HP is VexiiRiscv hart 1,
RV64IMAFDC_Zicbom_Zicntr_Zihpm, with M/S/U modes and Sv39. Physical addresses
remain 32 bits; the reset vector remains `0x38000000`. The existing 16 KiB
four-way I/D caches, 64-byte lines, 9-bit ASIDs, PMP, and clocks remain fixed.
I/D and cacheless MMIO use AXI64 at HP; MMIO is downsized to the existing
AXI32/APB32 control plane. Software accesses peripheral registers as 32-bit
words, including the two halves of CLINT timer registers. No new CDC or
hardware coherency is introduced. LP retains SYSCTRL and terminal-status
ownership, DMA channel 6, SDRAM initialization, and HP release control.

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
enabling PLIC source 2 in machine context 0. LP sends command `0x52545402`,
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
1000 Hz ticks, UART1, hart-1 MSIP/MTIMECMP, and the existing PLIC/mailbox.
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

Migrate the fixed generator, all PRODUCT profiles, manifests and core reports;
retain the locked VexiiRiscv revision. Use separate RV32 LP and RV64 HP tools.
Validate generated port widths, narrow MMIO lanes, 64-bit memory accesses,
and the migrated GA2D/cache-lifecycle smoke in IHP130 Verilator.

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
RV32 evidence as historical. Each workload writes separate run logs and
structured results; an interrupted or ongoing run cannot reuse an old pass.
Run affected host/Python/C/RTL checks and IHP130 behavioral regressions.
Synthesis, netlist simulation, STA, and synthesis-dependent metrics are
explicitly deferred by user instruction, as are SRAM macro replacement,
CDC/RDC/physical signoff and commercial qualification. No PPA claim is made.

Reference boundaries: [RT-Thread v5.3.0](https://github.com/RT-Thread/rt-thread/releases/tag/v5.3.0)
supplies the OS/CPU port; the repository owns board integration. The existing
CLINT/PLIC architecture and locked OpenSBI platform supply the interrupt and
supervisor boot patterns; no third-party board register map is imported.

The experimental LP/HP profile adds a 32-source, two-context PLIC at
`0x0C000000` and a bidirectional mailbox at `0x10019000`. Both are self-owned
APB4 peripherals. Their role in boot and lifecycle control is defined by
[LP/HP Architecture](../lp-hp-architecture.md).

## PLIC

Source 0 is permanently reserved. Source 1 is UART1, source 2 is the HP-side
mailbox doorbell, source 3 is EXT-H, and sources 4 through 10 are central DMA,
USB2, SDIO0, SDIO1, SPI-SD, JPEG, and APU respectively. Source 11 is GA2D and
source 12 is the NPU shell. Sources 13 through 31
are reserved and tied low. Resource-owned sources are suppressed unless HP is
the exclusive owner. Each source has a three-bit priority. Context 0 drives HP
machine external interrupt and context 1 drives HP supervisor external interrupt.

| Address offset | Register | Access |
| --- | --- | --- |
| `0x000000 + 4 * source` | source priority | RW |
| `0x001000` | pending bits 31:0 | RO |
| `0x002000 + 0x80 * context` | enable bits 31:0 | RW |
| `0x200000 + 0x1000 * context` | threshold | RW |
| `0x200004 + 0x1000 * context` | claim/complete | RO/RW |

Claim returns the lowest source ID at the greatest priority strictly above the
context threshold, clears its pending bit, and marks it claimed. Writing that
nonzero ID to the same context's claim/complete register completes it. A level
source that remains asserted becomes pending again after completion. Priority
zero disables delivery. The MVP implements one 32-bit pending/enable word and
does not implement MSI, AIA, virtualization, or affinity routing.

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

`tests/rtl/plic_tb.sv` and `tests/rtl/hp_mailbox_tb.sv` cover register and
interrupt behavior. `tests/test_hp_boot_bundle.py` enforces the handwritten
mailbox RTL/C offset parity. Production work still requires a Linux mailbox
driver, concurrent sequence/wrap policy, malformed-message tests, lifecycle
timeouts, and fault-injection coverage.
