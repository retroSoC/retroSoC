#import "style.typ": *
#import "diagrams.typ": architecture, flow, tcd-diagram
#import "waveforms.typ": timing
#import "ip-reference.typ": reference
#show: template

#cover(evaluation:((name:"Available",fill:"full"),(name:"Functional",fill:"left-half"),(name:"Reproduced",fill:"empty"),(name:"Tapedout",fill:"empty")))[
  #text(9pt,weight:"semibold",fill:gold)[PRODUCT DATASHEET / #doc.status]
  #v(rhythm.cover-gap)
  #text(30pt,weight:"semibold")[retroSoC Tiny]
  #linebreak()
  #text(23pt,weight:"semibold",fill:gold)[Gen1]
  #v(rhythm.cover-gap)
  #text(13pt)[An Open-Source, Single-Core RISC-V MCU]
  #v(rhythm.cover-meta-gap)
  #grid(columns:(1fr,1fr),
    [#text(font:("Inter","Noto Sans CJK SC"),weight:"bold",top-edge:0.7275390625em)[#doc.brand_name（#doc.brand_name_zh）] · v#doc.version \ #doc.date],
    align(right)[#doc.author#link("mailto:"+doc.author_email)[(#doc.author_email)] \ #doc.maintainer])
  #v(rhythm.cover-rule-gap)
  #line(length:100%,stroke:1.1pt+gold)
= Product Brief
== Features
  #columns(2,gutter:rhythm.cover-gutter)[
    #set par(leading:rhythm.cover-leading,spacing:rhythm.cover-spacing)
    #set list(spacing:rhythm.cover-list-spacing)
    *Compute and debug*
    - One Hazard3 RISC-V hart: *RV32IMC*, A disabled.
    - Default RV32IM firmware; IRQ/CSR support enabled.
    - JTAG debug with coordinated hart reset.

    *Memory and interconnect*
    - *128 KiB SRAM*, 32 banks of 4 KiB.
    - Native AXI32 memory paths and one APB4 island.
    - CPU and DMA share one active transaction globally.
    - XPI NOR boot and SRAM-resident application layout.

    *DMA and control*
    - *Four DMA channels*, 32-bit transfers, up to 16 beats.
    - Direct and 64-byte linked-descriptor operation.
    - Sticky first-fault records and CPU/DMA wait snapshots.
    - Sticky automated firmware acceptance result.
    #colbreak()
    *Wired connectivity*
    - 32 GPIOs with atomic output aliases and interrupts.
    - Two FIFO UARTs; dedicated TX/RX pads.
    - Two controller-mode I2C instances with 7/10-bit addressing.
    - Four-chip-select XPI with single/dual/quad SDR phases.

    *Timing and supervision*
    - Configured *24 MHz* system clock; no PLL.
    - Two 32-bit general timers; four PWM outputs.
    - 1 MHz CLINT timebase; local software/timer interrupts.
    - RTC alarms/wake and window watchdog on the system clock.

    *Development boundary*
    - Freestanding SDK and Tiny acceptance application.
    - IHP130 macro/behavioral integration and simulation flows.
    - No external RAM, wireless, HP core or multimedia accelerator.
  ]
  #v(1fr)
  #note(below:0pt)[This DRAFT describes an implemented *prototype*. The 24 MHz configuration is a functional target,
    *not a timing-qualified operating point*. Electrical, package, thermal, power and silicon qualification remain unprovided.
    The partial Functional mark does not establish complete protocol or physical qualification.]
]
#pagebreak()
== Configuration and Scope <tiny-configuration>
The main reference is #code(doc.profile). *Tiny is an independent wired MCU integration*; it is not a selectable Mini mode.
The reviewed implementation is identified by #code(doc.source_revision). An interface name, shared SDK declaration or mapped
offset does not establish an optional feature. Identify the product before using an inherited register or API name.
#ds-table("configuration",[Tiny reference configuration],([Item],[Selected value],[Boundary]),(
  ([Product],[Tiny Gen1 / IHP130],[Prototype; one management MCU hart.]),
  ([Hardware / firmware],[RV32IMC, A disabled / RV32IM],[Compressed execution is implemented; the default compiler target omits C.]),
  ([Clock],[24 MHz; CLINT 1 MHz],[Functional targets; no PLL or qualified maximum-frequency rating.]),
  ([Memory],[128 KiB SRAM],[External NOR for boot; no external RAM initialization dependency.]),
  ([Bus / DMA],[AXI32/APB4; four channels],[One active read or write globally; memory-mapped endpoints only.]),
  ([Firmware],code("APP=bringup; HAVE_CSR=YES; LINK_TYPE=ld2_all_sram"),[Tiny-specific acceptance entry point.])),widths:(0.8fr,1.55fr,1.75fr))

