#import "../style.typ": *
#import "../figures.typ": *

= Software
== Boot Configuration, Initialization and Recovery <boot-configuration>
The management hart starts from the reset flash alias. Normal firmware composition and memory
placement depend on the committed application and linker profile. The HP acceptance example
instead uses the SRAM-resident `hp_boot` image and validates an external boot bundle before
releasing HP. It must not be assumed that every bringup image automatically boots Linux.

#figure(boot-diagram(), caption:[HP boot example. Validation failure retains LP recovery control and prevents normal HP handoff.])<boot-flow>

The HP bundle contains locked OpenSBI, Linux, device-tree and initramfs inputs. LP validates
the header and payload bounds, attempts transfer with the boot DMA context and CRC, and
falls back to a software copy/CRC if that attempt fails. It fences memory, clears the LP
mailbox interrupt and requests HP release. It then waits for the expected readiness event;
it does not publish entry/DTB addresses through a boot mailbox before release.
#source-note("docs/lp-hp-architecture.md", title:"Boot-bundle ABI, lifecycle and failure handling")

=== Prerequisites and image layout
Use the dedicated HP profile for the acceptance loader. It runs from on-chip SRAM and waits
for the SDRAM controller to be ready and free of initialization/error state. The software
does not choose an arbitrary external device timing configuration during this wait. External
flash placement, SDRAM wiring and timing must already match the selected integration.

#ds-table("hp-image-layout",[HP image locations extracted from the boot-bundle header],
  ([Artifact],[Load address],[Maximum allocation]),
  data.system_reference.boot_layout.map(r=>(r.name,code(r.address),[#r.max_size_kib KiB])),
  widths:(1.2fr,1fr,1fr),notes:[Maximum allocation is a bundle bound, not the actual image size. The full SDRAM address region is listed in Address Mapping.])
The build uses OpenSBI FW_JUMP with a fixed Linux entry and DTB address, without a U-Boot
stage. The bundle header contains a format version, required entry types, lengths, fixed
load locations and CRCs. Keep the image builder, package builder, loader header and selected
source revision together. A larger image must not be silently truncated to fit its allocation.

The manual preparation/build entry points are the existing #code("make setup-hp-linux") and
#code("make CONFIG=configs/ci/ihp130-hp.mk hp-linux") flows. Setup obtains locked resources;
building the Linux artifacts alone does not demonstrate a successful target boot. See the
port guide for the generated output layout and boot packaging commands.

#include "boot-bundle-format.typ"

=== Loader sequence and completion
+ Initialize the LP console, hold HP in reset, select management debug and confirm HP presence/reset.
+ Wait for SDRAM readiness with the loader's bounded wait. A ready controller still requires
  the external device/model and selected timing to be correct.
+ Read the bundle header. Check magic, format version, header/entry counts, required flags,
  total size, fixed entry order, flash bounds, destination bounds and header CRC.
+ For each entry, attempt the DMA TCD transfer with expected CRC and check status, transferred
  length and CRC result. If that attempt fails, execute the existing software-copy/CRC fallback.
+ Apply the memory fence, clear the LP mailbox interrupt, request release, and check the
  immediate HP status result. Observe #code("HP_BOOT_RELEASED") only as a release checkpoint.
+ Wait for a nonzero-sequence mailbox message. The expected event/argument reports
  #code("HP_LINUX_READY") and the common sticky test pass. An unexpected message is a failure.

The software fallback computes CRC from bytes read from the source while copying. It performs
full destination readback only for entries up to the loader's small-entry threshold; it must
not be described as a complete large-image destination readback test. CRC checks protect
integrity, not image origin or rollback policy.

=== Failure branches and supervision boundary
#ds-table("hp-boot-failures",[HP loader checkpoints and diagnostic result codes],
  ([Checkpoint],[Code / observation],[Result and required response]),
  (([Console initialization],[1],[Common failed verdict; establish a usable diagnostic path.]),
   ([HP prerequisite state],[2],[HP presence/reset/debug setup did not meet requirements.]),
   ([SDRAM readiness],[3],[Bounded wait failed; inspect memory configuration and controller status.]),
   ([Bundle header],[4],[Reject the bundle; rebuild matching images and header rather than relaxing bounds.]),
   ([Payload loading],[5-8],[Both DMA and software paths failed for the respective entry.]),
   ([Release/checkpoint],[9],[Inspect requested/actual HP state and lifecycle faults.]),
   ([Unexpected ready event],[10],[Check software revisions, mailbox payload and boot epoch.]),
   ([No ready message],[No firmware-local deadline],[The loop keeps waiting. The simulator deadline is external to the loader.])),
  widths:(1fr,0.85fr,2.25fr))
The failure helper requests HP reset and writes a failed test verdict; it does not implement
an automatic image retry or signed recovery image selection. A board-level watchdog,
supervisor deadline or replacement loader policy is additional integration work. After a
failed release or forced stop, inspect actual reset/drain state before reusing HP memory.

For target acceptance, capture profile/image hashes, LP load/release checkpoints, the expected
Linux readiness event and the final simulator verdict. Do not treat UART startup alone as
success. A complete Linux peripheral qualification requires the separate support matrix.

#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #source("app/apps/hp_boot/main.c",title:"Executed boot checks, copy fallback and failure codes") ·
  #source("app/apps/hp_boot/hp_boot_bundle.h",title:"Image types, addresses and allocation bounds") \
  #source("scripts/build_hp_linux.py",title:"OpenSBI FW_JUMP and Linux artifact composition") ·
  #source("scripts/package_hp_boot.py",title:"Bundle generation and layout checks")
]


