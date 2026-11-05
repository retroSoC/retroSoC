# Mini datasheet content review - v0.5 OpenC906 refresh, 2026-10-22

This English Rill Mini Gen2/Gen2+ refresh retains **v0.5 DRAFT**, 42 IP chapters,
109 frozen entries and stable chapter/IP anchors. The reviewed dev source is
`9ab05c6404c02b5f2c927539b5c681b46f778b9f`. The implementation-start source was
`3062aec09ba22bd0eaa75600a85fd45eab99a51a`; handoff review found one later commit
that changes only the Mini smoke wall-time budget and its tests. Those two files
were reviewed before the fast-forward and identity update. Earlier CI failures
remain explicitly identified with their original commit and observation time.
The main reference remains IHP130 PRODUCT, 32 KiB SRAM
and no PLL. HP/APU acceptance and MPW compatibility remain separately scoped.
Publication date uses the client's calendar date; source and CI observations use UTC.

The retained **798-page** baseline has PDF SHA-256
`49c3e20e7568e20baaa75f104e71b7e526f33aa7231bed03dbcde5893712da93`, bound to
`95c243b7095547f2ada5166a1cc8e8a3a9345fed`. Current markers use
`v05-c906-20261022-`. Earlier source, branding, field-audit and layout corrections
remain part of this delivery; their implementation and historical verdicts are not
reclassified as new work. All 40 previously staged publication files were backed
up before synchronizing dev and reconciled with its OpenC906 publication edits.

## Commercial references and bounded adoption

Official source organization was reviewed on **2026-10-22**. The ST and Espressif
current official documents were checked directly; the RP2350 official indexed
release-history and hardware-revision sections were rechecked. No vendor prose,
numerical rating, package drawing or qualification is copied into Mini.

