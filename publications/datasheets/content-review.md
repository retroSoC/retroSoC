# Mini datasheet content review - 2026-09-17

This v0.4 DRAFT review targets dev commit
`2a497ecef0b084c02f77ddfb1e94fb0197e14b02`, with the unchanged IHP130 PRODUCT /
32 KiB SRAM reference profile. It reviews document coverage and source-level
implementation; it is not a hardware release or silicon qualification.

Commercial references are the [ESP32-P4 datasheet](https://documentation.espressif.com/esp32-p4_datasheet_en.html),
[STM32N6 datasheet](https://www.st.com/resource/en/datasheet/dm01125716.pdf), and
[RP2350 datasheet](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf).
They inform organization of configurations, functional subsets, programming
boundaries, and revision/qualification information. Their features, numerical
ratings and certifications are not transferred to retroSoC.

| Content area | Implementation / document assessment | This refresh | Recommendation |
| --- | --- | --- | --- |
| Address, register, IRQ and pin inventories | Existing generation, coverage and register-field mechanisms are complete for their declared scope. New GA2D and LP IRQ allocations need consistent presentation. | Reuse existing annotations; update the 41-IP inventory, active GA2D window and LP vector / ordinal / PLIC mappings. | Keep inventories source-derived and review interface changes when advancing the snapshot. |
| GA2D | P5 FILL, COPY, CONVERT, opaque BLEND, A8 mask and constrained in-place composition are implemented. A hidden register block was not a complete independent reference. | Add the standalone chapter, HAL sequence, limitations, circuit, packing, buffer/FIFO and timing figures. | Complete separately specified Phase 6 system/contention/performance and physical evidence before broader qualification. |
| APU codec / APUMC | WAV/FLAC code and bounded P5 image exist. V1/V2 limits differ; blanket codec-disabled statements are obsolete. | Derive current image capacity through the checked-in assembler; retain seven classes, 62 opcodes and the 128-byte job descriptor. | Attach full codec-corpus and sustained-path results for the exact source/profile. |
| APU MP3 / KWS | MP3 remains a trap entry. KWS RTL, model loader and HAL exist but the default gate is off and capability bit 6 is clear. | Explain gating, the new input register, fixed model ABI, conditional RX/flush and logical-versus-physical storage. | Keep MP3 unsupported and KWS in development until complete PCM, layer, concurrent-audio and lifecycle evidence is available. |
| I2S | Basic sample formats, dividers and 128-word FIFOs were already covered correctly. | Add exported RX-flush status and gated APU receive integration. | Retain the base reference; qualify external devices and clocks independently. |
| Fabric / JPEG / ownership | Nine masters, seven-bit IDs and bounded JPEG/GA2D credits are implemented. Older paragraphs still described eight masters or blocked JPEG admission. | Synchronize figures, matrices, resource and fault descriptions; separate admission from workload qualification. | Measure contention and recovery; permissions and credits are not throughput guarantees. |
| Software, boot and diagnostics | Startup, ownership, error and API structure is already substantial. CSR-enabled LP external IRQ and GA2D scenarios require refresh. | Document Xh3irq dispatch, no-CSR stubs, owner-routed GA2D and current benchmark counters. | Preserve profile/CRT distinctions and narrow firmware pass scopes. |
| Electrical, package, thermal, ordering and performance | Chapter structure and evidence requirements are complete; numerical characterization is not. | Keep missing measurements unfilled and distinguish configuration, static bounds and measured results. | Supply board/package/PDK/corner/instrument/workload evidence rather than duplicate placeholder chapters. |
| Verification and readiness | Current dev CI is mixed, and readiness remains prototype. Per-IP reports are separate. | Record commit-bound outcomes, including quality-format failure, skipped tests and SKY130 failure. | Resolve failures and attach scoped artifacts before broader claims; behavioral passes are not physical signoff. |

The build emits the complete 108-entry structural inventory and diagram coverage.
The [108-entry chapter review](chapter-review.md) maps each entry to its final page, implementation
state, document disposition, source pointers and next recommendation. Unchanged
chapters remain classified as covered rather than expanded for length.

The snapshot is stored jointly in [mini.json](mini.json) and
[system-reference.json](system-reference.json). Layout and evidence rules are in
[style.md](style.md); the approved structural addition is frozen in
[structure-contract.json](structure-contract.json).

The independent closing page is an unnumbered publication element outside the
108-entry chapter contract. It adds the empty logo reserve and project notice;
it does not change implementation coverage, capability or qualification status.
