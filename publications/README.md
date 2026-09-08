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
- IP-to-window/IRQ/source coverage: [datasheets/ip-catalog.json](datasheets/ip-catalog.json).
- Build and validation: [build_datasheet.py](build_datasheet.py).

The same v0.4 DRAFT now includes detailed per-IP functional, protocol,
register/bitfield and software reference chapters. Each actual IP starts on a
new page; UART/SDIO instances share their common register descriptions.
CPU ISA/CSR manuals remain outside this publication's scope.

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
- `datasheets/waveforms.json` contains the WaveDrom transaction/event examples.
  `waveforms.typ` runs the pinned wavy renderer through jogs and normalizes SVG
  typography before embedding the vector result. The package itself is not patched.
  Representative wait, timeout, backpressure and recovery cases accompany the
  external-interface examples. CeTZ IP diagrams include a data/event path below
  the control and functional units.

Fixed, conditional and live reset values are distinguished. A dynamic status
word is not silently assigned a zero reset constant. The expanded P5 source
snapshot reports APU APB V1.1 and a 32 KiB control store while retaining APUMC
V1 image compatibility.

The title remains **retroSoC Mini Gen2/Gen2+**. PRODUCT is the main configuration;
MPW retains its own appendix. No difference between Gen2 and Gen2+ is inferred.
The reference is `configs/ci/ihp130.mk`, with 32 KiB SRAM. The HP boot example
uses `configs/ci/ihp130-hp.mk`; legacy selection uses `configs/cluster/mini-mpw.mk`.

## Manual workflow

Use Python 3.10 or newer, Git and **Typst 0.15.1**. PDF checks additionally use
`pypdf` and `pdfplumber`, available in the Codex bundled document runtime. The
build itself uses Python's standard library and the installed Typst CLI.

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

Output goes to `build/datasheet-mini-<YYYY-MM-DD-HH-MM>-<input-hash>/`:

- `retrosoc-mini-gen2-gen2plus-datasheet.pdf`: final document;
- `data.json`: profile-resolved engineering tables;
- `manifest.json`: source hashes, reviewed commit, configuration, media commit,
  font hashes, package hashes, compiler version and PDF digest;
- `typst.log` and `check-report.json`: compiler and PDF checks.
- `ip-pages.json`: queried start/end pages used to enforce per-IP page breaks.

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
CeTZ 0.5.2, oxifmt 1.0.0, wavy 0.1.3, jogs 0.2.4 and the required local Typst version.
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
| Linux and APU | Reviewed driver matrix, boot/performance evidence and remaining codec/KWS delivery |
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
`tests/test_publication_registers.py`; existing memory,
topology and pin-map tests cover the reused canonical validators. PDF checks
verify snapshot freshness, metadata, embedded fonts, bookmarks, navigable links,
minimum 9 pt text, page-bound text, per-IP starts and presence of every generated pad/window.
They complement manual inspection of diagram meaning, continued headers,
footnotes, page balance and grayscale readability.

No RTL/HAL change is made by this publication flow. Simulation, synthesis,
CDC/RDC and physical/silicon signoff remain hardware validation tasks and are
not implied by a successful PDF build.

Layout references: [ESP32-P4 datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-p4_datasheet_en.pdf),
[STM32H743 datasheet](https://www.st.com/resource/en/datasheet/stm32h743vi.pdf),
and [CeTZ documentation](https://typst.app/universe/package/cetz/).