=== Implemented scope and deferred capabilities
The 14 IP chapters cover every decoded region and all allocated interrupt causes. UART and I2C instances retain distinct
addresses and wiring. The GPIO user/administration windows are views of one pad bank. A restricted register window is not
a claim of a separate security domain.

Atomics, wireless, external RAM, USB, SDIO, standalone general SPI, I2S, CAN, ADC, accelerators, authenticated boot,
RTOS ports and independent deep-sleep timing are outside this release. Additional XPI chip selects remain available at
the interface, but the initial pin-level NOR acceptance uses NSS0; other populated-device configurations require evidence.
#source-note("docs/ip/tiny-soc.md",title:"Frozen Tiny requirements and non-goals")

== Reading and Evidence Conventions
Addresses are byte addresses; register offsets are relative to their named instance/group. *Source reviewed*, *test available*,
*executed result* and *physical qualification* are separate states. Source links target the reviewed commit or locked managed
input. Diagrams describe digital structure and ordering; they do not specify measured latency or board timing.

Use @tiny-addresses for memory windows, @tiny-irq for interrupt numbering, @tiny-register-index for address-first register
lookup, @tiny-boot for startup, @tiny-diagnostics for terminal results and @tiny-evidence for verification boundaries.
The document uses the approved Mini visual language; all product facts and source inventories here belong to Tiny.
#pagebreak()
#contents(depth:3)
#pagebreak()
#figure-directory(tables:true)
#pagebreak()
#figure-directory()
#pagebreak()

= System Architecture
== Processor and Integration <tiny-core>
Hazard3 is hart zero. The shared wrapper selects the C and M extensions and disables A for Tiny. Its AHB-Lite bus terminates
at a direct AXI32 adapter. JTAG supports the implemented halt/resume, register and system-bus debug path; debug hart reset
waits for the adapter to become idle instead of abandoning an accepted transaction.

The system has no application hart, MMU/Linux platform, hardware cache-coherent multicore organization or product extension
slots. CPU-visible SRAM, XPI and APB routes are the implemented interconnect. The single-hart architecture does not remove
the need for software/DMA buffer ownership and fences.
#architecture()
#source-note("rtl/tiny/top/retrosoc_tiny.sv",title:"Tiny product integration and parameters")
#source-note("rtl/ip/core/mgmt_core_wrapper.sv",title:"CPU ISA, AHB adapter and debug wrapper")

== Clock, Reset and Operating State <tiny-clock>
CPU, AXI, APB, RTC and watchdog share the configured 24 MHz system clock. CLINT derives a 1 MHz tick. JTAG has its own
external clock and managed asynchronous debug crossing. Other asynchronous external inputs use their specified synchronizers;
the absence of a system-bus clock crossing is not complete CDC/RDC signoff.
#ds-table("clocks",[Declared Tiny clock/reset domains],([Domain],[Clock],[Reset],[Reset primitive]),
  data.clocks.map(c=>(c.name,code(c.clock),code(c.reset),code(c.reset_primitive))),widths:(0.65fr,1.1fr,1.5fr,0.9fr))
