#import "../style.typ": *
#import "../system-figures.typ": sequence-diagram
#import "../diagram-packages.typ": cache-boundary-diagram

== Memory Attributes, Cache and DMA Coherency <memory-coherency>
The LP and HP cores do not form a cache-coherent SMP system. Shared memory is visible through
different initiators, and non-CPU masters do not snoop the HP caches. A correct address and a
successful bus response therefore do not prove that a consumer observed the latest data.

=== Address regions and access attributes
The address map and access matrix in the preceding section remain authoritative. The table
below reuses the generated initiator policy. A permitted target can still reject an access
because its pads are inactive, the target is not ready, or an extension range check fails.
#ds-table("memory-attributes",[Initiator attributes derived from the data-plane policy],
  ([Initiator],[Instruction access],[Non-cacheable required],[Readable / writable targets]),
  data.policies.map(p=>(code(p.name),if p.allow_instruction {[Allowed]} else {[Denied]},
    if p.require_noncacheable {[Yes]} else {[No policy requirement]},
    [R: #p.read_targets.join(", ") \ W: #p.write_targets.join(", ")])),
  widths:(1fr,0.7fr,0.9fr,1.8fr))
"No policy requirement" does not configure the CPU MMU or create cacheability for MMIO.
Keep device registers uncached and use their documented access width and side-effect rules.
The HP uncached MMIO path is distinct from its cache data path. Do not map one shared physical
buffer with inconsistent aliases and then rely on a fence to repair the aliasing.

The supplied device tree exposes SDRAM as Linux RAM. SRAM and serial-memory apertures are not
automatically additional Linux allocation pools. XPI is read-only on the AXI64 memory path;
programming uses the command engine. Reserved ranges and inactive QPI/OPI windows must not be
used as scratch space. Physical device capacity must match the controller and board setup.

=== Buffer ownership and alignment
The supplied HP platform metadata declares Zicbom with a 64-byte cache-maintenance block. Round shared
maintenance ranges to full blocks and prevent unrelated owners from sharing a boundary block.
Check address-plus-length overflow before rounding. Device descriptors can impose additional
alignment, byte-count, stride and memory-placement constraints; the DMA TCD is a separate
64-byte descriptor contract, not a universal transfer-alignment rule for every IP.

#figure(cache-boundary-diagram(),kind:image,supplement:[Figure],caption:[Software-declared maintenance blocks around a shared-buffer range.])<cache-maintenance-layout>
Match the platform declaration to the generated HP artifact before deployment; this schematic
does not independently establish physical cache-line geometry or total cache capacity.
#source-note("app/ports/linux/linux/retrosoc_hp.dts",title:"Software-declared cache-maintenance block size")

#ds-table("buffer-ownership",[Shared-buffer responsibilities],
  ([Actor],[Responsibility before handoff],[Responsibility after completion]),
  (([Cached HP producer],[Finish writes; clean required data and descriptors; order publication.],[Do not modify the submitted range while the device owns it.]),
   ([Device / LP producer],[Own the destination exclusively; obey transfer bounds.],[Report completed length/status before transferring ownership.]),
   ([Cached HP consumer],[Prevent dirty cache lines from later overwriting incoming data.],[Observe completion, invalidate the produced range as required, then read it.]),
   ([LP coordinator],[Check owner, idle/blocked acknowledgement and failure status.],[Release or recover the resource only after dependent buffers are accounted for.])),
  widths:(0.9fr,1.6fr,1.6fr))

=== CPU-to-DMA transfer
+ Reserve a complete buffer and descriptor range for one transaction; do not let an interrupt
  handler or another core modify it after submission.
+ Populate the payload and descriptor, including bounds and expected completion fields.
+ On cached HP memory, clean the modified blocks using the supported platform cache operation.
  Apply the required ordering fence before publishing a descriptor or writing the doorbell.
+ Submit through the IP's supported API or driver; preserve the buffer until confirmed
  completion or a completed abort/drain sequence.
+ Inspect status and transferred length. A timeout is not evidence that the master stopped;
  recover or isolate the producer before reusing its memory.

=== DMA-to-CPU transfer
+ Allocate destination blocks that have no unrelated dirty data. Before device ownership,
  perform the platform's required clean/invalidate preparation to prevent later CPU writeback
  from overwriting device results.
+ Submit the transfer and avoid CPU reads or writes to the owned range while it is in flight.
+ Observe device completion using the driver's ordered status/interrupt path and check errors
  and actual length before accessing the payload.
+ Invalidate the produced cache range as required by the HP platform, complete the ordering
  operation, then transfer the buffer to the application.

These are integration sequences, not a new cache HAL. Linux drivers must use the DMA mapping
and synchronization interfaces appropriate to their platform. The existence of Zicbom and a
device-tree block-size property does not establish complete Linux DMA coherency integration.

=== LP-to-HP and HP-to-LP handoff
#figure(sequence-diagram((
  [*Producer owns buffer* \ Complete payload writes],
  [*Prepare visibility* \ Cache maintenance \ Ordering fence],
  [*Publish completion* \ Sequence and ownership],
  [*Consumer observes* \ Validate sequence / bounds],
  [*Prepare CPU view* \ Invalidate where required],
  [*Consume / return* \ Explicit lifetime end])),caption:[Software-managed shared-buffer handoff; arrows express ordering, not cycle timing.])
Use a protocol with an unambiguous sequence, bounded address/length and one current owner.
A mailbox notification does not move the payload or clean the cache. LP should acknowledge
the HP shutdown cache request only after the HP-side software has completed the required
range maintenance. A forced shutdown after a missing acknowledgement can lose dirty data.

Common integration errors are a fence without cache maintenance, invalidating a block that
contains another owner's dirty bytes, polling a cached completion flag, and reusing a buffer
after a timeout while DMA remains active. Preserve the first fault and invalidate the failed
transaction at the protocol level; retries require a new ownership decision.
#source-note("docs/lp-hp-architecture.md",title:"Memory paths and non-coherent ownership contract")
#source-note("docs/ip/resource-controller.md",title:"Cache request and clean acknowledgement")
#source-note("docs/ip/dma.md",title:"DMA descriptors, transfer restrictions and completion")
#source-note("app/ports/linux/linux/retrosoc_hp.dts",title:"Linux RAM and cache-maintenance properties")
