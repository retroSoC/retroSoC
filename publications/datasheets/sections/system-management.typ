#import "../style.typ": *
#import "../system-figures.typ": sequence-diagram

#include "routing-reference.typ"

== Multicore Operation and Resource Ownership <multicore-operation>
Hazard3 is the root-management hart; VexiiRiscv is the application hart. Linux does not take
over the SoC's root clock, reset, admission and recovery controls merely by booting. Decide
which software owns each resource and buffer before enabling interrupts or bus mastering.

=== Control and interrupt authority
#ds-table("root-authority",[System authority and software responsibilities],
  ([Actor],[Authority],[Required cooperation]),
  (([LP firmware],[Root configuration, ownership and lifecycle writes; first-fault recovery.],[Coordinate application shutdown and do not acknowledge cache cleaning prematurely.]),
   ([HP software],[Application execution and permitted MMIO/data accesses.],[Obey assigned resources, cache handoff, bounded buffers and stop requests.]),
   ([Resource Controller],[Owner/lock state, admission request and owner-directed IRQ routing.],[Software must wait for blocked/idle acknowledgement and prepare the receiving owner.]),
   ([DMA / I/O masters],[Transactions admitted by the topology and resource policy.],[Descriptors and data remain under exclusive ownership until completion or completed recovery.])),
  widths:(0.8fr,1.6fr,1.8fr))

The central Resource Controller covers DMA, USB2, SDIO0/1, SPI-SD, EXT-H, JPEG and APU.
An owner selects one interrupt route, not both LP and HP simultaneously. The resource
#code("CONTROL.RESET") request masks both routes; controller reset assignments and dynamic
IRQ observations are distinguished in @reset-summary. Owner locks are sticky under their
reset contract. Per-IP local interrupt causes
must still be acknowledged at the peripheral; changing the route does not clear a cause.

=== Resource handoff procedure
#figure(sequence-diagram((
  [*Prepare receiving owner* \ Buffers and handler ready],
  [*Quiesce old owner* \ Block new work],
  [*Wait for acknowledgement* \ Admission blocked \ Resource / fabric idle],
  [*Transfer ownership* \ LP writes owner \ Optional sticky lock],
  [*Verify owner and route* \ Read back status],
  [*Resume work* \ Release quiesce \ Enable prepared handler])),caption:[Root-managed peripheral handoff; cache visibility is a separate prerequisite.])
+ Agree on buffer disposition and stop the old software producer. Complete required cache
  maintenance before allowing another processor or device to consume the data.
+ Prepare the new owner's driver and interrupt handler while the resource remains quiescent.
+ Use #code("rs_resource_set_owner()") for the supported LP-managed sequence. It requests
  quiesce, waits for blocked and idle status, writes and verifies the owner, then releases quiesce.
+ Check its result and re-read status. Do not continue on an owner mismatch, locked resource,
  fault or timeout. Only enable the new owner's application traffic after the result is known.
+ Set the sticky lock only when later handoff is intentionally prohibited until the specified reset.

The current implementation can use conservative whole-data-plane idle conditions, and shared
gateways can delay a handoff while unrelated traffic remains active. A timeout does not prove
an independent engine reset occurred. Preserve the old/new owner observation, pending IRQ,
blocked/idle state and fault before deciding whether to retry. Recovery must follow the
individual IP contract, especially where the central reset request is not connected downstream.

=== Mailbox and cache-clean protocol
Mailbox messages carry control information, not an automatic transfer of payload ownership.
Validate sequence and bounded payload references at the receiver. Define what happens when a
message is duplicated, delayed or belongs to a previous boot epoch. These application rules
must be supplied by the integration; the register interface alone does not implement them.

For HP shutdown, #code("rs_resource_get_cache_status()") exposes the live clean request.
LP may call #code("rs_resource_acknowledge_cache_clean()") only after the HP-side software
has completed the agreed ranges and reported completion. The API checks for a live request;
it does not itself clean HP caches. A missing acknowledgement is recorded as a forced fault
by the lifecycle policy. See @memory-coherency and @operating-states.
#source-note("docs/ip/resource-controller.md",title:"Resource ownership, cache and delivery boundaries")
#source-note("crt/src/hal/resource.c",title:"Actual HAL handoff and acknowledgement sequence")
#source-note("docs/ip/hp-platform.md",title:"HP interrupt and mailbox platform")

#include "coexistence-reference.typ"

== Security and Access-Control Boundaries <security-boundaries>
The current protection model limits bus admission and root-control access. It must be used
with explicit software ownership and does not constitute a certified secure-boot or key-storage
system. A cryptographic accelerator provides operations; the complete trust model is separate.

#ds-table("security-boundaries",[Implemented control boundaries and excluded guarantees],
  ([Mechanism],[Published boundary],[Not established by that mechanism]),
  (([Root-control firewall],[HP MMIO cannot write protected management controls.],[A complete privilege/isolation proof for arbitrary hostile software.]),
   ([Data initiator policy],[Read/write/execute/cache restrictions by initiator and target.],[CPU cache coherence or protection from a corrupted descriptor within an allowed range.]),
   ([EXT-H address bounds],[Separate permitted read and write ranges at admission.],[An IOMMU or per-process virtual-address translation service.]),
   ([Owner/lock and IRQ route],[One selected owner and root-managed locked transitions.],[Universal independent peripheral reset or power isolation.]),
   ([AES/SHA/RSA block],[Documented LP-controlled computation and buffer interfaces.],[Secure persistent keys, side-channel resistance or algorithm certification.]),
   ([Boot CRC and bounds],[Accidental-corruption and layout checks in the supplied loader.],[Image authentication, anti-rollback or a signed recovery chain.]),
   ([RNG integration],[Controller and diagnostic stream behavior.],[Qualified cryptographic entropy from the current source.])),
  widths:(0.9fr,1.5fr,1.7fr))