External reset is asynchronously asserted and synchronously released. The watchdog requests a whole-system restart while
retaining its own reset-cause information. Debug hart reset has a narrower scope. SRAM contents are *not initialized by reset*;
the runtime explicitly establishes initialized data and BSS.

There is no dynamic frequency switching, independent sleep clock or guaranteed retention mode in this release. A watchdog
sharing the failed system clock cannot promise recovery from that clock failure. The existing RTL timing target must not be
advertised as a qualified voltage/frequency operating point.
#source-note("rtl/tiny/integration/clock_reset_domains.json",title:"Clock/reset inventory and debug crossings")

== Bus Transactions, Arbitration and Errors <tiny-bus>
The two initiators are CPU and DMA. They share *one active read or write transaction globally*. The fabric saves source,
direction, address and attributes, forwards the request, and retains ownership until the terminal B or RLAST handshake.
Read/write request arbitration is round-robin; it is not a throughput guarantee or an unrestricted liveness guarantee.

Memory transfers support naturally aligned 1/2/4-byte beats and up to 16 INCR beats. Single-beat FIXED is also admitted.
The complete address span must remain within one decoded target and one 4 KiB page without overflow. MMIO accepts only
one beat. The addressed register can impose stricter width/strobe rules; Tiny SYSCTRL requires aligned full-word writes.
#ds-table("bus-rules",[Transfer outcome and software consequence],([Condition],[Result],[Required handling]),(
  ([Legal SRAM access],[Target response with saved ID/owner],[Do not reuse DMA buffers before completion.]),
  ([XPI memory aperture],[Mapped reads; target controls memory-write rejection],[Programming uses the indirect command interface.]),
  ([Illegal size/burst/lock/alignment/span],[SLVERR responder],[Correct the request; preserve diagnostic context.]),
  ([Unmapped target],[DECERR responder],[Treat the address as unavailable, not scratch memory.]),
  ([Unsupported APB offset/write],[PSLVERR, propagated as a bus error],[Do not retry an unsupported control indefinitely.])),widths:(1.1fr,1.4fr,1.65fr))

AW and W are independent. W is backpressured until the saved write address reaches its target; another requester cannot
take over accepted write data. Rejected reads return the advertised response beat count, and rejected writes drain their
accepted data before B. Backpressure requires valid payloads to remain stable.
#timing("axi4",[Representative AXI read response and backpressure; Tiny uses 32-bit data and one-bit ID.])
#timing("apb4",[APB4 setup/access sequence with a wait state; address and write data remain stable.])
#source-note("rtl/tiny/top/tiny_axi4_fabric.sv",title:"Saved ownership, admission and terminal handshake")
#source-note("rtl/ip/interconnect/axi4_error_slave.sv",title:"Error response and write-drain implementation")

== Memory Map and Access Conventions <tiny-addresses>
#ds-table("memory-map",[Canonical Tiny address windows],([Region],[Base],[Last address],[Size]),
  data.regions.map(r=>(code(r.symbol),code(r.base_hex),code(r.end_hex),r.size_label)),widths:(1.2fr,1fr,1fr,0.65fr))
The Flash alias and XPI aperture identify memory routing, not fitted NOR capacity. The selected acceptance device and slot
configuration remain separate. Only SRAM is the application RAM in this profile. Unsupported holes and omitted peripheral
addresses must not be probed speculatively or reused as memory.

Register tables specify local offsets, access, reset and side effects. *W1C acknowledgement uses an explicit mask*;
read-modify-write can clear unrelated pending events. A live value or producer-dependent field need not equal its reset
assignment when software later reads it. Use coherent snapshots for multiword counters.

== Interrupt and DMA Request Routing <tiny-irq>
#ds-table("irq-map",[Tiny interrupt wiring],([Source],[Core bit],[External ordinal],[Producer]),
  data.interrupts.map(r=>(r.name,str(r.core_bit),if r.core_bit < 2 {[Local]} else {str(r.core_bit - 2)},code(r.signal))),widths:(1.05fr,0.5fr,0.7fr,1.95fr))