| Reference | Identity / adopted sections | Concrete use in this refresh |
| --- | --- | --- |
| [STM32N6](https://www.st.com/resource/en/datasheet/dm01125716.pdf) | DS14791 Rev 11, 2026-09-28; configuration/feature tables, pin constraints, electrical conditions | Separate the selected product configuration, optional process macro paths and missing physical limits. |
| [ESP32-P4](https://documentation.espressif.com/esp32-p4_datasheet_en.html) | Series v0.7; series comparison, boot configurations, system/memory/interrupt descriptions and document versioning | Preserve the functional grouping and task navigator; put source/ID translations and boot prerequisites beside their usage. |
| [RP2350](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf) | Documentation release 2025-07-29; version history and Appendices C, E and H | Keep core/hardware changes, remaining limitations, corrected implementation defects and same-version document revisions distinct. |

## Implementation and document assessment

Implementation state, document completeness and executed validation are separate.
**Covered and retained** means adequate within the stated scope, not hardware
qualification. Every one of the 109 entries has its own source-grounded assessment,
verification boundary and maintenance recommendation in the final chapter review.

| Area | Implementation / documentation assessment | Update or concrete recommendation |
| --- | --- | --- |
| Structure, cover and navigation | Covered and retained: complete reference-manual form, 42 IP chapters, 109 entries. The upstream Overview correctly has 43 integrated labels. | Preserve typography, logo reserve, contact, status marks and anchors. Update navigation and page records after layout; IP chapters and Overview labels are different inventories. |
| Fixed HP processor | Implemented upstream; processor basics already updated. The previous delivered PDF and its review still describe VexiiRiscv. | Reconcile OpenC906 RV64GC/Sv39, 32 KiB I/D caches, eight PMP regions and fixed hart 1. The Mini HP_CONFIG selector is retired; VexiiRiscv remains a Std asset. |
| HP data and control paths | Implemented upstream; the single AXI128 source, serializing 128-to-64 converter, MMIO demux and master-0 data route are present. | Distinguish active hp_mem from idle slot 1, retained numeric crossbar credits and the converter's one-read/one-write bound. Preserve the LP control route and existing clock boundaries. |
| Address width | Source limitation: the core drives 40 bits but the wrapper forwards only bits 31:0. | State the 32-bit physical mapping rule and lack of a separate high-bit rejection path. Sv39 is not a 40-bit SoC aperture. |
| HP CLINT/PLIC | Upstream integration chapters already adequate in principle; old standalone register and review assumptions are obsolete. | Keep chapter anchors, describe internal decode, time CSR, the 0x0C000000 CLINT and 0x08000000 PLIC. Remove old APB/register-index entries; publish both SoC sources and source+16 software IDs. |
| Startup and cache maintenance | C906 startup, OpenSBI and payload changes implemented; existing V2 layout and Linux mailbox details are retained. | Document MCOR before MHCR, MAEE clear, parking both timer compares, PLIC initialization and T-Head cache operations. Rebuild old-core images; preserve exact workload terminal handshakes. |
| HP JTAG debug | Implemented optional pre-release selection; upstream parser accepts the conditional. | Check the branch body, failure result 20 and ordering before release. Normal builds retain management selection; debug access does not imply a connected debug SBA master. |
| SRAM and ICG | IHP130/ICS55/GF180 SRAM paths and four process ICG paths implemented. SKY130 C906 SRAM remains behavioral. | Publish process/guard/model/fallback matrix and preserve the behavioral default. Verify all 14 controlled upstream override targets and record selected source hashes. Functional macro simulation is not physical qualification. |
| AW/W write-order adaptation | Upstream controlled BIU override corrects the documented downstream attribution wedge. | Describe the local integration requirement, not a universal AXI rule. Keep the separate source-readiness-dependent guard timeout gap explicit. |
| Linux and RT-Thread evidence | Repository narratives record C906 smoke, RT-Thread and later Linux userspace completion after earlier bounded frontiers. No matching raw current-commit hardware report is attached here. | Preserve the progression and original variants; do not label the earlier wedge as the current frontier or transfer VexiiRiscv passes to C906. No new full-product run is claimed. |
| Crypto initialization and lifecycle | Covered and retained from the 798-page delivery: CRYC1, six private SRAM banks, READY admission, erasure and error recovery. | Retain initialization/key/START order, IRQ_TEST exclusion, running-PCLK and DMA drain/scrub prerequisites. No new cryptographic qualification. |
| DMA, SDIO and cross-IP routing | Prior Mini-selected channels, requests, sessions and IRQ corrections retained. HP source interpretation changed with the core. | Preserve eight AXI32 channels, 16-beat implementation and the discovery-field truncation limitation. Fix SDIO/SYSCTRL old master-0/1 prose; keep Crypto LP bit 23 and NPU master 9/source 12/PLIC ID 28. |
| Register extraction and command semantics | Covered and retained: prior field-width, CONFIG versus CONFIG_LOCK, read/write-view and command-pulse corrections. | Keep source-bound annotations and reject writable all-reserved records. Preserve RTC opcodes, PWM status-bit overlap, SDIO/USB2 asymmetric readback, APU tied-zero counters and the USB2 debug-only BIST request. |
| APU/NPU/JPEG/GA2D | Existing IP functionality and detailed reference remain integrated; C906 payload cache instructions changed. | Retain P5/P9 separation, eight NPU operators/eight-beat DMA, JPEG table-command limitations and scoped GA2D evidence. Recheck NPU-P6 workload/GA2D ownership discrepancy before a complete P6 claim. |
| GPIO, serial, audio, capture and memory | Existing Mini descriptions are adequate after instance/source checks. Tiny SPI-P4 display work is separate. | Keep Mini pin mux, channel ownership, static clock-reporting versus actual clocks, external-device requirements and QPI/OPI exclusion explicit. |
| Physical, package, power and performance | Document structure is adequate; release measurements and physical signoff remain missing. | Require process/corner/board/workload/instrument evidence for numerical ratings. Configured clocks and analytical bandwidth are not measured operating points. |
| CI and local tests | Current-commit observation is refreshed separately from local results. | Preserve pending/failed/skipped/unrun states and exact raw records. Prior test totals remain historical; publication checks do not upgrade per-IP evidence. |

## Norms and follow-up boundaries

The [layout/content standard](style.md) now specifies whole-book core-migration
consistency, internal versus fabric decode, source/interrupt-ID namespaces,
address reduction, locked core/override integrity, technology selection and
non-transferable historical evidence. The [publication guide](../README.md)
keeps the existing build interface and directs the same-version comparison to
the retained 798-page artifact.

Full-page color/grayscale review, source/dependency checks, test results, exact
commands, PDF hashes and changed-page ranges belong to the final validation
record. Earlier test failures, integrity diagnoses and intermediate checks are
retained with their actual outcomes. No RTL, SDK public API, hardware profile,
warning baseline, dependency version, CI rule or Tiny publication is changed by
this publication work. Engineering discrepancies are documented, not repaired.
