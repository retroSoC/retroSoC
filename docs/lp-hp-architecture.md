# LP/HP Architecture and Delivery Contract

## Status

The committed `configs/ci/ihp130-hp.mk` profile is the executable MVP for the
retroSoC asymmetric LP/HP architecture. Hazard3 is the low-performance control
core (LP, hart 0) and a generated RV32 VexiiRiscv instance is the
high-performance Linux core (HP, hart 1). Both run from the fixed 72 MHz system
clock in this profile.

The profile proves integration, build, and lint readiness. A repeatable Linux
boot, the 2.5x performance gate, physical timing closure, and hardware
qualification remain release gates until their evidence is recorded. This MVP
must not be described as cache coherent, hot-reset safe, secure boot capable,
or power isolated.

The commercial reference analysis and product positioning are in
[SoC Family Product Positioning](soc-family-positioning.md). The implementation
reuses the most relevant patterns from heterogeneous Linux/MCU devices:

- an always-available management core owns application-core release;
- Linux receives standard CLINT/PLIC privilege interrupts and a dedicated
  console;
- a mailbox is the versioned cross-core control path;
- boot artifacts and generated CPU RTL have locked, reviewable provenance;
- performance claims are machine checked from measurements, not inferred from
  CPU configuration.

The MVP deliberately avoids presenting the HP core as an ordinary C0-C3 user
core. Those legacy slots remain available and software selected. HP has a
fixed hart ID, reset vector, bus master, interrupt topology, and Linux ABI.

## Compute and Memory Topology

| Property | LP | HP |
| --- | --- | --- |
| Core | Hazard3 | generated VexiiRiscv |
| Hart ID | 0 | 1 |
| ISA | RV32IM plus existing CSR/debug profile | RV32IMAFDC, S/U mode, Sv32 |
| Clock | 72 MHz | 72 MHz |
| Primary role | boot, lifecycle, diagnostics, recovery | OpenSBI and Linux |
| Reset | root reset controller | SYSCTRL release plus HP debug reset request |
| JTAG | shared pads, reset default owner | selectable only while HP is held reset |
| Main-memory view | 32-bit AXI4 | three AXI64 planes converted to one 32-bit AXI4 master |

HP instruction-cache, data-cache, and uncached MMIO ports each pass through a
64-to-32 adapter. The adapters preserve IDs and responses, split or combine
64-bit beats, honor backpressure, and track lanes across AXI burst types. The
transaction mux prioritizes uncached MMIO, then data cache, then instruction
cache and permits one transaction at a time. A Common `axi4_regslice` separates
the HP compatibility plane from the legacy system fabric.

The current system interconnect accepts up to sixteen 32-bit beats. Therefore
an HP 64-bit burst is limited to eight source beats. The generated 16 KiB,
four-way instruction and data caches use eight-beat refill/writeback geometry.
This is a compatibility architecture for the current 64 MiB SDRAM, not the
native 64-bit memory plane required for a later performance product.

There is no hardware cache coherency between LP, HP, DMA, or user cores. LP
loads HP memory before releasing HP, when HP caches are cold. Any later shared
buffer protocol must define ownership transfer and explicit cache maintenance.
Linux must not map device registers as cacheable.

## Platform ABI

| Block | Address | Purpose |
| --- | --- | --- |
| HP ACLINT | `0x02000000` | hart 1 machine software/timer interrupts, 1 MHz timebase |
| HP PLIC | `0x0C000000` | 31 usable sources and M/S contexts |
| UART1 | `0x10018000` | dedicated HP/SBI console pads; DMA request remains available |
| DMA | `0x1000A000` | LP-managed TCD/data movement; channel 6 reserved for HP boot |
| HP mailbox | `0x10019000` | command/event, argument, sequence, and dual doorbells |
| SDRAM | `0x38000000`-`0x3BFFFFFF` | shared 64 MiB Linux main memory |

PLIC source 1 is UART1 and source 2 is the HP mailbox. The LP interrupt map
retains existing assignments and adds mailbox IRQ 25 and UART1 IRQ 26. The
PLIC implements the priority, enable, pending, threshold, claim, and complete
registers needed by the Linux SiFive PLIC driver; it is not an AIA, MSI, or
virtualization interrupt controller.

SYSCTRL adds `HP_CTRL` at `0xA4`, `HP_STATUS` at `0xA8`, and `DEBUG_SELECT` at
`0xAC`. Reset defaults keep HP asserted and JTAG connected to LP. Selecting HP
debug while HP is running is rejected by hardware. The MVP release bit does
not drain transactions before reasserting reset, so software must not use it
as a safe hot-reset interface.

The mailbox RTL and `<retrosoc/hal/hp_mailbox.h>` are handwritten definitions.
`tests/test_hp_boot_bundle.py` checks their register offsets against each other.
Sequence zero means no message. Writers publish code and argument before the
nonzero sequence and doorbell; readers use the sequence as the validity token.

## Generated Core Contract

`make CONFIG=configs/ci/ihp130-hp.mk vexii-generate` runs the locked Scala
configuration in `scripts/vexiiriscv/GenerateRetroSocHp.scala`. It verifies the
source revision from `dependencies/dependencies.lock.json` and writes RTL,
filelist, source status, and SHA-256 provenance below the selected
`build/<variant>/generated/vexiiriscv/` directory. Generated VexiiRiscv RTL is
never Git tracked.

