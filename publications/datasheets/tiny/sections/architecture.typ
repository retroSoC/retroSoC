#import "../diagrams.typ": access-matrix
#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow
#import "../soc-functional.typ": functional-architecture
#import "../waveforms.typ": timing

= System Architecture
== Introduction <tiny-core>
=== Management Processor and Local Memory
#functional-architecture()

Hazard3 is hart zero. The locked dual-port wrapper selects the C and M extensions and disables A for Tiny. Instruction fetch
and load/store use independent AHB ports through separate local SRAM frontends; non-SRAM accesses use the tagged slow path.
JTAG supports halt/resume, register access and halted-hart abstract-command memory access, without an independent system-bus master.
Debug hart reset first halts the hart and drains accepted local I/D and slow-path responses. SRAM and unrelated DMA work stay active.

The system has no application hart, MMU/Linux platform, hardware cache-coherent multicore organization or product extension
slots. CPU-visible SRAM, XPI and APB routes are the implemented interconnect. The single-hart architecture does not remove
the need for software/DMA buffer ownership and fences.
#architecture()
#source-note("rtl/tiny/top/retrosoc_tiny.sv",title:"Tiny product integration and parameters")
#source-note("rtl/tiny/top/tiny_cpu_wrapper.sv",title:"Dual-port CPU ISA, AHB ports and debug wrapper")
#source-note("rtl/tiny/top/tiny_sram.sv",title:"Four local SRAM groups and external attachment")

== Interconnect <tiny-bus>
=== AXI4 and APB4 Interfaces
The three active external initiators are CPU slow path, central DMA and SDIO private DMA. Each SRAM group, XPI memory endpoint and APB peripheral has independent transaction ownership.
CPU slow traffic admits one combined operation; DMA can have one read and one write outstanding across different targets.
Each target admits one combined read or write. CPU local instruction/data requests remain independently arbitrated within
each SRAM group. Saved ownership includes accepted address and response buffers and lasts through the upstream B/RLAST handshake.
Owner arbitration is round-robin with fair direction selection. Progress bounds require a running clock and peer progress.
Separate APB bridges keep independent controls outside a FIFO-waiting peripheral's transaction.

Fault accounting counts each failed transaction once, including errors before the final read beat. Simultaneous events
increment the saturating count individually; first-fault metadata uses ascending owner, instruction before data, then read
before write. CPU is owner0, central DMA owner1, and SDIO private DMA owner2. FAULT_DETAIL retains raw AXI response 2/3. Clearing validity
does not clear the count, and a simultaneous hardware event wins over clear.

Memory transfers support naturally aligned 1/2/4-byte beats and up to 16 INCR beats. Single-beat FIXED is also admitted.
The complete address span must remain within one decoded target and one 4 KiB page without overflow. MMIO accepts only
one beat. The addressed register can impose stricter width/strobe rules; Tiny SYSCTRL requires aligned full-word writes.
#ds-table("bus-rules",[Transfer outcome and software consequence],([Condition],[Result],[Required handling]),(
  ([Legal SRAM access],[Target response with saved ID/owner],[Do not reuse DMA buffers before completion.]),
  ([XPI memory aperture],[Mapped reads and slot-qualified PSRAM writes],[NOR program/erase uses the indirect command interface.]),
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

#access-matrix()

=== Address Mapping <tiny-addresses>
#ds-table("memory-map",[Canonical Tiny address windows],([Region],[Base],[Last address],[Size]),
  data.regions.map(r=>(code(r.symbol),code(r.base_hex),code(r.end_hex),window-size(r))),widths:(1.2fr,1fr,1fr,0.65fr))
The Flash alias and XPI aperture identify memory routing, not fitted NOR capacity. The selected acceptance device and slot
configuration remain separate. Main SRAM is the startup/runtime RAM; optional NSS1 PSRAM is usable only after successful explicit initialization. Unsupported holes and omitted peripheral
addresses must not be probed speculatively or reused as memory.

Register tables specify local offsets, access, reset and side effects. *W1C acknowledgement uses an explicit mask*;
read-modify-write can clear unrelated pending events. A live value or producer-dependent field need not equal its reset
assignment when software later reads it. Use coherent snapshots for multiword counters.

