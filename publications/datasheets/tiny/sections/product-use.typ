#import "../engineering-figures.typ": circuit-figure
#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow
#import "../waveforms.typ": timing

== Product Configuration and Feature Availability <tiny-configuration>
The main reference is #code(doc.profile). *Tiny is an independent wired MCU integration*; it is not a selectable Mini mode.
The reviewed implementation is identified by #code(doc.source_revision). An interface name, shared SDK declaration or mapped
offset does not establish an optional feature. Identify the product before using an inherited register or API name.
#let compat = data.compatibility.first()
#ds-table("configuration",[Tiny selected and compatibility configurations],([Item],[ICS55 main reference],[IHP130 compatibility]),(
  ([Profile],code(doc.profile),code(compat.profile_path)),
  ([Processor],[One RV32IMC hart; A disabled; RV32IM default firmware],[Same hardware and default firmware ISA]),
  ([Boot / clocks],[#reference-boot(data.facts). Functional PLL192/240 profiles.],[#reference-boot(compat). Explicit external-XIN variants use separate profiles.]),
  ([Main / private memory],[#data.facts.sram.CapacityKiB KiB main SRAM; 24 KiB private Crypto SRAM],[#compat.sram.CapacityKiB KiB main SRAM; same logical private capacity, different technology macros]),
  ([DMA / fabric],[8 channels; streams and SPI; 3 external owners],[Same digital routing; no imported physical result]),
  ([GPIO pad capability],[CMOS input selection and pulls: 0x7],[Capability 0x0; unsupported electrical controls rejected]),
  ([Firmware],code("APP=bringup; HAVE_CSR=YES"),code("LINK_TYPE=ld2_all_sram"))),widths:(0.75fr,1.7fr,1.7fr))

=== Implemented scope and planned capabilities
The 23 IP chapters cover every currently decoded region and allocated interrupt cause. RCU is a SYSCTRL subregion;
GPIO administration and user windows are views of the same pad bank. UART0/I2C0 are the active serial instances.
@tiny-migration records the removed UART1/I2C1 interfaces without advertising them as current hardware.

PPALite P3 is integrated with APB4, IRQ27, RCU17 and the existing request-11/DMA2 path.
PIO-lite has standalone P2 RTL and host tools, but Tiny integration remains absent.
The document does not imply USB, wireless, CAN, ADC, an application hart, Linux, secure boot or a production entropy source.
Optional PSRAM and the camera/display workflows require explicit device initialization and resource ownership.
#source-note("docs/ip/tiny-soc.md",title:"Frozen Tiny target and separately phased extensions")
#source-note("docs/ip/piolite-verification.md",title:"PIO-lite standalone evidence and remaining integration gates")

 #pagebreak()
== Typical Applications and System Configurations <tiny-applications>
=== Wired control and instrumentation
Use the single Hazard3 hart with local SRAM for control firmware, GPIO, timers, UART0 and I2C0.
Select complete pad groups and reserve DMA channels before enabling a service. The default firmware uses RV32IM;
the hardware also supports compressed instructions. No application hart, Linux or wireless subsystem is implied.

=== Camera, display, audio and storage
#circuit-figure("system-media")
Camera snapshots select RAW DVP or PPALite PROCESS before central DMA, optionally landing in explicitly initialized NSS1 PSRAM. PPALite application/consumer qualification remains P4; its P3 integration is separately recorded.
Display consumes completed frame data through SPI; SD saving uses the native host's private DMA and SRAM bounce storage.
These operations have separate ownership and completion boundaries. Camera and audio share pins and require exclusive routing.
#flow("application-composition",([Acquire routes and initialize external devices],
 [Capture or produce a bounded payload],[Drain producer; publish immutable payload],
 [Display or save through the selected consumer],[Verify completion and release ownership]),
 [Tiny application composition. This ordering does not claim concurrent pipelines or measured throughput.])
See @tiny-diagnostics for the current snapshot procedure and @tiny-conflicts for shared resources.
#source-note("app/apps/ci_smoke/tiny.c",title:"Current acceptance composition")
#source-note("docs/ip/spi-verification.md",title:"Scoped display and snapshot evidence")

#change-start("tiny-v02-commercial-20261114-quick-reference","Specification and evidence quick reference")
== Specification and Evidence Quick Reference <tiny-specification-quick>
#import "../../../specifications/components.typ": quick-reference
#quick-reference(data.specifications,ds-table)
#change-end("tiny-v02-commercial-20261114-quick-reference")
