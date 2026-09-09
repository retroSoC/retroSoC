#import "../style.typ": *

== Interface Standards and Supported Subsets <interface-subsets>
An interface name is not a claim that every mode in a related standard is implemented. This
matrix summarizes the source-level subset, instance routing and software boundary of the
reviewed snapshot. The individual IP contract and actual register/capability checks remain
authoritative. No interface compliance certificate is attached to this matrix.

#ds-table("interface-subsets",[Digital interface roles, supported subsets and exclusions],
  ([Interface / role],[Source-level subset],[Excluded or qualified scope]),
  data.system_reference.product_details.interfaces.map(r=>([#r.title \ #r.role],r.modes,r.excluded)),
  widths:(0.9fr,1.65fr,1.6fr))

#change-start("interface-format-links","Interface overview links to complete data-format diagrams",category:"cross-reference")
Source-bound data layouts:
#data.system_reference.product_details.formats.map(r=>link(label("binary-"+r.id),r.title)).join([; ]).
Use the instance's protocol and availability qualifications together with its format diagram.
#change-end("interface-format-links")

=== Software and verification boundary
Hardware mode support, a callable HAL and a qualified protocol/system result are separate
columns. A driver may implement only a subset of the digital engine. An external PHY, device,
clock, pin route or software stack may also be required before a mode is usable on a board.

#ds-table("interface-software-scope",[Software and verification scope for interface selection],
  ([Interface],[Software boundary],[Evidence]),
  data.system_reference.product_details.interfaces.map(r=>(r.title,r.software,r.evidence)),
  widths:(0.8fr,2.15fr,1.2fr))

=== Selecting and confirming a mode
+ Identify the exact instance, protocol role and requested mode before allocating resources.
+ Check identity/capability, published exclusions and board prerequisites.
+ Match software transactions and data layout to the supported subset; an SDK enumeration or
  descriptor field is not proof of hardware support.
+ Check transport availability separately from format support. JPEG admission and APU
  production-job gates remain binding.
+ Verify a bounded normal transfer and its error/recovery case on the selected platform.

Calculations and model/test availability do not establish compliance. A board-level validation
claim must identify the actual device, mode, configuration and matching result.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("publications/datasheets/system-reference.json",title:"Subset evidence index") ·
  #source("publications/datasheets/features.json",title:"Per-IP feature summaries")
]
