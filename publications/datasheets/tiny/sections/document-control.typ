#import "../style.typ": *
#import "../diagrams.typ": flow

= Document Control
== Revision History
#ds-table("revision",[Document revision history],([Date],[Version],[Change]),(
 ([2026-09-25],[v0.1 DRAFT],[Initial IHP130/four-channel publication; original PDF retained.]),
 ([2026-10-29],[v0.2 DRAFT],[ICS55 main reference; 22 IP chapters; current R2/SPI integration and evidence.]),
 ([2026-10-29],[v0.2 DRAFT],[Same-version Mini hierarchy and engineering-figure alignment.]),
 ([2026-11-10],[v0.2 DRAFT],[Source refresh with PPALite P3, DVP/DMA/RCU contracts and 23 integrated IP chapters.]),
 (doc.date,[v0.2 DRAFT],[Latest reviewed dev source. Uppercase IP suffixes in Contents. Transparent architecture labels and PPALite data-route references.])),widths:(0.8fr,0.85fr,2.5fr))

== Sources and Reproducibility <publication-provenance>
Hardware/software snapshot: #code(doc.source_revision). This document's source manifest records the exact technical files,
publication files, managed revisions and fonts/packages used for the build. The PDF digest, chapter review and actual
validation record accompany the output; the document date is not a hardware measurement date.

The publication uses locked Typst 0.15.1, existing Inter/Fira Code/Noto fonts and the project's managed vector/waveform packages.
The prototype brand is Rill; this identity does not establish an orderable or qualified silicon product.



== License
The project retains Mulan PSL v2 and the respective component/font licenses. Read the repository LICENSE
and locked third-party notices for the full terms; the publication does not change their scope.
#source-note("LICENSE",title:"Project license")

== Document Status and Contact
This is an English v0.2 DRAFT for the reviewed Tiny implementation. Rill is the retained prototype brand;
no orderable product, production availability or completed silicon qualification is implied.
Contact: #link("mailto:"+doc.author_email)[#doc.author (#doc.author_email)]. Maintainer: #doc.maintainer.
