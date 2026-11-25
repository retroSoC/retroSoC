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
 ([2026-11-21],[v0.2 DRAFT],[Add a smartwatch host diagram and reference pin assignments. The pin assignments follow the reviewed TINY topology.]),
 ([2026-11-22],[v0.2 DRAFT],[Expand the smartwatch diagram and pin assignments to cover storage, radio and service options, sensing, audio, actuation and an alternate camera assembly.]),
 ([2026-11-22],[v0.2 DRAFT],[Show all 49 routed GPIO alternate functions on the QFN64 target pinout with full names and distinct GPIO, ALT0, and ALT1 fills.]),
 ([2026-11-23],[v0.2 DRAFT],[Use power-rail terminology throughout TINY and split QFN64 alternate functions and their directions into distinct ALT0 and ALT1 columns.]),
 ([2026-11-23],[v0.2 DRAFT],[Add a dedicated Overview figure for TINY Gen1 features and reference multimedia applications.]),
 ([2026-11-23],[v0.2 DRAFT],[Standardize TINY in the publication title, text, figures and metadata.]),
 ([2026-11-24],[v0.2 DRAFT],[Rearrange the Figure 2 chip lettering, logo placeholders and Edge AI badge.]),
 ([2026-11-24],[v0.2 DRAFT],[Add the white ECOS and ICsprout marks to Figure 2.]),
 ([2026-11-24],[v0.2 DRAFT],[Reuse the Figure 2 chip artwork on the cover.]),
 ([2026-11-24],[v0.2 DRAFT],[Place the feature highlights and R1 product line illustrations together in the Overview.]),
 ([2026-11-25],[v0.2 DRAFT],[Apply warm-yellow accents to the PRO, MAX and ULTRA chip markings in Figure 3.]),
 ([2026-11-25],[v0.2 DRAFT],[Remove ICsprout from the cover chip and the Figure 3 product line.])),widths:(0.8fr,0.85fr,2.5fr))
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
This is an English v0.2 DRAFT for the reviewed TINY implementation. Rill is the retained prototype brand;
no orderable product, production availability or completed silicon qualification is implied.
Contact: #link("mailto:"+doc.author_email)[#doc.author (#doc.author_email)]. Maintainer: #doc.maintainer.
