# Publications

This directory owns manually built technical publications. The Mini datasheet is
an English product document with a separate MPW compatibility appendix. It does
not define or change RTL, register ABIs, build profiles or hardware quality policy.
The canonical RTL/configuration inputs remain authoritative.

## Mini datasheet

- Entry: [datasheets/retroSoC-mini-datasheet.typ](datasheets/retroSoC-mini-datasheet.typ).
- Identity, reviewed hardware commit and reference profiles:
  [datasheets/mini.json](datasheets/mini.json).
- Layout, diagrams and chapter content: `datasheets/style.typ`,
  `datasheets/figures.typ` and `datasheets/sections/`.
- Layout standard: [datasheets/style.md](datasheets/style.md).
- IP-to-window/IRQ/source coverage: [datasheets/ip-catalog.json](datasheets/ip-catalog.json).
- Build and validation: [build_datasheet.py](build_datasheet.py).

The same v0.4 DRAFT now includes detailed per-IP functional, protocol,
register/bitfield and software reference chapters. Each actual IP starts on a
new page; UART/SDIO instances share their common register descriptions.
CPU ISA/CSR manuals remain outside this publication's scope.

The full drawing layer uses bytefield 0.0.8, rivet 0.3.1, blockcell 0.1.0 and
circuiteria 0.2.1. All 40 IP chapters and four system hardware figures use
source-bound circuits. Binary layouts cover descriptors, boot/microcode bundles,
serial framing and media/crypto packing. APU's seven current instruction classes
and 62 operations are grouped by format, operand constraints and tool target.
Storage figures cover architectural FIFOs, line buffers, packet/table/control
memory, descriptor examples, address windows, linker/load placement and budgets.
Overview classification, access matrices, software flows, register bit layouts
and WaveDrom keep their existing rendering.

`diagram_reference.py` coordinates the circuit, binary, instruction and storage
adapters. The catalogs under `datasheets/diagram-*.json` record sources and
primary/shared chapter placement; `diagram-packages.typ` owns their appearance.
`diagram_coverage.py` records covered/shared/not-applicable categories for all
107 frozen entries and rejects declared drawings absent from renderer output.
Instance port directions, selected signal widths, descriptor arrays, FIFO
parameters and linker regions are checked against their actual definitions.
Rendering a connected interface or accepted instruction encoding does not remove
current admission/capability/delivery restrictions.

`package_reference.py` identifies dependencies by name/version, validates each
cache and walks its runtime imports. CeTZ 0.3.4 and oxifmt 0.2.1 are retained for
these packages alongside CeTZ 0.5.2 and oxifmt 1.0.0; tidy 0.3.0 is a runtime
input of circuiteria. Waveforms retain wavy 0.1.3 and jogs 0.2.4.
Setup uses checksum-locked archives, and build/check require the
complete local cache. The manifest records version-qualified package digests
and their runtime import graph. Third-party manual sources are not built.

### Software execution and structure baseline

The same draft now details generic LP startup/linker initialization, conditional
exception/IRQ support, OpenSBI/device-tree/kernel/rootfs handoff, and the ordered
bringup/CI smoke diagnostics. Application result tables retain stage identity
when numeric codes repeat and distinguish a C return from a TEST_STATUS write.
Source-level controller self-tests and known-answer checks are described by
their actual coverage; they are not new hardware pass reports.

`datasheets/system-reference.json.software` holds the reviewed semantic records
and source bindings. `software_reference.py` derives startup choices, software
IRQ bounds, platform properties, mailbox publication order and terminal branches.
The manifest includes their runtime, application, configuration and tool sources.

The [structure contract](datasheets/structure-contract.json) freezes the final
outlined level-one/two headings and all IP entries, including deeper IP titles,
their levels, order and stable anchors. Build/check validate the resolved heading
record; `document-structure.json` is hashed in the manifest. Deeper explanatory
subsections, content, figures and pagination can change without altering the
contract. Normal builds never regenerate it. A later explicit structure-change
task must review the revised contract alongside the document. This publication
baseline does not change DRAFT status or the repository's RTL maturity policy.

