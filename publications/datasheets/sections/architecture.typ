#import "../style.typ": *
#import "../figures.typ": *
#import "../waveforms.typ": timing

= System Architecture
== Introduction
=== SoC Architecture
Mini PRODUCT contains two fixed harts, an LP-owned control plane, a native HP data fabric and
two APB4 register islands. There is no hardware cache coherency. Software transfers shared
buffer ownership explicitly and performs the required fences and cache maintenance.

=== Management Processor
==== Hazard3
Hazard3 is hart 0 and the root-management processor. The reference profile selects RV32IM
firmware. Its AHB-Lite interface is adapted to AXI32 for control access; memory transactions
are directed through the LP gateway to the shared data plane. The management JTAG path provides
halt, resume, register and system-bus access. LP retains control while HP is held in reset.
#source("docs/hazard3-debug.md", title:"Management debug transport and acceptance flow")

=== Application Processor
==== VexiiRiscv
The generated HP hart is a dual-issue RV32IMAFDC + Zicbom configuration, with supervisor/user
modes, Sv32 virtual memory and 64-byte cache-maintenance blocks. Hart 1 uses native AXI64
instruction and data paths. Its uncached MMIO path is downsized and crosses into the LP
control plane. OpenSBI/Linux inputs and generated-core configuration are dependency-locked.
#source("docs/lp-hp-architecture.md", title:"LP/HP architecture and boot contract")

== Interconnect
=== AXI4 and APB4 Interfaces
The product replaces the former NMI/AXI4-Lite/APB3 organization with AXI4 control and data
paths and APB4 register targets. The compatibility RIBP boundary for selected MPW cores is
described in @mpw. It is not the PRODUCT data fabric.

The LP control fabric uses 32-bit data. APB accesses cross LP to PCLK through asynchronous
request/response bridges. The HP data plane uses 64-bit data, 32-bit addresses and six-bit
global transaction IDs. Adapters preserve byte lanes and response attribution across width
and clock boundaries. HP MMIO cannot write root-owned SYSCTRL/RCU, watchdog, GPIO administration
and other protected management controls.

#figure(fabric-diagram(), caption:[PRODUCT control and memory paths. Gateway adaptation and CDC separate the functional clock domains.])<fabric-diagram>

=== Common Bus Protocols <common-protocols>
The following WaveDrom examples define the handshake notation used by the IP chapters.
They show valid protocol ordering, not guaranteed transaction latency. Address windows,
byte strobes, burst limits, access permissions and IP-specific side effects remain binding.

#timing("apb4",[APB4 setup, access and wait-state example.])
#timing("axi4",[AXI4 read-address and response-channel example.])
#timing("axis",[AXI4-Stream backpressure and end-of-transfer example.])

=== Interconnect Matrix
Eight initiator identities access five memory targets. The crossbar arbitrates reads and
writes separately for each target. I/O gateway A combines USB2, SDIO0 and the APU private
master; gateway B combines SDIO1 and SPI-SD. JPEG occupies data-master slot 6.

#note[The matrix on the next page is generated from the RTL access policy. R/W permission is
subject to active memory-pad mode, resource ownership, target readiness and EXT-H address bounds.
An allowed entry does not guarantee throughput.]

#pagebreak()
#set page(flipped: true)
#figure(matrix-diagram(), caption:[AXI64 memory access matrix: R = read, W = write, - = denied.])<bus-matrix>
The I-cache is the only instruction-permitted initiator. HP cache attributes are preserved;
DMA, I/O gateways, LP gateway, JPEG and EXT-H require non-cacheable transactions. XPI is read-only
on this data plane; indirect writes use its APB-controlled command engine.

Denied accesses return a finite error response with source attribution. EXT-H has additional
read/write address bounds. SRAM and SDRAM use multiple outstanding credits; serial targets
have more restricted concurrency. Software must not assume coherency or treat theoretical bus
width multiplied by clock rate as measured application bandwidth.
#source("rtl/mini/integration/soc_topology.json", title:"Generated matrix source: data_master_policies")
#pagebreak()
#set page(flipped: false)

