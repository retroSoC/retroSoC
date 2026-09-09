#import "../style.typ": *

== Peripheral Coexistence and Resource Conflicts <resource-conflicts>
This matrix describes shared resources and integration constraints. Hardware exclusions,
software conventions and bandwidth competition require different decisions. Allowed combinations
still require workload-specific validation.

#ds-table("coexistence-matrix",[Shared-resource constraints across IP boundaries],
  ([Shared resource],[Constraint class],[Condition / integration action]),
  data.system_reference.programming.conflicts.map(r=>(r.resource,r.state,r.condition)),
  widths:(1fr,0.95fr,2.2fr))

=== Choosing a coexistence configuration
+ Start from the generated GPIO alternate-function table and memory-pad mode. A single pad
  cannot be driven by two independent peripheral outputs; identify the complete pin group.
+ Allocate software DMA contexts and check endpoint exclusivity. Reserve the entire buffer
  lifetime, not just the interval needed to program the channel.
+ Check the central Resource Controller's owner. Its DMA resource represents the shared engine,
  not an independent LP/HP owner bit for each software channel convention.
+ Account for gateway sharing, memory target credits and conservative drain/block behavior.
  A second controller can be electrically independent yet share the same data admission path.
+ Establish clocks, stream-switch selection and interrupt ownership before enabling producers.
+ Validate the intended combination with actual input/output traffic, completion and error handling.

For example, DVP capture and an I2S convenience DMA client cannot both assume exclusive use
of bulk channel 3. Explicitly allocating a different context can address a software convention,
but it does not change a shared endpoint, stream-switch mode or target bandwidth limit. QPI/OPI
pad exclusion cannot be solved by choosing another DMA channel.

=== Failure handling and evidence
Reject a conflicting request without overwriting active state. Capture the context, owner,
pad mode and fault. Complete recovery before reassignment. An admission error is not permission
to widen an ACL; simultaneous-workload qualification remains separate.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("rtl/mini/integration/soc_topology.json",title:"Pin and initiator policy") ·
  #source("rtl/mini/top/soc_data_plane.sv",title:"Gateway/lifecycle wiring") ·
  #source("docs/ip/resource-controller.md",title:"Ownership and drain contract")
]