The runtime reference also separates polling budgets from time units and API
returns from hardware completion. Ten selected helpers retain their reviewed
zero-budget, partial-transfer and recovery semantics, with source-body bindings.
The HP boot chapter contains byte-level bundle tables, generator-versus-loader
rules and a deterministic synthetic serialization example produced by the
existing packager. The synthetic files are temporary and are not bootable images.
`api_bundle_reference.py` supplies these records through the existing software
data layer; `tests/test_publication_api_bundle.py` compares the format and tests
original C function bodies against memory-backed register substitutes in Linux.

### System-use reference

The same reviewed snapshot also includes configuration/feature availability,
three typical system compositions, non-coherent buffer/DMA handoff, operating
states/reset effects, resource ownership, access-control boundaries, debug/fault
recovery, external-interface constraints, boot/recovery and software support.
Electrical, thermal, performance and power sections describe required conditions
and evidence without manufacturing values for uncharacterized hardware. Known
limitations and revision compatibility are collected before Document Control.

`datasheets/system-reference.json` owns the publication's 40-IP support inventory,
limitation records and source/test/report references. `system_reference.py`
checks coverage, unique identifiers, paths and evidence context; the builder
emits `data.json.system_reference` and hashes these dependencies. Boot-image
addresses and bounds are extracted from the existing loader header. No hardware
or software ABI is generated. The source of truth remains the reviewed RTL,
configuration, HAL, boot loader and Linux platform files.

Implementation, test availability and reviewed successful runs are separate
states. A Linux device-tree node or bare-metal HAL is not native driver support.
The supplied initial console uses SBI. The loader's DMA failure path falls back
to software copy/CRC; its final Linux-ready wait has no firmware-local deadline.
CRC is not authentication. Power isolation, qualified entropy, physical ratings
and production APU codec support are not inferred from controller capabilities.

The cross-IP reference additionally covers register access conventions,
transaction/credit/arbitration rules, DMA request and interrupt routing,
resource coexistence, clock/divider examples and external-memory compatibility.
Two usage appendices provide software/buffer budgets and terminology/document
navigation. `programming_reference.py` collects the corresponding
`system-reference.json.programming` records, verifies RTL/SDK selector parity
and connection evidence, extracts interrupt/credit data, and calculates bounded
timing and buffer examples. The pure timing calculations are cross-checked
against the existing C helpers by `tests/test_publication_programming.py` in the
Linux host environment. No MMIO or new firmware/RTL simulation is involved in
those calculation checks.

The current native JPEG path is connected to master slot 6 but receives zero
normal read/write credits in the reviewed crossbar. The publication now records
that static integration limitation; it does not change RTL or promote standalone
codec tests into an end-to-end SoC DMA result. Existing IP register/codec details
remain available with this system-level qualification.

The implementation-detail layer adds the LP/HP configuration comparison, reset
initial-state/dependency summary, interface selection/subset matrices, multimedia
format interoperability and an image-maintenance chapter. Its publication-only
records live under `system-reference.json.product_details`; the
`implementation_reference.py` collector validates source/reset bindings and
extracts explicit LP/HP parameters, PMA envelopes and build flags. The LP firmware
ISA/CSR choices are kept separate from hardware parameters. Unreviewed upstream
defaults and cache capacity are not inferred from the HP generator's sets/ways.

The Multimedia overview is outside the actual I2S IP page markers; its label
ends the preceding IP header scope. All actual IP sections retain independent
page starts. Interface/format agreement does not remove the existing JPEG or
APU integration gates. The source-level matrices contain no compliance claims.

Image-maintenance examples only describe the existing SRAM-loader flow.
`passed=true` with `executed=false` is script preparation, not device programming.
`tests/test_publication_implementation.py` verifies that distinction with mocked
tool invocation, along with CPU/reset/capability-source checks. No live debugger,
erase/program action, new core generation or hardware measurement is performed.
Board constraint inputs are listed separately from the still-missing approved
schematic, physical package and matching characterization evidence.