== Memory Attributes and DMA Buffer Ownership <tiny-memory-ownership>
Tiny has one hart and no application-CPU cache handoff. Local SRAM, external serial-memory apertures and
MMIO controls nevertheless have different access and lifetime rules. A single CPU does not make DMA buffers
implicitly safe: completion, fences and peripheral ownership still apply.
#ds-table("memory-attributes",[Software-visible memory classes],([Class],[Access and use],[Ownership boundary]),(
 ([Main SRAM],[128 KiB; code, data, stack and descriptors],[CPU local I/D and external masters arbitrate per group.]),
 ([Boot NOR / alias],[Instruction and data reads; indirect program/erase],[Keep update execution and dependencies in SRAM.]),
 ([NSS1 PSRAM],[8 MiB reference device after explicit initialization],[Clock/reset changes invalidate the session; preserve slot and LUT ownership.]),
 ([MMIO],[Device-defined reads, writes, strobes and side effects],[Never use as ordinary RAM or speculative scratch space.])),widths:(0.7fr,1.6fr,1.9fr))
Publish CPU-produced data before starting a non-CPU master. Keep descriptors and payload stable until the
owning operation completes or abort/drain is confirmed. A timeout is not a release acknowledgement.
#source-note("rtl/tiny/top/tiny_cpu_mem.sv",title:"Local and slow-path decoding")
#source-note("crt/src/hal/dma.c",title:"Submission, polling and completion")

== Clock and Reset <tiny-clock>
Tiny has distinct AON, SYS, MEM, PCLK, AUDIO, camera-pixel and debug domains. AON uses normalized REF24; CPU/main SRAM/fabric/SDIO use SYS,
XPI uses MEM, and central DMA plus peripheral/security service use PCLK. I2S data uses AUDIO; JTAG uses external TCK.
Declared crossings and reset barriers remain required even for nominal integer clock ratios.
#clock-tree()
#ds-table("clock-profiles",[Implemented digital clock profiles; no physical speed rating],([Profile],[SYS MHz],[MEM MHz],[PCLK MHz],[Availability]),(
  ([SAFE24],[24],[24],[24],[Boot/default and fallback on both PDKs]),
  ([PLL192],[192],[96],[48],[ICS55 functional PLL profile]),
  ([PLL240],[240],[120],[60],[ICS55 functional PLL profile]),
  ([XIN48 / XIN96],[48 / 96],[48 / 96],[48 / 48],[Explicit no-PLL external-input profiles; REF stays 24 MHz])),widths:(0.85fr,0.55fr,0.55fr,0.55fr,1.8fr))
#ds-table("clocks",[Declared Tiny clock/reset domains],([Domain],[Clock],[Reset],[Reset primitive]),
  data.clocks.map(c=>(c.name,code(c.clock),code(c.reset),code(c.reset_primitive))),widths:(0.65fr,1.1fr,1.5fr,0.9fr))
Clock requests drain accepted work and switch through a safe source before publishing committed rates. A failed drain
does not authorize dropping traffic. PLL lock timeout returns SAFE24; stopped-source recovery has a separate reset contract.
The @rcu chapter specifies commands, snapshots and recovery. Timing observation and digital profile availability remain
separate from final physical closure.

CPU WFI gating affects its leaf only. Debug hart reset drains CPU work while SRAM and other masters remain active.
Warm system reset preserves SRAM payload and recorded cause/fault/debug state, returns SAFE24 and resets functional RTC/WDG
state. SRAM contents are not initialized by reset; startup establishes initialized data and BSS. AON is a clock/control
domain, not a demonstrated independent power or battery-retention domain. Missing XIN still requires external recovery.
#source-note("rtl/tiny/integration/clock_reset_domains.json",title:"Clock/reset inventory and crossings")
#source-note("docs/ip/tiny-soc-r2-clock-reset.md",title:"Implemented transition, reset and failure contracts")

