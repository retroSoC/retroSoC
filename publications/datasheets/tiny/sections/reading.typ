#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow
#import "../waveforms.typ": timing

== Reading this datasheet
Addresses are byte addresses; register offsets are relative to their named instance/group. *Source reviewed*, *test available*,
*executed result* and *physical qualification* are separate states. Source links target the reviewed commit or locked managed
input. Diagrams describe digital structure and ordering; they do not specify measured latency or board timing.

Use @tiny-addresses for memory windows, @tiny-irq for interrupt numbering, @tiny-register-index for address-first register
lookup, @tiny-boot for startup, @tiny-diagnostics for terminal results and @tiny-evidence for verification boundaries.
The document uses the approved Mini visual language; all product facts and source inventories here belong to Tiny.


#ds-table("reading-map",[Finding the relevant contract],([Reader task],[Start here]),(
 ([Select a usable profile],[@tiny-configuration]),([Understand CPU and memory paths],[@tiny-core]),
 ([Choose shared pins and channels],[@tiny-conflicts]),([Program an IP],[@tiny-peripherals]),
 ([Locate a register address],[@tiny-register-index]),([Interpret a fault or test verdict],[@tiny-fault-reference]),
 ([Check buffers and memory capacity],[@tiny-memory-budget]),([Check terms and evidence status],[@tiny-document-map])),widths:(1.7fr,2.3fr))