The retrieval appendices add a complete instance-qualified register address index
and scoped fault/status-code lookup. `retrieval_reference.py` reuses the register
records and validates publication mappings in `system-reference.json.retrieval`.
It checks array geometry and all expanded addresses while retaining compact
formulas in the PDF, separates GPIO windows/MPW selections, and preserves shared
definition links. Diagnostic enums, masks, field positions, HP boot application
codes, SDK returns and simulator verdicts keep distinct scopes. Their declarations
and producing branches are source-checked; they do not imply feature availability.

Release Verification Summary records test entrypoints, applicable profiles/stages,
matching-report availability and the repository RTL readiness declaration. It does
not promote readiness or replace missing reports with publication test results.
Existing physical/electrical chapters specify the identity and evidence fields
needed before package, PCB, numerical and ordering data can be released.

### Spacing and document flow

The [layout standard](datasheets/style.md) records the implemented page,
typography, spacing, navigation and diagram rules, including the compact cover
and current table-caption behavior. Shared spacing lives in the `rhythm`
configuration in `datasheets/style.typ`; update the standard together with
intentional layout changes and verify actual spacing in the rendered PDF.
The publication converter preserves real nested lists and explicit step numbers;
its regressions are covered by `tests/test_publication_prose.py`.

### Detailed IP reference sources

- `datasheets/register-profiles.json` selects the reviewed RTL, managed IP,
  register groups and instance geometry. Repeated banks retain their real
  base/stride/count instead of duplicating every instance.
- `datasheets/register-annotations.json` supplies reviewed field semantics,
  access qualifications, conditional reset values and explicit special cases.
- `register_reference.py` extracts publication data without generating RTL or
  C definitions. It follows explicit readback packing and selected named
  producer bindings, applies the annotations, and checks offsets, register/field
  reset agreement, value ranges and complete non-overlapping 32-bit layouts.
  Register entries link to RTL and C sources; explicit semantic overrides retain
  a source pointer and review note.
- `datasheets/ip-content.json`, `features.json` and `ips/` own the functional
  chapters. The original grouping and meaningful child sections are retained.
- `datasheets/overview-groups.json` contains only integrated IP names and
  functional categories. Its membership is checked against the topology.
- `datasheets/waveforms.json` contains the WaveDrom examples and per-lane RTL
  declaration bindings, polarity/meaning, clock scope and behavior review.
  `waveform_reference.py` validates declaration coverage and selections and
  generates `waveform-audit.json`; it is a static review aid, not a simulator.
  `waveforms.typ` runs the pinned wavy renderer through jogs and normalizes SVG
  typography before embedding the vector result. The package itself is not patched.
  Representative wait, timeout, backpressure and recovery cases accompany the
  external-interface examples. Circuit figures separately label selected control,
  data and clock-domain relationships and retain instance-specific restrictions.

Fixed, conditional and live reset values are distinguished. A dynamic status
word is not silently assigned a zero reset constant. The source snapshot still
reports APU APB V1.0 and a 16 KiB control store; the later V1.1/32 KiB refreeze
must not be advertised until the implementation and delivery evidence agree.

The title remains **retroSoC Mini Gen2/Gen2+**. PRODUCT is the main configuration;
MPW retains its own appendix. No difference between Gen2 and Gen2+ is inferred.
The reference is `configs/ci/ihp130.mk`, with 32 KiB SRAM. The HP boot example
uses `configs/ci/ihp130-hp.mk`; legacy selection uses `configs/cluster/mini-mpw.mk`.

## Manual workflow

Use Python 3.10 or newer, Git and **Typst 0.15.1**. PDF checks additionally use
`pypdf` and `pdfplumber`, available in the Codex bundled document runtime. The
build uses Python's standard library and the installed Typst CLI; Python 3.10
also uses the `tomli` backport already pinned in `requirements/build.txt`.

From the repository root:

```sh
python publications/build_datasheet.py setup
python publications/build_datasheet.py build
python publications/build_datasheet.py check
```

Validate the displayed SDK call examples with an installed C compiler:

```sh
python publications/check_examples.py --cc gcc
```