== Interrupt System <tiny-irq>
#ds-table("irq-map",[Tiny interrupt wiring],([Source],[Core bit],[External ordinal],[Producer]),
  data.interrupts.map(r=>(r.name,str(r.core_bit),if r.core_bit < 2 {[Local]} else {str(r.core_bit - 2)},code(r.signal))),widths:(1.05fr,0.5fr,0.7fr,1.95fr))
Core bits 0/1 are CLINT software/timer causes. The other 30 positions feed Hazard3 external interrupt inputs;
*external ordinal equals core bit minus two*. All omitted producers are tied zero. A register index, DMA selector and
interrupt number are different namespaces. Core bits here number the wrapper input vector, not architectural CSR bit positions.


== DMA Request, Interrupt and Event Routing <tiny-dma-routing>
#ds-table("dma-routes",[Enabled requests and software channel conventions],([Selector],[Endpoint],[Channel convention]),(
  ([0],[Software-paced memory transfer],[3 bulk, or explicitly leased free channel]),
  ([1 / 2],[I2S transmit / receive],[6 / 7]),([3 / 4],[XPI transmit / receive],[3]),
  ([5 / 6],[UART0 transmit / receive],[0]),([7 / 8],[I2C0 transmit / receive],[1]),
  ([11],[DVP RAW / PPALite PROCESS],[2]),([12 / 13],[Crypto input / output],[4 / 5]),
  ([16 / 17],[SPI transmit / receive],[Bound leased channel; display normally uses 3])),widths:(0.7fr,2fr,1.4fr))
The implemented mask is #code("0x000339FF"). I2C1 selectors 9/10 and PIO-lite selectors 14/15 are absent. SDIO is a separate
fabric master and does not use this table. Channel conventions are software leases, not separate physical engines.
DMA V2.2 request bit 4 must be retained in both register and TCD programming. Stream, memory and SPI port admission have
different legal transfer forms. PROCESS requires PPALite's exact armed direct DMA2 job; processed TCDs are rejected.
See @dma, @spi and @ppalite for quotas, response drain and recovery.
#source-note("rtl/tiny/integration/soc_topology.json",title:"Interrupt, DMA and GPIO bindings")
#source-note("crt/src/hal/dma_math.c",title:"Tiny DMA transfer-kind and request validation")

== Bus Master Coordination and Resource Ownership <tiny-master-ownership>
The CPU slow path, central DMA and SDIO private DMA are independent external requesters. CPU local SRAM
instruction/data paths have separate group attachments. Software must coordinate these clients even though
there is only one hart. DMA channel numbers do not identify independent peripheral ownership.
#flow("master-ownership",([Reserve peripheral route, channel and memory],
 [Configure while idle and publish immutable inputs],[Start the owner and service its interrupts],
 [Observe peripheral completion plus transport drain],[Return ownership only after completion or recovery]),
 [Ownership transfer for Tiny bus masters. A command accepted by a register is not completed payload traffic.])
Acquire shared resources in a consistent order and release them after all accepted responses are drained.
For SDIO, preserve descriptor and buffer lifetime through its own command/data/writeback status. Do not
substitute central-DMA completion for private-DMA completion. See @sdio and @dma.
#source-note("rtl/tiny/top/tiny_axi4_fabric.sv",title:"Active owners and target-local arbitration")

== Peripheral Coexistence and Resource Conflicts <tiny-conflicts>
#ds-table("coexistence",[Resource coexistence and route changes],([Use],[Owned resources],[Change/release condition]),(
  ([Audio],[GPIO12-17 ALT0; AUDIO; DMA6/7],[Stop/drain both directions and verify engine reset readiness.]),
  ([Camera],[GPIO12-23 ALT1; DMA2; CLKOUT; initialized PSRAM],[Excludes audio and conflicting PWM routes; complete frame and drain before consumers.]),
  ([Display],[GPIO27/28/31; GPIO30 D/C; DMA3],[D/C changes at clean held-CS boundaries; release only after wire/transport cleanup.]),
  ([NSS1 PSRAM],[Shared XPI engine; GPIO29 ALT0; slot1/LUT8-11],[Invalidate and reinitialize after reset or rate change.]),
  ([SD storage],[GPIO0-5; SDIO private DMA; SRAM bounce buffers],[Wait for command/data/status writeback; keep descriptors live.]),
  ([Bulk services],[DMA3 shared by XPI/CRC/WS2812/display],[Serialize leases; WS ownership continues through wire completion.])),widths:(0.7fr,1.65fr,1.85fr))

