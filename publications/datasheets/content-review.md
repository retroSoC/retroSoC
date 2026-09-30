# Mini datasheet content review - v0.5 presentation revision

## Current presentation revision

This round retains v0.5 DRAFT / 2026-09-22 and reviewed source
`c3de7c602a7ca0f0f9ade9d3ffb59339bc34fb8b`. Its comparison baseline is the
779-page PDF with SHA-256
`25257e5243e945401c8a214d4043819cf802a7fa2d22b04d83b513ce9075647b`.
The cover contact becomes `Yuchi Miao(miaoyuchi@ict.ac.cn)` with a mail link;
PDF author metadata remains the name. Functional uses an explicitly partial,
vertical left-half pale-gold mark. This is not a new full-verification claim.

All frozen chapters are reviewed for selective emphasis: short capability and
parameter phrases, programming prerequisites/order, limits, failure conditions
and evidence boundaries. The IP renderer preserves explicit strong spans rather
than deleting their markers. Code, addresses, register identifiers and diagram
labels keep their separate typography rules. Hardware text and values are retained.
The current dev increment changes only
Docker/Nix runtime libraries, tool-archive access modes, environment stamp
permissions, their guide and host tests; RTL, SDK and committed hardware profiles
are unchanged. The new revision-history row records this presentation work.

This round uses only `v05-emphasis-` content markers plus shared navigation
markers. Earlier source-refresh corrections below remain historical context.
Regenerated chapter-review and change-page records identify final page movement
without describing NPU or other existing IP as newly added.
Build directly in the current dev checkout and retain the exact reviewed SHA
and fresh CI observation. The temporary independent snapshot directory was
removed at the user's request; existing shared caches and earlier PDF artifacts
remain. Strict source checks remain enabled.

## Prior technical refresh and retained commercial comparison

The preceding technical refresh retained **v0.5 DRAFT / 2026-09-22** and reviewed commit
`b209ccedfe6f9c33078ef082a4d31580d4d1a845`. The main reference remains
IHP130 PRODUCT / 32 KiB SRAM; the APU P9 acceptance profile is separate.
This is a publication refresh, not a hardware change or a new qualification campaign.

That technical refresh compared against the 777-page baseline bound to
`ca4b06d30456599a2d3fd676d832f8d4dd2f78af`, with SHA-256
`c8e18ba1a973ed409bf2fb3c2197cea427097c1b57760b04fb1e1c97a7ea26a6`.
That round used the `v05-refresh-` prefix for its active change markers. NPU's
existing chapter and earlier diagram work were retained, not newly added.
Actual final page ranges belong to the delivered change report; pagination alone
does not turn retained material into a content change.

## Commercial references and bounded use

The official sources below were checked on **2026-09-22**. The adopted ideas concern
organization and clarity; their features, numerical ratings, certifications and
release-status policies are not retroSoC specifications.