This generates only build-local reference-profile headers and runs freestanding
syntax checks. It does not execute the examples or assert hardware validation.

Pass `--typst PATH` to setup/build, or set `TYPST`, if the CLI is not on PATH.
`setup --update` updates clean managed checkouts to their reviewed lock entries
and restores modified package caches. It refuses to overwrite dirty repositories.
Setup obtains the locked media, Common/peripheral and Hazard3 sources used by
the canonical clock/reset checker. It does not install EDA tools or PDKs.

Normal build/check does not fetch updates. Once setup is complete, building is
offline. The compiler is invoked with system fonts disabled, only the media font
directory and the verified package cache. No root Makefile target or automatic
publication workflow is added.

If other work has advanced the hardware beyond `source_revision`, retain those
changes and use an isolated checkout matching the reviewed snapshot with the
publication changes applied there. Do not bypass the snapshot check or advance
the advertised hardware revision to make a document build pass. Keep managed
source checkouts inside that checkout so source-path containment remains valid;
record the isolated publication checkout and input hashes in the build manifest.

Output goes to `build/datasheet-mini-<YYYY-MM-DD-HH-MM>-<input-hash>/`:

- `retrosoc-mini-gen2-gen2plus-datasheet.pdf`: final document;
- `data.json`: profile-resolved engineering tables;
- `manifest.json`: source hashes, reviewed commit, configuration, media commit,
  font hashes, package hashes, compiler version and PDF digest;
- `typst.log` and `check-report.json`: compiler and PDF checks.
- `ip-pages.json`: queried start/end pages used to enforce per-IP page breaks.
- `layout-regions.json`: renderer-marked continuation-text regions, hashed in
  the manifest to limit the 8.5 pt continuation-notice exception.
- `waveform-audit.json`: source files/scopes, declaration lines, resolved lane
  widths and behavior-review qualifications for every waveform.
- `change-markers.json`: paired layout positions for the current edit's substantive
  content, explicit cross-references and navigation changes; hashed in the manifest.
- `document-structure.json`: resolved headings checked against the frozen chapter/IP
  contract and protected by a manifest digest.
- `diagram-inventory.json`: every specialized diagram's package, sources, actual
  page and visual bounds; missing or duplicate renderer uses fail the build.
- `diagram-coverage.json`: per-entry coverage of the 107 frozen structure records,
  including shared diagrams, source pointers and explicit not-applicable reasons.
- `changed-pages.json`: final page-range report, generated after PDF checking with
  the command below; binds the previous delivered PDF and final PDF digests.
  Global presentation changes, such as the repository footer on every page, are
  separate from content and navigation ranges; pagination alone is not a rewrite.

For a content-edit handoff, retain the previous PDF and run:

```sh
python publications/report_changes.py --baseline build/<previous>/<filename>.pdf --pdf build/<final>/<filename>.pdf
```

The report checks printed footers and PDF/marker integrity. Review its ranges
against the rendered content, then include them in the final change summary.
Subsequent pages whose only differences are pagination or automatic numbering
are described separately from substantive edits. Maintain the paired markers for
the current editing round rather than carrying forward stale change claims.

The document date fixes the PDF creation timestamp. Identical inputs produce
identical PDF bytes; the build-directory timestamp is not printed in the PDF.
`--output-dir build/<directory>` selects a build-local destination for iteration.
`check --pdf build/<directory>/<filename>.pdf` checks a specific manifest-backed
PDF; otherwise it checks the last build. `check --source-only` checks inputs and
coverage without requiring the PDF inspection libraries, after setup.

## Source and asset ownership