A route change is a lifecycle operation: stop admission, drain accepted payload, release drive enables,
change the complete pad group, configure the new clock-dependent timings and then re-enable the consumer.
Claims about simultaneous operation require a separate matching workload and pin-level result.
#source-note("rtl/tiny/integration/soc_topology.json",title:"Actual GPIO and DMA routes")

== Security and Access-Control Boundaries <tiny-security>
The publication does not define secure boot, authenticated update, privilege isolation, a trusted execution
environment or qualified entropy. GPIO user/management views and register locks constrain specific accesses;
they are not a general system security boundary. CRC detects the defined data corruption patterns and is
not authentication. Crypto algorithm support does not imply protected key provisioning or side-channel qualification.
Device-ID inputs are invalid/read-disabled; their offsets do not establish a provisioned unique identity.
#source-note("rtl/tiny/top/tiny_archinfo.sv",title:"Identity adapter and tied-off provisioning inputs")
#source-note("rtl/ip/peripheral/gpio_reg.sv",title:"GPIO view and lock rules")

== Debug, Diagnostics and Fault Recovery <tiny-system-diagnostics>
JTAG supports the implemented halted-hart debug path. Debug hart reset drains CPU local and slow-path work;
unrelated DMA traffic is not implicitly cancelled. Capture first-fault address/master/detail and operation
progress before acknowledging sticky status or applying a reset.
#flow("fault-recovery",([Capture fault, clocks, owner and progress],
 [Stop new work and preserve source/buffer ownership],[Abort using the affected peripheral's contract],
 [Confirm response drain and safe pad state],[Reinitialize invalidated state before retry]),
 [Fault recovery ordering; software polling cannot recover a bus access that never returns.])
Use @tiny-fault-reference for code namespaces and @tiny-evidence for evidence limits.
#source-note("rtl/tiny/top/tiny_sysctrl.sv",title:"First-fault and terminal-result state")

== Register Access and Programming Conventions <tiny-register-programming>
Use each register's documented access width, alignment and strobe policy. Tiny SYSCTRL requires aligned
full-word writes. Read-only, write-one-clear, write-one-set and command fields have different side effects;
do not apply a generic read-modify-write sequence to them.
Read multiword counters through their snapshot or coherent sequence. Respect busy-state restrictions and
keep the required clock running until completion. Reserved bits are not capability discovery.
The first valid full-word TEST_STATUS write is sticky until reset; a later pass cannot replace an earlier failure.
#source-note("rtl/tiny/top/tiny_sysctrl.sv",title:"Alignment, strobes and sticky test result")

== Interface Standards and Supported Subsets <tiny-interface-subsets>
#ds-table("interface-subsets",[Implemented digital interface subsets],([Interface],[Current Tiny subset],[Separate external boundary]),(
 ([AXI/APB],[32-bit data; selected AXI burst rules; APB4 register controls],[Not arbitrary AXI option support.]),
 ([XPI],[Single/dual/quad SDR; NOR and explicitly initialized NSS1 PSRAM],[Actual device commands, capacity and board timing.]),
 ([SPI0],[Master, 8/16-bit finite segments and qualified DMA ports],[Panel-specific command and pin timing.]),
 ([UART0 / I2C0],[FIFO UART; controller-mode I2C],[External levels, pull-ups and electrical compliance.]),
 ([SDIO0],[Native 1/4-bit card protocol and private DMA],[Card enumeration, media and physical qualification.]),
 ([I2S],[Stereo master and selected 16/24-bit formats],[No slave, TDM or PDM claim; external audio clock/device.]),
 ([DVP / WS2812],[8-bit bounded capture; programmable LED serial timing],[No continuous-FPS or arbitrary-device qualification.])),widths:(0.8fr,1.9fr,1.5fr))
Register and SDK declarations must be interpreted using the selected product capability and the owning IP chapter.
