#import "../style.typ": *
#import "../system-figures.typ": *

== Product Configuration and Feature Availability <product-configuration>
This publication describes one reviewed integration, not every combination of build options.
Use the configuration identity with the IP capability registers before selecting a firmware
image, external component or operating-system driver. An integrated controller may still need
board wiring, a technology macro or additional software. A reserved address range is not an IP.

=== Configuration identity
#ds-table("system-profiles",[Publication configurations and their intended use],
  ([Role],[Committed profile],[Boundary]),
  (([PRODUCT reference],code(doc.profile),[Fixed LP/HP topology; reference for the main register and pad inventories.]),
   ([HP boot acceptance],code(doc.hp_profile),[Same PRODUCT organization; SRAM-resident LP loader and an external HP bundle.]),
   ([MPW compatibility],code(doc.mpw_profile),[Selectable legacy user core/IP; use only the separate MPW appendix.])),
  widths:(0.75fr,1.35fr,1.6fr))
The source revision printed in Document Control identifies the hardware/software contract.
Gen2 and Gen2+ remain the product title; no unreviewed derivative differences or orderable
part numbers are inferred. The 32 KiB SRAM and disabled PLL belong to the selected reference
profile. Other committed technology profiles must be checked independently for available macros.

=== Feature availability and dependencies
The following rows cover every actual IP chapter, including the two MPW-only examples.
Repeated instances have separate rows where their routing differs; shared functional blocks
such as the dual timer and dual I2C retain their documented instance counts in the scope column.
"Integrated" describes the documented digital block, not a qualified silicon feature.
"Partial" identifies an explicit implementation or qualification boundary.
#ds-table("feature-availability",[IP availability and system dependencies],
  ([IP / status],[Implemented scope],[Integration dependency]),
  data.system_reference.support.map(r=>([#r.title \ #r.implementation],r.scope,r.dependencies)),
  widths:(1.05fr,1.4fr,1.7fr))

=== Interface selection summary
#ds-table("interface-selection-summary",[Interface roles and key exclusions for selection],
  ([Interface / role],[Important selection boundary]),
  data.system_reference.product_details.interfaces.map(r=>([#r.title \ #r.role],r.excluded)),widths:(1fr,3.15fr))
This is a source-level selection aid. Use @interface-subsets for the complete mode/software
matrix and @media-interoperability for media layout and transport gates. An interface name
does not establish all optional modes in a standard or a compliance certificate.

=== Selecting a usable configuration
+ Start with the reference profile and identify the memory needed by the application.
  Confirm that mapped capacity, fitted device capacity and linker placement agree.
+ Check shared-pad exclusion and external clock/PHY requirements before allocating GPIOs.
+ Read ARCHINFO and the relevant IP version/capability registers; reject unsupported modes
  before writing configuration or submitting DMA work.
+ Match the firmware or Linux path to the support matrix in @software-support. Keep unsupported
  resources under LP control until an appropriate driver and handoff protocol are supplied.

A probe mismatch should stop initialization of that resource. Preserve diagnostic identity
and report the incompatible image/profile instead of treating reserved or disabled registers
as a compatible peripheral. The compatibility rules and known exceptions are in @known-limitations.
#source-note("publications/datasheets/mini.json",title:"Publication identity and reference profiles")
#source-note("rtl/mini/integration/soc_topology.json",title:"Integrated resources and access policy")

#pagebreak()
== Typical Applications and System Configurations <typical-applications>
These logical system examples show how existing blocks can be combined. They are not a
reference PCB, a complete application distribution or measured performance claims. External
device configuration, buffer sizing and the selected workload remain integration responsibilities.

=== LP management and embedded control
#figure(sequence-diagram((
  [*Hazard3 firmware* \ Root initialization \ HP may remain in reset],
  [*APB4 peripherals* \ GPIO, timers, UART, I2C],
  [*External system* \ Sensors, actuators \ Board-level interface])),
  caption:[Management-control configuration and its external boundary.])
The LP application can own initialization, diagnostics and bounded peripheral operations.
Use the published bringup or shell profile as an entry point, then select only the interfaces
needed by the board. Keep interrupts masked until peripheral status has been cleared and a
handler is installed. Establish inactive output levels before enabling an alternate function.

+ Verify the management clock and console, then probe ARCHINFO and SYSCTRL.
+ Configure pads and the selected peripheral while its output path is inactive.
+ Install the handler or bounded polling loop, clear stale status, and enable operation.
+ On timeout, preserve error/status registers and use the IP-specific stop/recovery path.

An LP-only workload does not remove the instantiated HP core from PRODUCT and does not imply
a separately qualified low-power SKU. SRAM-only software placement must fit the chosen linker
profile; other profiles can depend on external memory even when Linux is not used.

=== Asymmetric Linux system
#figure(sequence-diagram((
  [*External boot image* \ XPI-visible bundle \ Header and payload CRCs],
  [*LP loader* \ Validate and copy \ Retain root authority],
  [*External SDRAM* \ OpenSBI, DTB \ Linux and initramfs],
  [*HP application* \ Hart 1, Sv32 \ Linux enters via OpenSBI],
  [*SBI console / timer* \ Supplied platform path],
  [*LP supervision* \ Mailbox observation \ Resource and reset policy])),
  caption:[Supplied Linux boot composition and management responsibilities.])
The fixed Linux memory layout uses external SDRAM. The supplied software uses OpenSBI
FW_JUMP and an initramfs; it does not include a U-Boot stage. The initial Linux console is
SBI-based, even though OpenSBI accesses UART1 underneath. Native custom peripheral drivers
and an application resource-handoff service are separate work.

Before boot, validate the external memory configuration and the exact bundle generated for
the selected snapshot. After boot, an expected mailbox event provides the acceptance marker;
it does not establish that all peripheral drivers or workloads have been validated. Follow
@boot-configuration for failure handling, including the unbounded firmware-local ready wait.

=== Camera and audio data paths
#figure(media-system-diagram(),caption:[Memory-mediated camera and audio composition using the current digital interfaces.])
Use separate producer and consumer buffers, with an explicit lifetime for every captured
frame or audio block. DVP capture reaches memory through its DMA/stream path; JPEG consumes
an independently configured memory job. The drawing does not assert a direct hardware
connection from DVP to the JPEG engine. I2S uses its independent audio clock and compatible
external codec wiring. Production APU codec/KWS availability must be checked separately.

The current native JPEG master has zero normal admission credits in the reviewed crossbar.
The diagram describes the intended memory-mediated composition; an end-to-end JPEG private-DMA
application requires the separately corrected and validated route described in @bus-programming.

+ Select external interface modes, pin routing and clocks before starting capture/playback.
+ Allocate aligned buffers, prepare ownership, and configure the consumer before enabling
  a producer that cannot tolerate sustained backpressure.
+ Start the bounded transfer and monitor completion, overflow/underflow and DMA errors.
+ Stop or discard the affected frame/block after a fault; do not recycle a buffer while a
  producer, DMA engine or cached HP consumer still owns it.

Sustained frame rate, audio latency and simultaneous memory bandwidth depend on device
timing, contention, buffer policy and software. Measure the complete composition under
the conditions in @performance-characterization rather than adding individual IP rates.
#source-note("app/README.md",title:"Application and middleware ownership")
#source-note("app/ports/linux/README.md",title:"Current HP Linux composition")
#source-note("docs/axi4-stream.md",title:"DMA, audio and camera stream integration")
