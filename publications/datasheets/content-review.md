# Mini datasheet content review - 2026-09-22

The v0.5 DRAFT targets dev commit
`ca4b06d30456599a2d3fd676d832f8d4dd2f78af`. The main reference remains
IHP130 PRODUCT / 32 KiB SRAM; the APU P7 acceptance profile is described separately.
This is a publication refresh, not a hardware change or a new qualification campaign.

The [STM32N6 datasheet](https://www.st.com/resource/en/datasheet/dm01125716.pdf),
[ESP32-P4 datasheet](https://documentation.espressif.com/esp32-p4_datasheet_en.html)
and [RP2350 datasheet](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf)
inform the organization of accelerator functions, configuration boundaries,
programming references and revision/errata material. Their features, numerical
ratings and certifications are not transferred to retroSoC.

| Area | Implementation and document assessment | v0.5 disposition | Recommendation |
| --- | --- | --- | --- |
| NPU | Software-launchable eight-operator computation, private DMA/SRAM, compiler and HAL exist. Publication data mixed shell-only and enabled descriptions and lacked a chapter. | Added the independent NPU chapter, source-derived geometry, operator/job/error limits, register/HAL reference, circuit, storage, descriptor/parameter layouts and normal/abort waveforms. | Use the static supported graph subset and exact numeric profile. Attach matching full-corpus and physical reports before claiming speedup, accuracy or timing closure. |
| APU formats and base programming | APUMC V1/V2, 4096-word current store, seven classes/62 opcodes, APUM model and 128-byte job format remain correct. | Covered; retained. Default and P7 capability/digest identities are now explicit. | Preserve format compatibility and distinguish the fixed APUM engine from NPU deployment. MP3 remains unsupported. |
| APU configuration and acceptance | Default KWS is off; the P7 acceptance profile enables it and publishes digest 0xF5005D7C. LP/HP acceptance and quiesced-loader progress are implemented. | Updated loader/ACL/ownership/cache and bare-metal HP workflow. No Linux ASoC support is claimed. | A passing smoke wrapper or missing-data early return is not the full accuracy or 60-second-per-scenario release campaign. Supply workload/clock/result artifacts. |
| GA2D | Existing FILL/COPY/CONVERT/opaque BLEND/A8 programming coverage is adequate. P6 extends tests, workload matrices and dated evidence. | Retained functional ABI; updated performance-method and evidence boundaries, including schema 3. | The historical composition target and 48 MHz slow-corner timing were not met. Full-product closure and current-source measurements still need matching artifacts. |
| Fabric, memory conversion and resources | Ten masters/resources, NPU master/resource9 and Resource ABI1.2 are implemented. The 64-to-32 converter supports fragmented long bursts. | Updated prose, matrices and source-bound circuits, NPU IRQ/fault/cache/lifecycle references, and corrected the overview NPU HP background. | Preserve master/target credit, permission, source-ID and boundary rules. An admitted burst is not a throughput guarantee. |
| Address/register/IRQ/pad inventories | Existing generation and register-field mechanisms are adequate for their declared scope. | Covered; retained and extended to the independently rendered NPU chapter. No new NPU pins are implied. | Keep chapter, catalog, feature, register, diagram and API coverage synchronized when advancing the source snapshot. |
| Startup, cache handoff and recovery | Existing LP/HP startup, boot image, timeout/partial-transfer, ownership and recovery references are substantial and remain applicable. | Covered; retained with NPU/APU and current diagnostic-stage additions. Repeated result codes remain stage-qualified. | A HAL, DT node or freestanding HP payload is not a native Linux driver. Complete cache and terminal/drain handoff before buffer reuse. |
| Interface, format and memory budgeting | Existing mode exclusions, byte packing, pitches, buffer accounting and interoperability guidance are adequate. | Covered; retained with NPU INT8 preprocessing and CPU-finalizer boundaries. | Check actual byte order, zero points, allocation/stride and producer/consumer lifetimes; shared memory does not convert formats. |
| Electrical, package, thermal, reliability and ordering | Chapter structure and evidence requirements are complete; measured product values are not. | Covered structure; evidence missing. Existing placeholders are retained instead of duplicated. | Supply process/package/corner/board/instrument/workload evidence. Do not substitute target clocks, analytic peaks or commercial-device limits. |
| Release evidence | Current CI status, historical narratives and exact-profile IP reports are different evidence classes. | Updated commit-bound CI with status and nullable conclusion; dated GA2D/NPU narratives remain historical. | Refresh CI before delivery and retain pending/failed/skipped states. Missing original reports cannot be recreated from prose as current passes. |

## Source/specification discrepancies

- `docs/ip/apu.md` describes sixteen KWS technology-macro banks, while
  `apu_kws_sram_client.sv` still uses inferred storage with combinational reads.
  The datasheet retains the implementation's logical-versus-physical distinction.
  Reconcile the hardware specification or implement/verify the macro change in a
  separate hardware task.
- Older NPU phase comments and some source-linked descriptions predate the enabled
  scheduler and capability returns. Publication facts follow the instantiated
  parameters, register logic and actual compute/DMA path. Comment cleanup is
  recommended separately; no RTL edits are included here.
- The dated GA2D and NPU verification narratives refer to reports not supplied
  for this publication's exact source revision. They are indexed as historical
  records, without promoting current per-IP verification or RTL maturity.

The [chapter review](chapter-review.md) covers all **109 frozen entries / 42 IP
chapters**, classifies each disposition and recommendation, and binds final page
numbers to the delivered PDF. Document completeness is not protocol compliance,
physical closure or silicon qualification. The independent unnumbered closing
page remains outside that chapter contract.