The fixed configuration enables dual issue, late ALU, full bypassing, branch
prediction, PMP, performance counters, debug triggers, RV32IMAFDC, Sv32, and
separate 16 KiB instruction/data caches. Changing any of these is a new
`HP_CONFIG` and requires a separate profile, software ABI review, synthesis,
timing, and benchmark evidence.

## Boot Flow

The `hp_boot` LP application is linked wholly into the 32 KiB on-chip SRAM so
loading OpenSBI at the SDRAM base cannot overwrite running management code.
The `hp-bundle` target combines LP firmware and the four HP artifacts in the
16 MiB boot flash:

| Artifact | Load address | Maximum |
| --- | --- | --- |
| OpenSBI `fw_jump.bin` | `0x38000000` | 512 KiB |
| `retrosoc_hp.dtb` | `0x38080000` | 64 KiB |
| Linux `Image` | `0x38400000` | 12 MiB |
| `rootfs.cpio.gz` | `0x39000000` | 8 MiB |

The bundle starts at flash offset `0x00100000`. Its 128-byte v1 header contains
four whitelisted entries with type, flash offset, load address, byte count,
CRC32, and required flags. LP validates the header, flash and SDRAM bounds,
fixed destinations, sizes, alignment, and every payload CRC. It copies with
32-bit writes and full readback for control payloads; large payloads use full
flash CRC validation without destination rereads. It issues a memory fence
before releasing HP.
CRC detects accidental corruption; it is not authentication. DMA V2 channel 6
loads each entry with a 64-byte TCD and hardware CRC32. If DMA validation or
transfer fails, LP falls back to the existing CPU copy path before releasing
HP. Descriptor and payload memory are explicitly non-coherent; LP publishes
them with `fence rw,rw` and HP starts only after ownership transfer.

OpenSBI is built from an external repo-owned platform directory without
patching its locked source. The platform maps OpenSBI hart index 0 to hardware
hart ID 1, registers the HP ACLINT, and provides the SBI debug console through
UART1. OpenSBI starts at `0x38000000` and directly enters Linux at
`0x38400000`, passing the DTB at `0x38080000`; U-Boot is not part of the MVP.

Buildroot creates the RV32 glibc toolchain and a small initramfs. Linux starts
from `tinyconfig` and merges `app/ports/linux/linux/retrosoc_hp.config` so the
Image stays within the fixed flash budget. Its final init script prints
`retroSoC HP Linux ready` and posts mailbox event 1 with argument `0x4C4E5801`.
LP then writes the normal sticky `TEST_STATUS` pass result, giving simulation a
deterministic terminal verdict.

```sh
make setup-hp-linux
make CONFIG=configs/ci/ihp130-hp.mk hp-linux
make CONFIG=configs/ci/ihp130-hp.mk hp-bundle
make CONFIG=configs/ci/ihp130-hp.mk SIMU=VERILATOR comp sim
```

The setup flow locks VexiiRiscv, OpenSBI, Linux, and Buildroot by full Git
revision. Interrupted HP source fetches are repaired in place on retry.

## Performance and Verification

LP and HP claims use the same 72 MHz frequency and CoreMark mode. After both
machine-readable reports exist, enforce the selected requirement with:

```sh
make hp-performance-check \
  LP_COREMARK_REPORT=<lp-coremark.json> \
  HP_COREMARK_REPORT=<hp-coremark.json>
```

The gate writes `meta/lp-hp-performance.json` and requires HP CoreMark/MHz to
be at least 2.5 times LP. An HP report must come from executed Linux, RTL
simulation, FPGA, or silicon with its provenance retained. A predicted score
is not acceptable evidence.

Current directed verification covers the AXI downsizer, 8-master interconnect,
mailbox, PLIC, topology generation, pad ring, generated-source boundary,
bundle CRC/layout, HAL/RTL offset parity, HP firmware build, RTL style, and
full-design Verilator lint. Release qualification additionally requires a
successful Linux boot log, both CoreMark reports, IHP130 synthesis/STA, and the
normal PR regression.

## Commercial Alignment Roadmap

The next phases are ordered by risk and dependency:

1. Complete repeatable Linux boot and native UART/mailbox kernel drivers;
   retain boot-time and error-injection evidence.
2. Replace the serialized compatibility plane with a native burst-capable
   memory path, add HP QoS/wait counters, and close the 2.5x performance gate.
3. Add lifecycle handshakes that block new HP requests, drain accepted traffic,
   request Linux shutdown, apply cache maintenance, and only then reset.
4. Add clock gating, power isolation/retention controls, CDC/RDC signoff, and
   measured state-transition latency and energy.
5. Add immutable boot ROM, signature verification, rollback protection, OTP
   key/lifecycle state, debug authentication/disable, firewall regions, and a
   documented threat model. CRC32 is then retained only for transport errors.
6. Add RAS evidence: ECC/parity coverage, watchdog escalation, bus timeout,
   machine-check logging, fault injection, and recovery/reset campaigns.
7. Add production DFT, MBIST, trace, PMU event definitions, coverage closure,
   software update/recovery, long-duration stress, and PVT/package signoff.

Avoid claiming a commercial big.LITTLE-style coherent cluster: this design is
asymmetric multiprocessing with independent software roles. Also avoid direct
LP reset of a running HP, shared cacheable buffers without an ownership
protocol, Linux control over root lifecycle registers, and per-PDK frequency
claims derived only from RTL simulation.
