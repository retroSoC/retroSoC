#import "../style.typ": *
#import "../diagrams.typ": flow

= Document Control
#change-start(doc.change_prefix + "document-control", "Publication revision history")
== Revision History
#ds-table("revision",[Document revision history],([Date],[Version],[Change]),(
 ([2026-09-25],[v0.1 DRAFT],[Initial IHP130/four-channel publication; original PDF retained.]),
 ([2026-10-29],[v0.2 DRAFT],[ICS55 main reference; 22 IP chapters; current R2/SPI integration and evidence.]),
 ([2026-10-29],[v0.2 DRAFT],[Same-version Mini hierarchy and engineering-figure alignment.]),
 ([2026-11-10],[v0.2 DRAFT],[Source refresh with PPALite P3, DVP/DMA/RCU contracts and 23 integrated IP chapters.]),
 ([2026-11-11],[v0.2 DRAFT],[Latest reviewed dev source. Uppercase IP suffixes in Contents. Transparent architecture labels and PPALite data-route references.]),
 ([2026-11-14],[v0.2 DRAFT],[Commercial-reference organization, typed data/provenance, QFN64 and board vectors, characteristic models and common maintenance rules. No new hardware qualification.]),
 ([2026-11-17],[v0.2 DRAFT],[Functional IP diagram v2: 23 main and 12 detail views, source-bound units and dimensions, solid fine-line routing and outline audits. Integrate the reviewed d9f27811 snapshot and retain the scope of the dated PPALite P4 acceptance.]),
 ([2026-11-18],[v0.2 DRAFT],[RM0486 comparison across all IP views. Refine signal labels, local route details and crossing limits. Retain the reviewed hardware source and evidence.]),
 ([2026-11-19],[v0.2 DRAFT],[Redraw QFN64 pin numbering, mechanical views, land pattern and assembly layers in the publication gold and gray palette.]),
 ([2026-11-19],[v0.2 DRAFT],[Add carrier tape, reel and Pb-free reflow classification drawings and reference tables.]),
 ([2026-11-20],[v0.2 DRAFT],[Expand the clock tree with the clock source selection, divisors, gate controls and reset distribution.]),
 ([2026-11-20],[v0.2 DRAFT],[Redraw Figure 5 with independent CPU local paths, a grouped fabric matrix and XPI memory and control routes.]),
 ([2026-11-20],[v0.2 DRAFT],[Add a QFN64 target pinout with functional colors and selected GPIO alternate functions.]),
 ([2026-11-20],[v0.2 DRAFT],[Add a 32-bit address map with APB4 window and SRAM bank detail.]),
 ([2026-11-20],[v0.2 DRAFT],[Add a tape and reel box drawing and nominal carton reference dimensions.]),
 (doc.date,[v0.2 DRAFT],[Add a smartwatch host diagram and reference pin assignments. The pin assignments follow the reviewed Tiny topology.])),widths:(0.8fr,0.85fr,2.5fr))
#change-end(doc.change_prefix + "document-control")

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