| Official reference | Document identity and release | Relevant organization | Disposition for Mini |
| --- | --- | --- | --- |
| [STM32N6 datasheet](https://www.st.com/resource/en/datasheet/dm01125716.pdf) | DS14791 Rev 10, 2026-08-04 | Introduction, device configuration tables, functional overview, electrical conditions and revision history; separate reference-manual and errata destinations. | Retain Mini's configuration/functional/electrical separation and source links. Do not copy device limits, part numbers or qualification claims. |
| [ESP32-P4 datasheet](https://documentation.espressif.com/esp32-p4_datasheet_en.html) | ESP32-P4 Series Datasheet v0.7, 2026-07-14 | Series/chip revision, peripheral pin assignment, document status definitions and related-document navigation. | Retain profile-specific availability and pad constraints. Improve links in the existing document map; Mini's DRAFT status remains independently defined. |
| [RP2350 datasheet](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf) | RP2350 Datasheet, build-date 2025-07-29, build-version `d126e9e-clean` | Integrated programming reference; separate hardware and documentation revision histories; errata identify affected revisions, workaround and fix status. | Retain the full Mini reference and distinguish publication corrections, implementation limitations and missing evidence. Do not describe a documented workaround or wording correction as a hardware fix. |

## Current implementation and document assessment

| Area | Implementation and document assessment | This refresh | Specific recommendation |
| --- | --- | --- | --- |
| NPU | The existing chapter adequately covers the software-launchable eight-operator engine, private DMA/SRAM, compiler/HAL, descriptor/parameter layouts and normal/abort behavior. | Already covered; retain the chapter, geometry, static graph subset and numeric profile. No new NPU capability is introduced by this refresh. | Attach matching full-corpus and physical reports before claiming speedup, accuracy or timing closure. Distinguish the deployed burst limit from the reusable DMA default. |
| APU formats and base programming | APUMC V1/V2, 4096-word current store, seven classes/62 opcodes, APUM model and 128-byte job format are already covered. | Already covered; retain the formats, register/HAL reference and default/P7 identity distinction. | Preserve format compatibility and separate the fixed APUM engine from NPU deployment. MP3 remains unsupported. |
| APU summary, configuration and acceptance | Default KWS is off; the P9 acceptance profile enables KWS and APUC loading with digest `0x63E96066`. The checked-in WAV/FLAC image is distinct from full production-job qualification. | Correct summary/body/table consistency while retaining the detailed formats and bare-metal acceptance reference. No native Linux ASoC support is claimed. | A smoke wrapper or missing-data early return is not the full accuracy or 60-second-per-scenario campaign. Keep actual workload, clock, source and result artifacts with any pass. |
| GA2D | Existing FILL/COPY/CONVERT/opaque BLEND/A8 programming coverage and P6 workload/evidence boundaries are adequate. | Already covered; retain functional ABI and schema-3 performance-method descriptions. | The dated composition target and 48 MHz slow-corner timing were not met. Full-product closure and current-source measurements still require matching artifacts. |
| Fabric, memory conversion and resources | Ten masters/resources, NPU master/resource 9, Resource ABI 1.2 and fragmented 64-to-32 long-burst conversion are already described. | Already covered; retain source-bound topology, matrices, circuits, credits and lifecycle references. | Preserve permission, source-ID and boundary rules. Burst admission is not a throughput guarantee. |
| Address/register/IRQ/pad inventories | Existing generation and field-reference mechanisms cover their declared scope, including the independent NPU chapter. | Already covered; retain inventories, instance distinctions and stable anchors. Correct mailbox-purpose summaries from the actual register offsets and HAL/RTL producer paths. | Keep chapter, feature, register, diagram and API coverage synchronized. NPU has no implied new external pins. |
| HP boot, mailbox and Linux runtime | The actual `hp_boot` terminal sequence extends beyond initial ready through GA2D ownership/result, cache-clean acknowledgement, HP-held state and return to LP. NPU handoffs are conditional on the P5/P6 acceptance definitions. | Correct shortened boot/recovery summaries, polling units, mailbox-purpose tables and stage-qualified diagrams. Distinguish generic `HP_LINUX_READY` text from the selected runtime. | The supplied Linux rootfs sends initial ready but lacks the later GA2D/cache-clean service. Record that delivery gap; freestanding acceptance behavior does not establish complete Linux integration. |
| Cache handoff, ownership and recovery | Existing non-coherent buffer ownership, clean/invalidate and stop/drain references are adequate. | Already covered; retain these rules and align the boot-specific terminal/failure sequence with them. | Do not reuse buffers before terminal/drain handoff. The failure helper requests reset only before GA2D has been handed to HP; do not generalize an unconditional reset policy. |
| Interface, format and memory budgeting | Mode exclusions, byte packing, pitches, NPU INT8 preprocessing, CPU-finalizer boundaries and buffer accounting are already covered. | Already covered; retain the existing tables and examples. | Check byte order, zero points, allocation/stride and producer/consumer lifetimes. Shared memory does not convert formats; missing ELF/MAP or high-water evidence remains unprovided. |
| Electrical, package, thermal, reliability and ordering | Chapter structure and evidence requirements are complete; measured product values are not. | Structure adequate; retain existing placeholders without adding duplicate chapters. Evidence remains missing. | Supply process/package/corner/board/instrument/workload evidence. Do not substitute target clocks, analytic peaks or commercial-device limits. |
| Development environment and maintenance | Current repository sources define the shared Linux environment, Python 3.10 Docker/Nix choices, the locked SBT tool, Java 17 requirement and activation-script handling. | Update development instructions and source references; link contribution/Git rules in the publication guide. | Follow the committed bootstrap and dependency lock. Environment availability does not establish a firmware, simulator or physical pass. |
| Release evidence | Current CI, prior local tests, historical narratives and exact-profile IP reports have different scopes. | Refresh complete-SHA/UTC CI observations and preserve job/step/runtime-stage status, including pending, failed and skipped work. Previous local test totals remain historical. | Refresh before delivery. A workflow verdict cannot replace the original scoped report, and missing artifacts cannot be reconstructed from prose as current passes. |
| Document navigation and norms | The existing nine-question document map and frozen 109-entry structure are sufficient. | Link Reading this datasheet to the existing map and its nine rows to existing internal anchors. Separate lasting rules from this round's source/baseline/marker record. | Retain one navigator and stable chapter destinations. Verify links after layout; do not add a second guide or restructure adequate chapters. |

## Source/specification discrepancies and follow-up

- [APU specification](../../docs/ip/apu.md) defines synchronous macro-backed KWS,
  coefficient and proof-memo storage. The RTL exposes the frozen wrapper inventory,
  but physical replacement, synthesis-time and peak-RSS claims remain conditional on
  the revision-qualified P9 A/B evidence rather than on source structure alone.
- Older NPU phase comments and some descriptions predate the enabled scheduler
  and capability returns. Keep publication claims tied to instantiated parameters,
  register logic and the compute/DMA path. Clean up stale engineering comments
  separately; this publication refresh does not edit RTL.
- [HP boot orchestration](../../app/apps/hp_boot/main.c),
  [mailbox HAL](../../crt/src/hal/hp_mailbox.c) and
  [Linux ready publisher](../../app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp)
  define distinct parts of the handoff. Document the absent later Linux service
  explicitly. A future Linux integration task must supply and verify the GA2D,
  cache-clean and ownership protocol rather than infer it from the initial marker.
- Dated GA2D/NPU verification narratives lack attached reports for this exact
  publication revision. Keep them historical, with the report/profile/stage
  requirements visible. Obtain original artifacts or execute an appropriately
  scoped campaign before updating current per-IP verification or RTL maturity.
- [Development environment](../../docs/development-environment.md) and its
  [bootstrap](../../scripts/development_environment.py) are the source of truth
  for host requirements. Documentation of Python 3.10 and activation-file mode
  `0644` does not establish a successful Docker, Nix or EDA run.

The [chapter review](chapter-review.md) covers all **109 frozen entries / 42 IP
chapters**, classifies each disposition and recommendation, and binds final page
numbers to the delivered PDF. Document completeness is not protocol compliance,
physical closure or silicon qualification. The independent unnumbered closing
page remains outside that chapter contract. The final validation report records
only checks actually executed for this refresh and identifies all unrun gates.