#include "image-maintenance.typ"

== Runtime, SDK and Shell
The freestanding CRT is organized into RISC-V architecture support, core, HAL, library and
service layers. Applications consume public headers through `<retrosoc/...>`, use the `rs_`
namespace and handle `rs_status_t` failures. Board support and middleware live in the
application layer. The retired TinySDK/TinyShell names are replaced by the current CRT and
shell application terminology.

The SDK remains freestanding. Hardware-facing APIs use bounded transfers and timeout-based
waits. Drivers must observe ownership, clock transitions, cache maintenance and peripheral
error returns. A HAL interface does not imply a Linux kernel driver for the same IP.
#source-note("crt/README.md", title:"Freestanding runtime and SDK layout")

#include "software-runtime.typ"

== Applications
#ds-table("apps", [Application roles],
  ([Application], [Role / boundary]),
  (([bringup], [Hardware initialization and diagnostics]),
   ([shell], [Interactive firmware shell and peripheral commands]),
   ([benchmark / coremark], [Profile-selected workloads and measured performance flows]),
   ([debug], [Debug-transport acceptance image]),
   ([hp_boot], [SRAM-resident HP bundle loader and handoff example]),
   ([ci_smoke], [Small regression verdict image selected by CI])),
  widths:(0.85fr,2.2fr),
)
Supported combinations are the committed build profiles and application manifests, not every
possible combination of compiler variables. Simulation passes require successful command
completion, the configured success marker and no failure/timeout markers.
#source-note("app/README.md", title:"Application composition and current profiles")

#include "application-diagnostics.typ"

== Linux and Driver Status
The repository provides the asymmetric Linux integration path with OpenSBI and Buildroot
inputs. Linux boot, native driver coverage, performance, cache-maintenance correctness and
physical implementation remain distinct qualification topics. The source-level matrix in
@software-support describes the currently indexed interfaces and missing evidence. It does
not assert complete Linux peripheral qualification or sustained application performance.

#include "linux-runtime.typ"

== Software Support and Validated Configurations <software-support>
This matrix records the software interfaces indexed for the reviewed hardware snapshot.
HAL availability, a device-tree binding, test source and an independently reviewable successful
run are different evidence levels. The publication does not turn a discovered file into a
target-validation claim. "Tests available" identifies a reproducible test entry point whose
run must still be evaluated with its configuration and tool dependencies.