The ignored `publications/media/` checkout is the independent
[retroSoC/media](https://github.com/retroSoC/media) repository. Fonts, licenses and
static image assets belong there. Current engineering diagrams are editable
Typst/CeTZ source here; they are emitted as vector drawing operators in the PDF.
The three original SVGs are archived byte-for-byte in media and are not used as
current architecture diagrams. Do not reintroduce copies beside the Typst files.

[The shared dependency lock](../dependencies/dependencies.lock.json) pins media,
all eleven runtime package name/version pairs documented above, and the required
local Typst version.
Media's `.gitattributes` prevents platform line-ending conversion of hashed
assets. Every file listed in media's `assets.json` is checked before building.
Typst package extraction uses the shared safe archive helper and a file-hash
manifest. Packages are confined to `.cache/retrosoc/publications/`.

To change assets, edit and review the media repository, regenerate its hash
inventory, commit/push there, then update only `publication_media.revision` in
the main lock. A normal build never commits, pushes, or changes asset revisions.

## Updating technical content

1. Review the current dev RTL and committed configurations; set the exact
   reviewed SHA in `mini.json`. The builder rejects changed technical sources
   relative to this snapshot, including uncommitted tracked changes.
2. Update explanatory prose and `ip-catalog.json`. Every allocated region,
   including reserved ranges, and every LP IRQ must have exactly one owner in
   the publication catalog. Keep still-integrated IPs and their child headings.
3. Address, LP IRQ, GPIO, pad and access-policy data come from existing canonical
   generators. SRAM uses the selected profile size, not the JSON maximum.
4. Review RTL when an architecture document disagrees. Current important cases:
   JPEG occupies AXI64 slot 6; APU advertises WAV/FLAC job/transport infrastructure
   while MP3/KWS and full production qualification remain unavailable. Managed-IP links use their locked
   upstream commits, not nonexistent main-repository blob paths.
5. Compile, check, render all pages and inspect 100% scale and grayscale.

### Deliberately unfilled specifications

| Topic | Missing evidence |
| --- | --- |
| Package and pin numbering | Approved outline, physical pin/pad mapping, pin 1 and thermal pad |
| Electrical and clock ratings | PDK/corners, supply and threshold limits, PLL jitter, load conditions |
| Power, frequency and area | Exact workload/configuration and reproducible measured/signoff reports |
| PCB and external interfaces | Approved schematic, banks, external devices and board timing |
| Assembly and ordering | Supplier reflow/MSL data, part numbers, grades and availability |
| Linux and APU | Native driver/boot/performance qualification beyond the source-level support matrix, and remaining codec/KWS delivery |
| Silicon and roadmap | Identified lot/revision, measurement setup and reviewed release milestones |

TBD never means zero. The legacy 196 MHz, QFN128 dimensions, PicoRV32/TIM2/
ONEWIRE/GA feature claims and Lorem ipsum are not carried forward as product
specifications. CRC remains under the preserved integrity/security grouping,
with an explicit statement that CRC is not encryption.

## Validation boundary

```sh
python scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
ruff check .
python -m pytest -q
python publications/build_datasheet.py check
git diff --check
```

The focused exporter tests are `tests/test_publications.py` and
`tests/test_publication_registers.py`; `tests/test_publication_system.py` covers
support/evidence metadata and boot-layout extraction. Existing memory,
topology and pin-map tests cover the reused canonical validators. PDF checks
verify snapshot freshness, metadata, embedded fonts, bookmarks, navigable links,
minimum 9 pt text (8.5 pt only inside marked continuation notices), page-bound
text, per-IP starts and presence of every generated pad/window.
They complement manual inspection of diagram meaning, continued headers,
footnotes, page balance and grayscale readability.

`tests/test_publication_diagrams.py` and `tests/test_publication_full_diagrams.py`
cover field/source drift, all instruction families, C descriptor layouts, actual
storage geometry, named instance ports, chapter coverage and renderer completeness.
The footer displays the complete clickable repository URL; Contents bolds only
level-one chapter numbers/titles, leaving leaders/page numbers and flat lists regular.

No RTL/HAL change is made by this publication flow. Simulation, synthesis,
CDC/RDC and physical/silicon signoff remain hardware validation tasks and are
not implied by a successful PDF build.

Layout references: [ESP32-P4 datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-p4_datasheet_en.pdf),
[STM32H743 datasheet](https://www.st.com/resource/en/datasheet/stm32h743vi.pdf),
and [CeTZ documentation](https://typst.app/universe/package/cetz/).