Core bits 0/1 are CLINT software/timer causes. The other 30 positions feed Hazard3 external interrupt inputs;
*external ordinal equals core bit minus two*. All omitted producers are tied zero. A register index, DMA selector and
interrupt number are different namespaces. Core bits here number the wrapper input vector, not architectural CSR bit positions.
#ds-table("dma-routes",[Enabled DMA requests and software channel conventions],([Selector],[Endpoint],[Channel convention]),(
  ([0],[Software-paced memory transfer],[3 bulk, or explicitly reserved free channel]),
  ([3 / 4],[XPI transmit / receive],[3]),([5 / 6],[UART0 transmit / receive],[0]),
  ([7 / 8],[I2C0 transmit / receive],[1]),([9 / 10],[I2C1 transmit / receive],[2])),widths:(0.7fr,2fr,1.4fr))
UART1 uses PIO/IRQ. The shared SDK names other requests and channels, but Tiny must reject unavailable selections.
The current DMA transfer validator accepts 32-bit MM-to-MM work; stream modes are disabled. Serialize shared channel
conventions rather than assuming that each API owns a permanently independent engine.
#source-note("rtl/tiny/integration/soc_topology.json",title:"Interrupt and GPIO bindings")
#source-note("crt/src/hal/dma_math.c",title:"Tiny DMA kind/request validation")

== Peripherals
Each IP starts on a new page. Repeated instances retain separate address/IRQ entries; their common register layout is
documented once. The fields below are extracted from the active common implementation with Tiny parameter overrides;
SYSCTRL and the ARCHINFO identity override are bound to Tiny-owned RTL.
#for entry in data.catalog {reference(entry)}

== Pins and Board Connections <tiny-pins>
The following is a *logical signal-pad inventory*, not a package pin numbering or an approved PCB schematic. Pad cells,
power/ground pins, voltage domains and package bonding require the selected physical implementation.
#ds-table("pads",[Tiny logical signal pads],([Signal],[RTL direction],[Pad kind]),
  data.pads.map(p=>(code(p.name),p.direction,p.kind.replace("_"," "))),widths:(2fr,0.8fr,1.2fr))
#let gpio-mode(mode) = {
  let terms=mode.inputs + if mode.do.contains("'") {()} else {(mode.do,)}
  if terms.len()==0 {[Not routed]} else {code(terms.join(" / "))}
}
#ds-table("gpio-alternates",[Tiny GPIO alternate-function routes],([GPIO],[ALT0],[ALT1]),
  data.gpio.map(g=>(str(g.pin),gpio-mode(g.alt0),gpio-mode(g.alt1))),widths:(0.4fr,1.85fr,1.85fr))
Disable producers and release output enables before changing a live pad route. I2C and open-drain signals require external
pull-ups and compatible levels. Dedicated UART and XPI pins are not reassigned through the GPIO mux. Verify complete
pin groups, reset drive state and external clock availability before enabling a device.

== Electrical, Package and Reliability Boundaries
This source-level publication supplies *no numerical production electrical ratings*. TBD means unavailable evidence,
not zero, unlimited range or permission to select a convenient value. Functional clock names are not independent power rails.
#ds-table("physical-gaps",[Evidence required before physical product claims],([Area],[Required evidence],[Current state]),(
  ([Supply / absolute maximum],[Pad/core rails, sequencing, injection/ESD limits, approved conditions],[TBD]),
  ([AC/DC timing],[PVT, loading, clock reference edge, setup/hold and input/output limits],[TBD]),
  ([Package / pinout],[Die pad and package pin mapping, dimensions and bonding],[TBD]),
  ([Thermal / power],[Package/board/test conditions, workloads, voltage and measured results],[TBD]),
  ([Reliability / ordering],[Qualification records, traceable device revisions and order codes],[TBD])),widths:(1fr,2.5fr,0.5fr))
