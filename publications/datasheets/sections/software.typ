#import "../style.typ": *
#change-start("v05-c906-20261022-sections-software","C906 payload and pre-release JTAG branch")
#change-start("v05-dev-20261022-software","V2 workload-specific boot, RT-Thread and Mini configuration boundaries")
#change-start("v05-emphasis-software","Selected body emphasis: software")
#change-start("dev-software","NPU/APU support, boot ownership and current application diagnostics")
#import "../figures.typ": *
#let boot = data.system_reference.software.boot_acceptance
#change-start("v05-refresh-hp-boot","Current bounded HP boot and complete acceptance protocol")

= Software
== Boot Configuration, Initialization and Recovery <boot-configuration>
The management hart starts from the reset flash alias. Normal firmware composition and memory
placement depend on the committed application and linker profile. The HP acceptance example
instead uses the *SRAM-resident `hp_boot` image* and validates an external boot bundle before
releasing HP. It must not be assumed that every bringup image automatically boots Linux.
The separate APU P9 acceptance profile performs LP APUMC/APUC/APUM loading and bare-metal HP
audio/KWS work; it is not the Linux boot profile. NPU compiler output and HP smoke payloads
likewise do not supply a native Linux driver. See @apu and @npu for their software boundaries.

#figure(boot-diagram(), caption:[Linux image loading and ready checkpoint. Smoke and NPU-P6 acceptance continue through the later protocol.])<boot-flow>

The Linux workload bundle contains locked OpenSBI, Linux, device-tree and initramfs inputs.
Smoke and RT-Thread each carry one executable in the same V2 transport. LP validates
the header and payload bounds, attempts transfer with the boot DMA context and CRC, and
falls back to a software copy/CRC if that attempt fails. It fences memory, clears the LP
mailbox interrupt and requests HP release. It then waits for the expected readiness event;
it does not publish entry/DTB addresses through a boot mailbox before release. For an ordinary
Linux workload the checked userspace ready event is terminal. The same loader also serves
freestanding HP acceptance payloads: smoke and the dedicated NPU-P6 build continue through the
later GA2D/cache-clean protocol, where the *initial ready message alone does not complete it*.
#source-note("docs/lp-hp-architecture.md", title:"Boot-bundle ABI, lifecycle and failure handling")

=== Prerequisites and image layout
Use the dedicated HP profile for the acceptance loader. It runs from on-chip SRAM and waits
for the SDRAM controller to be ready and free of initialization/error state. The software
does not choose an arbitrary external device timing configuration during this wait. External
flash placement, SDRAM wiring and timing *must already match the selected integration*.