=== Address Mapping
All ranges below are inclusive. The SRAM range is resolved using the reference profile's
32 KiB setting. Peripheral windows are address allocations; not every offset implements a
register. Detailed contracts define valid offsets and access modes. Reserved regions do not
advertise an implemented IP.

#ds-table("memory", [Memory and reserved data apertures],
  ([Window], [Base], [End], [Size]),
  data.regions.filter(r=>r.route in ("axi4","ram","reserved") and r.size > 4096).map(r=>(
    code(r.symbol),code(r.base_hex),code(r.end_hex),r.size_label)),
  widths:(1fr,1.1fr,1.1fr,0.65fr),
  notes:[FLASH is the reset/boot alias. SPISD's former card-data aperture is reserved. The physical
  capacity of fitted XPI/OPI devices remains board-dependent.],
)
#ds-table("registers", [Register and interrupt-controller windows],
  ([Window], [Base], [Size], [Integration]),
  data.regions.filter(r=>not(r.route in ("axi4","ram","reserved") and r.size > 4096)).map(r=>(
    code(r.symbol),code(r.base_hex),r.size_label,r.availability)),
  widths:(1.3fr,1fr,0.6fr,1.35fr),
)
<reserved>
The retained GA register range and SPI-SD data aperture are reserved. PRODUCT keeps a
compatibility responder at the former selectable user-IP window; it does not instantiate
MPW user IPs there. Neither case should be counted as an active accelerator.

#pagebreak()
== Clock and Reset
=== Architecture
The RCU compatibility wrapper contains the product clock/reset subsystem. AON uses REF24;
LP resets to REF24 and HP resets to the external 72 MHz safe source. The reference profile
disables the PLL. Generic PLL selectors model 72-240 MHz in 24 MHz steps; these are digital
integration choices, not qualified silicon speed grades.

#figure(clock-diagram(), caption:[Clock-domain organization and reset defaults. Frequencies shown are configuration values.])<clock-diagram>

The memory root is the stable external 72 MHz clock divided by two. Audio, DVP pixel, ULPI and
JTAG have independent clocks. The inventory below lists domains without presenting synthesis
constraint periods as measured operating limits.
#ds-table("domains", [Canonical clock/reset-domain inventory],
  ([Domain], [Clock signal], [Reset signal]),
  data.clocks.map(d=>(d.name,code(d.clock),code(d.reset))),widths:(0.6fr,1.45fr,1.45fr),
)

=== Reset and Logic
Clock changes validate the request, block new traffic, quiesce and drain accepted work, park
LP, select the safe source, apply and qualify the PLL setting, then restore the requested
roots. Timeout or lock loss returns to the safe source and retains fault status. Reset
release uses per-domain synchronizers; coordinated warm flushes prevent stale transactions
from re-entering a restarted domain.
#source("docs/pll-clock-control.md", title:"Clock transition, fault and PLL control contract")
#tbd[PLL jitter, PVT range, clock-tree closure and pad-level reset timing require physical
qualification. No crystal-oscillator range or maximum core frequency is specified here.]

== Interrupt System
The management interrupt vector contains 32 allocated positions. The following numbers are
LP vector bits, not HP PLIC source IDs. Peripheral-level status registers identify causes
within an aggregate source. Resource-controlled interrupts are routed according to ownership.
#ds-table("lp-irqs", [LP interrupt vector],
  ([LP bit], [Source], [Description]),
  data.interrupts.map(i=>(str(i.core_bit),code(i.name),i.description)),
  widths:(0.45fr,1.25fr,2fr),
)

HP has local software/timer interrupts and a 32-source, two-context PLIC. Source 0 is
reserved; sources 1-10 are UART1, mailbox, EXT-H, DMA, USB2, SDIO0, SDIO1, SPI-SD, JPEG and APU.
Sources 11-31 are reserved. The contexts drive machine and supervisor external interrupts.
Claim/complete and priority rules are defined in the HP platform contract.
#source("docs/ip/hp-platform.md", title:"HP PLIC, local interrupts and mailbox")