No package photograph, fabricated part number, regulatory mark or silicon speed grade is inferred from the digital profile.
The documented STA deficit remains visible in @tiny-evidence; it is not an operating specification.

= Software
== Reset, Boot and Linker Layout <tiny-boot>
Reset enters the Flash alias at #code(data.reset_address). The Tiny runtime excludes the generic PSRAM delay/setup branches.
With CSR support selected it masks interrupts and installs the direct trap entry, initializes registers/stack, copies code
and data when load/run addresses differ, clears BSS, performs the configured premain work, and enters main.
#flow("boot",(
  [Reset / JTAG state established · Fetch from NOR alias],
  [Mask interrupts; establish trap entry and register/stack state],
  [Tiny skips PSRAM setup · Copy initialized code/data into SRAM],
  [Clear SRAM BSS · Perform configured premain initialization],
  [Enter Tiny application · Handle terminal result or watchdog restart]
),[Tiny ordinary startup: source order, not a guaranteed boot-time measurement.])
The `ld2_all_sram` layout places runtime code, data, BSS and stack in SRAM with initialized material loaded from Flash.
Memory-map capacity, load-image bytes, runtime static occupation and stack high-water demand are different quantities.
Inspect the actual ELF/MAP and reserve buffers plus stack/scratch margin before deployment. No matching size/high-water
measurement is supplied by this datasheet build.
#source-note("crt/arch/riscv/startup.S",title:"Tiny conditional startup and relocation")
#source-note("crt/linker/ld2_all_sram.lds",title:"Flash load / SRAM runtime linker layout")

== SDK, API Completion and Polling
Consume public headers under #code("<retrosoc/...>") and the #code("rs_") namespace. The Tiny build selects product-specific
application composition and generated address/IRQ/capability metadata. This does not generate replacement IP register ABIs.
Unsupported PLL, application-hart or selectable-core APIs return an error before MMIO.

*A successful API return describes that API's completion boundary*: a start command can be accepted before its operation
finishes. FIFO acceptance is not completed serial transmission. A timeout can leave work active and buffers owned by a
device. Capture state and complete abort/drain before reuse.

Software timeout arguments are polling budgets, not milliseconds. CPU/compiler work and bus stalls affect elapsed time;
a budget cannot bound a register read that never returns. Hardware counters and device-specific timeouts use their own
documented clock units. Use CLINT or another appropriate timebase when an elapsed-time deadline is required.

== DMA Descriptors and Buffer Lifetime <tiny-dma-format>
#tcd-diagram()
#ds-table("tcd-fields",[Source-derived DMA C descriptor layout],([Byte offset],[Field],[Bytes],[Role]),
  data.tcd.map(f=>(code("0x"+upper(str(f.offset,base:16))),code(f.name),str(f.bytes),f.role)),widths:(0.75fr,1.7fr,0.45fr,1.1fr))
The descriptor is 64 bytes and each descriptor address is 64-byte aligned. Tiny permits only the implemented transfer kind,
request, increment and width combinations. Stride fields remain zero and row count is at most one. A field in the ABI is
not evidence of cyclic, 2D or stream support. HAL result fields do not imply that hardware directly writes every result word.

#ds-table("tcd-control",[Descriptor control positions and portable Tiny use],([Bits],[Field],[Meaning / restriction]),(
  ([0],[VALID],[Must be set for a submitted descriptor.]),
  ([1 / 2],[SRC_INC / DST_INC],[Increment the corresponding memory address; use the endpoint's required mode.]),
  ([3 / 4],[CRC_ENABLE / CRC_FINAL],[Select the implemented CRC processing/final comparison.]),
  ([5 / 6],[INT_DONE / INT_ERROR],[Declared SDK flags; use the channel event-enable/IRQ registers rather than assuming per-descriptor IRQ gating.]),
  ([10:8],[KIND],[Tiny admits MM-to-MM value zero only.]),
  ([15:12],[REQUEST],[Zero or 3 through 10 in the current Tiny request map.]),
  ([17:16],[PRIORITY],[Two-bit software priority value.]),
  ([24:20],[BURST],[0 selects the 16-beat default in descriptor submission; 1 through 16 select a bound. Direct configuration requires 1 through 16.]),
  ([Other bits],[Reserved / unused],[Use zero for compatibility; a field declaration does not establish an extra operation.])),widths:(0.6fr,1.05fr,2.5fr))
