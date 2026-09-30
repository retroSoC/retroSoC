#import "../style.typ": *
#change-start("v05-emphasis-reading","Selected body emphasis: reading")
Clock values above describe the selected digital configuration, *not characterized maximum
frequencies*. Larger memory-map apertures describe addressability and *do not imply fitted devices*.

== Reading this datasheet
The architecture and peripheral sections describe PRODUCT mode unless explicitly marked MPW.
Address, LP IRQ, pad and access-matrix tables are generated from the same reviewed inputs used
by the SoC integration. Per-IP references point to detailed contracts or executable sources at
the recorded commit. Features marked *partial*, *prototype* or *TBD* are *not qualified product claims*.
#change-start("v05-refresh-reading", "Link the reading guide to the existing document and evidence map", category: "cross-reference")
Use @document-map to choose the relevant address, programming, boot, diagnostic, board or
verification reference. It also explains the distinction between implementation and evidence status.
#change-end("v05-refresh-reading")

#change-end("v05-emphasis-reading")