Before enabling a bus master, validate descriptor addresses, lengths and ownership and install
the narrowest supported EXT-H bounds. Keep keys and sensitive working buffers under a defined
software lifetime; overwrite or retire them using the relevant platform policy after use.
No immutable boot root, fuse provisioning flow or production debug-lock policy is specified here.

Treat rejected access as a fault to diagnose, not a signal to widen permissions automatically.
Capture master, target/address and access type before clearing status. A recovery action must
not grant HP root writes or bypass an inactive memory-pad restriction. System designers needing
authenticated updates or confidential storage must add and verify those mechanisms separately.
#source-note("rtl/mini/integration/soc_topology.json",title:"Canonical initiator access policy")
#source-note("docs/ip/extensions.md",title:"EXT-H range checks and lifecycle")
#source-note("docs/ip/crypto.md",title:"Cryptographic implementation and security limits")
#source-note("app/apps/hp_boot/main.c",title:"Loader CRC/bounds checks and failure handling")

== Debug, Diagnostics and Fault Recovery <system-diagnostics>
Bringup should establish a reliable LP console and management debug path before depending on
HP applications or external memory. A successful debugger connection validates only the tested
transport and target configuration, not the remaining peripheral or physical implementation.

#change-start("diagnostic-lookup-link", "Diagnostics: code-reference link", category:"cross-reference")
Use @fault-code-reference to decode a captured status in its producing module's namespace.
Retain the first event before following the acknowledgement and recovery order below.
#change-end("diagnostic-lookup-link")

=== Debug connection and scope
The management JTAG transport uses TCK, TMS, TDI, TRST_n and TDO. Connect them using an approved
board pinout and compatible I/O levels. Logical pad names do not determine connector pins or
package numbering. The clock/reset map's JTAG constraint is not a characterized pad frequency limit.

+ Start with the management target and the committed debug profile. Read the configured
  identity before loading an ELF or changing memory.
+ Confirm that debugger accesses reach the intended SRAM window. The management Debug Module
  has no independent system-bus master; memory operations execute through the halted hart.
+ Keep the LP clock and root-control path alive during debugging. Management debug reset waits
  for its bridge to become idle and resets that hart/bridge, while peripheral state can remain live.
+ Select shared HP JTAG only under the documented held-in-reset condition. The HAL checks
  release state, but the integrator must also observe actual lifecycle completion.

Breakpoints and single-step can alter timing and watchdog behavior. Do not publish timing or
throughput measurements taken with an active halt/step session as normal-run results. Use the
OpenOCD/GDB acceptance flow for the selected target instead of assuming another core's configuration.

=== Diagnostic checkpoints
#ds-table("diagnostic-checkpoints",[Minimum observations during bringup and recovery],
  ([Checkpoint],[Capture],[Interpretation]),
  (([Before HP release],[Profile/ARCHINFO, memory readiness, HP requested and actual state.],[Reject an incompatible image or incomplete initialization.]),
   ([Transfer failure],[IP status, actual length, descriptor result and resource owner.],[Differentiate peripheral failure from admission or memory errors.]),
   ([Fabric fault],[SYSCTRL first fault, address/master details and Fabric Monitor snapshot.],[Retain the first attribution before later traffic obscures the cause.]),
   ([Clock/lifecycle fault],[Safe-source selection, clock fault, drain and forced-reset status.],[Do not infer core progress from the requested control bit.]),
   ([Automated completion],[Sticky TEST_STATUS and simulator terminal marker.],[UART startup text alone is not a test verdict.])),
  widths:(0.85fr,1.6fr,1.7fr))

=== Fault recovery order
+ Stop the affected application's new submissions. Preserve error, descriptor and owner state
  before issuing clears, retries or reset requests.
+ Take the monitor snapshot and identify whether the failure occurred before admission,
  during an accepted transaction, in a peripheral engine or during clock/lifecycle control.
+ Quiesce and drain the producer. If the target has been isolated after a timeout, follow its
  documented reset requirement; do not assume clearing the visible flag reconnects it.
+ Mark interrupted buffers/jobs failed. Recover the device and software queues, then recreate
  ownership before resuming traffic with a new transaction identity.
+ Confirm actual recovery status and a small bounded transaction before restoring the full workload.

The first fault is intentionally sticky. Read its related fields as one diagnostic event and
clear only after copying the evidence. Monitor counters describe observed traffic and stalls;
they are not a proof of real-time latency or an exported trace stream. Independent clock-loss,
target-timeout and warm-flush conditions need distinct recovery decisions.
#source-note("docs/hazard3-debug.md",title:"Management JTAG and debug acceptance flow")
#source-note("docs/ip/fabric-monitor.md",title:"Counter snapshots and sticky fault attribution")
#source-note("docs/axi4-interconnect.md",title:"Timeout, isolation and finite-error contract")
#source-note("docs/engineering.md",title:"Simulation verdict and reproducibility rules")