The current HAL chain helper submits one descriptor at a time, waits, copies result registers into the descriptor and then
follows #code("next_ptr"), bounded by #code("max_tcds"). It is not an autonomous circular-queue API. On a timeout or error,
the helper records observed progress but the caller must still confirm abort/drain before releasing memory.

Reserve channel, descriptor and payload storage through completion or confirmed recovery. Publish CPU-produced input with
the required fence before starting the non-CPU master. Tiny has no application-hart cache handoff protocol; importing the
Mini HP cache-clean service would describe nonexistent hardware.
#flow("dma-recovery",([Validate channel / request / bounds and reserve storage],
  [Publish descriptor/input and configure while idle], [Start and wait for the required completion boundary],
  [On failure: capture fault/progress, abort, confirm drain], [Release or reuse storage only after ownership is safe]),
  [DMA lifetime and recovery ordering. A polling timeout is not an idle acknowledgement.])
#source-note("crt/include/retrosoc/hal/dma.h",title:"Handwritten descriptor and public HAL ABI")
#source-note("crt/src/hal/dma_math.c",title:"Descriptor validation and unsupported combinations")

== Acceptance and Diagnostics <tiny-diagnostics>
Both #code("bringup") and #code("ci_smoke") select the Tiny acceptance entry point. A controlled first boot with a clear
watchdog reset count performs the tests below, then deliberately requests watchdog reboot. A subsequent boot with a nonzero
retained reset count takes the early successful terminal path. *A pre-existing watchdog reset count is not proof that this
boot executed every test.* Record initial state, image, profile and the final simulator result.
#ds-table("acceptance-codes",[Tiny application failure codes from the reviewed main sequence],([Code],[Stage]),(
  ([1],[Primary UART initialization]),([2],[Watchdog status read]),([3],[Tiny build/topology and SRAM discovery]),
  ([4],[Compressed execution, A-disabled ISA and exception handler setup]),([5],[Atomic/unmapped probes and first fault]),
  ([6],[Memory/UART DMA]),([7],[CLINT progression and timer interrupt]),([8],[RTC, PWM discovery and unsupported-control rejection]),
  ([9],[Watchdog configuration/start]),([10],[GPIO, UART1 loopback and I2C NACK checks])),widths:(0.4fr,3.8fr))
The first valid full-word SYSCTRL TEST_STATUS write is sticky. Bit 31 is valid, bit 0 pass and bits 15:8 the result code.
The testbench must emit #code("SIM_TEST_PASS") and the command must succeed without failure/timeout markers. UART startup
text is diagnostic only. The compact assembly netlist boot test has a narrower scope than the full SDK image.
#source-note("app/apps/ci_smoke/tiny.c",title:"Acceptance order, reset-count branch and terminal codes")
#source-note("app/asm/tiny_boot.S",title:"Separate compact netlist boot test")

= Implementation and Evidence
== Reproducible Development Flow
Start from the committed IHP130 Tiny profile. Use the existing locked dependency setup and doctor flow, then build the
Tiny firmware and selected simulator. The publication pipeline itself does not perform an EDA campaign.
#code-block(raw("make CONFIG=configs/ci/ihp130-tiny.mk setup\nmake CONFIG=configs/ci/ihp130-tiny.mk doctor\nmake CONFIG=configs/ci/ihp130-tiny.mk firmware sim\nmake CONFIG=configs/ci/ihp130-tiny.mk SIMU=IVERILOG firmware sim\nmake CONFIG=configs/ci/ihp130-tiny.mk regress-pr",block:true))
Tiny source lists exclude Mini product RTL, RIB/RIBP, application-CPU generation and accelerator inputs. Common RTL and
Hazard3 remain revision-locked. Keep generated files in the selected build variant; missing unrelated accelerator corpora
must not become prerequisites for the Tiny publication.

