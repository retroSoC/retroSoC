#import "../style.typ": *
#import "../figures.typ": *

= Software
== Boot Sequence
The management hart starts from the reset flash alias. Normal firmware composition and memory
placement depend on the committed application and linker profile. The HP acceptance example
instead uses the SRAM-resident `hp_boot` image and validates an external boot bundle before
releasing HP. It must not be assumed that every bringup image automatically boots Linux.

#figure(boot-diagram(), caption:[HP boot example. Validation failure retains LP recovery control and prevents normal HP handoff.])<boot-flow>

The HP bundle contains locked OpenSBI, Linux and device-tree inputs. LP validates header and
payload bounds, uses the boot DMA context for transfer, verifies CRCs and publishes mailbox
state before release. LP remains responsible for ownership and recovery after Linux starts.
#source-note("docs/lp-hp-architecture.md", title:"Boot-bundle ABI, lifecycle and failure handling")

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

== Linux and Driver Status
The repository provides the asymmetric Linux integration path with OpenSBI and Buildroot
inputs. Linux boot, native driver coverage, performance, cache-maintenance correctness and
physical implementation remain distinct qualification topics. No complete Linux peripheral
support matrix or sustained application benchmark is asserted by this draft.
#tbd[Publish a reviewed driver-support matrix and reproducible Linux boot/performance results
for the chosen hardware configuration before claiming a production Linux platform.]

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