#ds-table("hp-image-layout",[HP image locations extracted from the boot-bundle header],
  ([Artifact],[Load address],[Maximum allocation]),
  data.system_reference.boot_layout.map(r=>(r.name,code(r.address),[#r.max_size_kib KiB])),
  widths:(1.2fr,1fr,1fr),notes:[Maximum allocation is a bundle bound, not the actual image size. The full SDRAM address region is listed in Address Mapping.])
The build uses OpenSBI FW_JUMP with a fixed Linux entry and DTB address, without a U-Boot
stage. The bundle header contains a format version, required entry types, lengths, fixed
load locations and CRCs. Keep the image builder, package builder, loader header and selected
source revision together. A larger image *must not be silently truncated* to fit its allocation.

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
+ Probe the mailbox. *Only the smoke workload* transfers GA2D from confirmed LP-owned idle
  to confirmed HP-owned idle before HP release. NPU ownership participates only when
  #code(boot.npu_defines.join(" or ")) is compiled.
+ Apply the memory fence. If #code("HP_JTAG_DEBUG=YES") selected the compiled debug branch,
  select the HP JTAG target *while HP is still held*; failure terminates with result code
  #boot.jtag_debug_failure_code. Then clear the LP mailbox interrupt, request release, and check the
  immediate HP status result. Observe #code("HP_BOOT_RELEASED") only as a release checkpoint.
+ Select the workload-specific terminal path. RT-Thread requires its ready event followed by
  a mailbox interrupt command and acknowledgement. Ordinary Linux requires the exact Linux-ready
  event, argument and sequence, then LP writes TEST_STATUS. #code("HP_LINUX_READY") alone is diagnostic.
+ For smoke, and for the dedicated NPU-P6 continuation, send the GA2D start command and wait
  for the result message with its distinct sequence.
  Confirm GA2D safe idle before requesting HP hold.
+ On that continuation path, observe the cache-clean request, receive the cache message, acknowledge clean state and
  confirm HP held without a forced fault. Return GA2D to LP and verify safe idle; return NPU
  as well when its acceptance option is enabled. Only then write the sticky successful verdict.

The NPU-P6 build reuses workload 1's four-entry transport for its corpus payload; it is not an
ordinary Linux image. In this snapshot its compile-time branch continues to the GA2D/cache
tail, while the earlier GA2D ownership transfer is guarded by workload SMOKE. *That source-path
mismatch remains an integration review item*, not evidence of a complete current P6 pass.
Do not change the workload tag or infer missing ownership work from the ready marker.

#minor-title("RT-Thread runtime boundary")
The dedicated RV64 M-mode BSP uses the locked RT-Thread v5.3.0 source and lp64d toolchain.
Its acceptance checks scheduling, integer context preservation, IPC, timer timeouts and the
LP-issued mailbox interrupt round trip. The recorded context test does not qualify FCSR or
floating-point task preservation. LP alone publishes the final sticky verdict.
#source-note("docs/hp-rv64-validation.md",title:"Dated smoke/RT-Thread evidence and Linux coverage limits")
The C906 BSP initializes cache/predictor state before entering C and uses the internal
CLINT/PLIC layout. Its mailbox doorbell is PLIC ID 18. Bare-metal smoke, APU and NPU
payloads use the C906 cache-maintenance encodings; older VexiiRiscv images and Zicbom
instruction sequences must be rebuilt for the current core rather than reused by filename.

#ds-table("hp-boot-mailbox-checkpoints",[Linux/smoke-path HP-to-LP messages; RT-Thread uses its separate handshake],
  ([Checkpoint],[Event],[Argument],[Sequence]),
  boot.messages.map(r=>(r.title,str(r.event),code("0x"+upper(str(r.argument,base:16))),str(r.sequence))),
  widths:(1.65fr,0.45fr,1.15fr,0.65fr))
The ready, result and cache waits each have a firmware polling budget of
#boot.event_poll_iterations iterations (#boot.event_poll_multiplier × RS_TIMEOUT_DEFAULT).
The budget is *not a duration in milliseconds*, and a stalled MMIO access can prevent loop
progress. A different sequence remains pending until the budget expires; matching the sequence
with a wrong event or argument fails immediately. A mailbox API error also fails the wait.

The supplied Linux rootfs service sends *only the ready message*. That is sufficient for the
ordinary Linux workload's terminal checkpoint. It contains no GA2D command responder or
cache-clean service and therefore cannot substitute for the smoke or NPU-P6 acceptance payloads,
which supply those later responses. See @linux-runtime.

The software fallback computes CRC from bytes read from the source while copying. It performs
full destination readback only for entries up to the loader's small-entry threshold; it must
not be described as a complete large-image destination readback test. CRC checks protect
integrity, not image origin or rollback policy.

=== Failure branches and supervision boundary
Use the source-checked result codes in @firmware-application-results for the producing stage;
they include missing ready, result and cache-clean checkpoints. The failed verdict alone does
not prove that HP, its dirty cache or accepted bus traffic has stopped.
The failure helper requests HP hold/reset *only while GA2D is not recorded as HP-owned*.
After that handoff, it preserves the ownership state and writes a failed verdict without an
unconditional HP reset. Capture actual reset, drain, cache and resource state before recovery
or buffer reuse. No automatic image retry or signed recovery image selection is implemented.
A board supervisor/watchdog remains a separate protection against stalled accesses or software.

For target acceptance, capture profile/image hashes, enabled acceptance options, LP load/release
checkpoints, ready/result/cache messages where applicable, final ownership and the simulator
verdict. Do not treat UART startup as success or apply the Linux-ready terminal rule to smoke or
NPU-P6. Linux peripheral qualification requires
the separate support matrix and matching platform evidence.

#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #source("app/apps/hp_boot/main.c",title:"Executed boot checks, copy fallback and failure codes") ·
  #source("app/apps/hp_boot/hp_boot_bundle.h",title:"Image types, addresses and allocation bounds") \
  #source("scripts/build_hp_linux.py",title:"OpenSBI FW_JUMP and Linux artifact composition") ·
  #source("scripts/package_hp_boot.py",title:"Bundle generation and layout checks")
]
#change-end("v05-refresh-hp-boot")


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
console implementation and the core-internal CLINT timer/software-interrupt setup. UART1 and mailbox DT nodes
reserve their platform ABI; the presence of #code("status = okay") is not evidence that a
native custom driver is available or correct. No generic HAL-to-Linux bridge is supplied here.

=== Validated-configuration record
A reusable run record must name the source commit, committed profile, vendored HP core revision,
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
IHP130 reference enables the 32 KiB SRAM interface and macro. The current Mini ICS55 CI
profile also enables 32 KiB SRAM and its macro, while keeping HAVE_PLL=NO. Tiny's ICS55
PLL/SAFE24 lifecycle is a separate product contract and does not change Mini's clock policy.

Canonical memory, topology and pin generators emit build-local bindings. Managed IPs,
toolchains and external inputs are revision-locked. This document does not modify those
hardware interfaces or create another register source of truth.

#include "development-environment.typ"

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

#change-end("v05-emphasis-software")

#change-end("v05-dev-20261022-software")

#change-end("v05-c906-20261022-sections-software")