== Verification Status and Qualification Gaps <tiny-evidence>
Readiness is *prototype*. #data.evidence.boundary
#ds-table("evidence",[Dated repository verification record and publication boundary],([Area],[What the record reports],[Interpretation]),
  data.evidence.records.map(r=>(r.at(0),r.at(1),r.at(2))),widths:(0.8fr,1.7fr,1.65fr))
No matching current-commit raw qualification report is attached. The documented setup WNS of *−455.18 ns* and TNS of
*−13,049,600 ns* describe the dated IHP130 slow-library analysis at a 41.666666667 ns clock constraint, with a reset-distribution deficit. They must not become a positive
24 MHz timing claim. Subsequent source-path migration has its own bounded follow-up record; it does not rerun all earlier stages.

Publication tests establish document/source consistency and layout, not electrical compliance, full protocol coverage or
silicon operation. Future pass records must identify exact source/profile, tool/model versions, executed stage, raw report
and result. Keep skipped, failed and unfinished work visible.
#source-note("docs/ip/tiny-soc-verification.md",title:"Historical evidence, timing deficit and remaining work")

= Appendix: Global Register Index <tiny-register-index>
Use the instance-qualified address below, then follow the canonical register reference. GPIO common discovery offsets
exist in both views. Repeated groups retain explicit indices; gaps are not additional registers. Addressability does not
override the register's access, alignment, strobe or side-effect rules.
#for entry in data.catalog {
  if entry.id=="uart1" {minor-title("UART1 - shared UART register ABI")} else {minor-title(entry.title)}
  let ref=data.registers.at(entry.family)
  for symbol in entry.regions.filter(s=>s.starts-with("APB4_")) {
    let region=data.regions.find(r=>r.symbol==symbol)
    let records=()
    for group in ref.groups {
      let applies=entry.family!="gpio" or group.id=="common" or (group.id=="user" and symbol=="APB4_GPIO") or (group.id=="admin" and symbol=="APB4_GPIO_ADMIN")
      if applies {
        for instance in range(group.count) {
          for reg in ref.registers.filter(r=>r.group==group.id) {
            let address=region.base+group.base+instance*group.stride+reg.offset
            records.push((code("0x"+upper(str(address,base:16))),link(label("reg-"+entry.family+"-"+reg.key),code(reg.name)),
              if group.count>1 {str(instance)} else {[—]},reg.access))
          }
        }
      }
    }
    ds-table("index-"+symbol,[#symbol instance addresses],([Absolute address],[Register],[Index],[Access]),records,widths:(1fr,1.9fr,0.4fr,0.85fr))
  }
}

= Document Control
== Revision History
#ds-table("revision",[Document revision history],([Date],[Version],[Change]),
  ((doc.date,[v#doc.version #doc.status],[Initial Tiny Gen1 complete reference; independent source extraction and Tiny-qualified integration.]),),widths:(0.8fr,0.85fr,2.5fr))

== Sources, License and Contact <publication-provenance>
Hardware/software snapshot: #code(doc.source_revision). This document's source manifest records the exact technical files,
publication files, managed revisions and fonts/packages used for the build. The PDF digest, chapter review and actual
validation record accompany the output; the document date is not a hardware measurement date.

The publication uses locked Typst 0.15.1, existing Inter/Fira Code/Noto fonts and the project's managed vector/waveform packages.
The prototype brand is Rill; this identity does not establish an orderable or qualified silicon product.

The project retains its Mulan PSL v2 license and third-party component/font licenses. Obtain the current source and license
inventory from #link("https://github.com/retroSoC/retroSoC")[the project repository].
Contact: #link("mailto:"+doc.author_email)[#doc.author (#doc.author_email)]. Maintainer: #doc.maintainer.

