#import "../style.typ": *
#import "../figures.typ": *

= Appendix: MPW Compatibility <mpw>
== SoC Template
=== Architecture
The separate MPW configuration retains selectable user-core and user-IP mechanisms. It is
not the fixed PRODUCT topology and does not define a Gen2/Gen2+ derivative mapping. Hazard3
remains the management core. The selected C0-C3 interface uses RIBP and an AXI4 adapter.

#figure(mpw-diagram(), caption:[MPW compatibility profile: one selectable user core and legacy user-IP selection.])<mpw-figure>

#ds-table("mpw-cores", [Current MPW core slots],
  ([Slot], [Design ID], [Module], [Reset]),
  data.mpw.core_targets.map(c=>(str(c.slot),code(c.design_id),code(c.module),c.reset)),
  widths:(0.4fr,1.5fr,0.8fr,0.7fr),
)
The current map contains kianV RV32I, SERV, FemtoRV32 and DarkRISCV. PicoRV32 is not a selected
management or MPW core in this snapshot. Historical diagrams with PicoRV32 or arbitrary core
counts are retained only as original media assets, not as current product figures.

=== User Guide <user-ip>
#ip("user-ip")
#ds-table("mpw-ip", [Selectable MPW user-IP slots],
  ([Slot], [Design ID], [Module]),
  data.mpw.ip_targets.map(i=>(str(i.slot),code(i.design_id),code(i.module))),
  widths:(0.5fr,1.5fr,1fr),
)
Use the committed MPW profile and locked design manifest. Firmware must obey reset, selection
and GPIO ownership rules before handoff. PRODUCT uses fixed extension slots and reports no
selectable user cores or user IPs.
#source-note("rtl/mini/integration/README.md", title:"Extension manifests and generation boundary")

#include "../ips/mpw-timer.typ"
#include "../ips/mpw-gpio.typ"

= Appendix: Product Direction
== Product Series
#ds-table("family", [Family positioning - roadmap context],
  ([Series], [Intended role], [Status in this datasheet]),
  (([Tiny], [MCU and connectivity endpoint], [Roadmap context]),
   ([Mini], [Asymmetric RV32 embedded control and lightweight Linux], [Current documented integration]),
   ([Std], [Graphical RV32 Linux edge system], [Roadmap context]),
   ([Pro], [Higher-performance RV64 graphical system], [Roadmap context])),
  widths:(0.5fr,1.8fr,1.2fr),
)
The product ladder expresses intended positioning. It does not advertise implemented Tiny,
Std or Pro profiles, a Mini NPU, a graphics accelerator or measured performance for a future
device. Only the current Mini snapshot is specified here.
#source-note("docs/soc-family-positioning.md", title:"Family roadmap and scope")

== Roadmap
#placeholder[Reviewed release and silicon roadmap]
#tbd[Release dates, derivative differences, process/package selections and future accelerator
milestones have not been established as product commitments in this datasheet.]

= Technical Report
#include "release-verification.typ"

== Shuttle and Qualification Evidence
The previous draft's dated first-shuttle heading is replaced by an evidence placeholder.
No fabricated die image, tapeout badge, packaged-part photograph or silicon performance
number is used to imply completion.
#placeholder[Silicon / package photograph and measurement setup]
#ds-table("evidence", [Evidence required for a characterized release],
  ([Evidence], [Required context], [State]),
  (([Silicon and package identification], [Lot, revision, PDK and outline], [TBD]),
   ([Electrical measurements], [Boards, corners, instruments, test conditions], [TBD]),
   ([Frequency / power / area], [Exact configuration and reproducible reports], [TBD]),
   ([Interface qualification], [External devices, coverage and timing], [TBD])),
  widths:(1.15fr,1.8fr,0.4fr),
)

#include "performance-reference.typ"

#include "usage-appendices.typ"

#include "register-index.typ"
#include "fault-reference.typ"

= Document Control
== Revision History
#change-start("revision-history", "Document revision history")
#ds-table("revisions", [Document revision history],
  ([Date], [Version], [Change], [Author]),
  (([2025-09-28],[0.1],[Create document],[Yuchi Miao]),
   ([2025-12-02],[0.2],[Initial draft],[Yuchi Miao]),
   ([2026-02-15],[0.3],[Initial release (historical document entry)],[Yuchi Miao]),
   ([2026-09-06],[0.4 DRAFT],[Expand IP/system-use, programming, processor/reset/interface and maintenance references; add register/code indexes and release-evidence summary. Retain the reviewed snapshot and gray/gold layout.],[Yuchi Miao / ECOS Team])),
  widths:(0.8fr,0.65fr,1.8fr,1fr),
)
The retained historical release entry does not establish silicon availability or qualify
the electrical placeholders in this revision.
#change-end("revision-history")

== Sources and Reproducibility <publication-provenance>
Hardware snapshot: #code(doc.source_revision).
The source revision, configuration files, media commit, font/package hashes and PDF digest
are recorded in the build manifest. The datasheet is built manually with Typst 0.15.1 and
CeTZ 0.5.2. Main-repository sources and assets in the separate media repository are maintained
independently, with exact asset commits locked by the main repository.

Publication-only support, limitation and register-annotation metadata can postdate the
reviewed hardware commit. Their source links lead to this provenance section; obtain the
matching publication sources and build manifest with this PDF. The manifest records hashes
for the system-reference index, publication files and all declared engineering dependencies.
It does not claim that newly authored publication files existed at the hardware commit.

The generated address, IRQ, GPIO, pad and bus-permission data are derived from canonical
inputs. Explanatory prose is reviewed against RTL and software contracts; stale descriptive
documents do not override executable integration.

== License
retroSoC project material is distributed under Mulan Permissive Software License, Version 2.
Third-party IP, fonts and Typst packages retain their own licenses. The media repository
contains the original illustrations, font files and associated license texts.
#source-note("LICENSE", title:"retroSoC Mulan PSL v2 license")

== Document Status and Contact
This draft describes an evolving implementation. Numerical electrical ratings, ordering data,
package dimensions and unsupported features remain explicitly unfilled until reviewed evidence
is available. Specifications can change with later source revisions.

Author: #link("mailto:miaoyuchi@ict.ac.cn")[Yuchi Miao] \
Maintainer: #doc.maintainer \
Project: #link("https://github.com/retroSoC/retroSoC")[retroSoC source repository]