=== Bare-metal and Linux support matrix
#ds-table("software-support",[Published software paths and validation evidence by IP],
  ([IP],[Bare-metal / platform interface],[Linux integration],[Evidence indexed]),
  data.system_reference.support.map(r=>(link(label(r.id),r.title),r.hal,r.linux,
    [#r.verification \ #if r.tests.len()>0 {source(r.tests.first(),title:"Test entry point")} else {[See IP source links.]}])),
  widths:(0.9fr,1.05fr,1.5fr,0.8fr))
No FPGA or silicon pass report is attached to these rows. Existing documents can describe
earlier test activity; such historical summaries are not promoted to a pass for this exact
publication configuration without a reviewable matching report. The content index includes
the source paths used for each row and allows later reports to be bound to a profile and revision.

=== Selecting and validating a software path
+ Read the IP identity/capability and compare it with the driver's expected register ABI.
+ Identify whether the selected path is an LP HAL, an OpenSBI platform function, a standard
  kernel binding or a custom Linux driver that still needs implementation.
+ Verify clocks, reset state, DMA buffers, resource owner and IRQ route before enabling the driver.
+ Run a bounded functional transaction, an error/timeout case and the relevant reset/handoff
  case on the selected platform. Record the actual command, configuration and artifact identity.
+ Promote only the tested scope. A standalone IP test does not establish simultaneous
  multimedia throughput, physical pin timing or whole-system Linux stability.

The supplied Linux console uses #code("console=hvc0 earlycon=sbi"). OpenSBI contains the UART1
console implementation and ACLINT timer/software-interrupt setup. UART1 and mailbox DT nodes
reserve their platform ABI; the presence of #code("status = okay") is not evidence that a
native custom driver is available or correct. No generic HAL-to-Linux bridge is supplied here.

=== Validated-configuration record
A reusable run record must name the source commit, committed profile, generated HP core,
toolchain/kernel/OpenSBI versions, device/model or board, command, log/result digest and
tested feature set. Record skips and missing tools explicitly. Keep simulation, FPGA and
silicon stages separate and retain failed runs as diagnostics rather than overwriting them
with a broad "supported" label.
#source-note("publications/datasheets/system-reference.json",title:"Reviewed support and limitation index")
#source-note("app/ports/linux/README.md",title:"Current SBI console and native-driver boundary")
#source-note("app/ports/linux/opensbi/retrosoc_hp/platform.c",title:"OpenSBI console and local-interrupt implementation")

= Implementation
== SoC Integration
The committed product profiles instantiate fixed LP/HP harts and EXT-L/EXT-H slots. IHP130,
GF180, SKY130 and ICS55 have different macro availability and validation boundaries. The
IHP130 reference enables the 32 KiB SRAM interface and macro; committed ICS55 profiles
intentionally keep SRAM and PLL disabled unless a separate reviewed local setup is used.

Canonical memory, topology and pin generators emit build-local bindings. Managed IPs,
toolchains and external inputs are revision-locked. This document does not modify those
hardware interfaces or create another register source of truth.

== RTL Simulation
Verilator and Icarus support behavioral verification; the repository also defines synthesis,
netlist simulation, static timing, warning and metric collection flows. The supported PR
matrix and nightly extensions are documented by the regression configuration. Delayed UART
display in piped Verilator output is not evidence of a failed simulation.
#source-note("docs/engineering.md", title:"Reproducible build and regression evidence")

== FPGA Verification
FPGA wrapper and constraints are board-specific. Logical pad names in this datasheet are not
FPGA package locations. Dedicated SDIO1 and USB2 ULPI routes require approved board constraints
before a corresponding hardware claim is made.
#source-note("fpga/README.md", title:"FPGA ownership and validation boundary")

== Physical Design
Technology wrappers and smoke synthesis/STA provide implementation infrastructure. Frequency,
area and timing reports must identify the exact profile, PDK, constraints and tool revisions.
A successful behavioral test or a generic PLL model does not prove physical signoff.
#source-note("physical/README.md", title:"Physical design and managed PDK flows")

== PCB Hardware
#placeholder([Reference board and external-memory / ULPI wiring], height:22mm)
#tbd[Approved schematic, power tree, connector pinout, impedance/timing constraints and
board bringup results are required for a reference PCB specification.]

#ds-table("physical-evidence-inventory",[Available physical-design inputs and missing release evidence],
  ([Topic],[Available input],[Missing evidence]),
  data.system_reference.product_details.physical.map(r=>(r.title,r.available,r.missing)),widths:(0.6fr,1.65fr,1.9fr))
The StarrySky V2 constraint file is a board-specific implementation input. It is not a
minimal-system schematic, an ASIC package-pin assignment or a characterization report.
No approved schematic, physical package mapping or matching measurement result was supplied
for this publication update; the corresponding existing specification fields remain unfilled.

A reference-board release needs a versioned schematic and BOM, connector/net mapping,
power/decoupling network, external-memory and PHY selection, clock/impedance constraints
and bringup record. Publish the design-file revision with each drawing or download entry,
and identify which routes were actually tested. The current XDC provides constraints for its
named FPGA board; the missing circuit and acceptance records remain listed in @release-verification.
#source-note("fpga/mini/starrysky_v2.xdc",title:"Existing board-specific FPGA constraint input")
