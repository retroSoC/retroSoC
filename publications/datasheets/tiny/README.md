# Tiny Gen1 publication

This directory owns the English **retroSoC Tiny Gen1 / Rill (清溪)** datasheet,
its independent v0.2 DRAFT identity and 24 current IP chapters. The same-version
Mini alignment uses 12 main chapters, 88 frozen major/IP entries and a five-level
145-entry navigation contract. The explicitly
reviewed structure retains stable anchors, moves retired UART1/I2C1 interfaces
to migration guidance and adds the RCU/SPI/shared-IP chapters. It is a publication
adapter, not an RTL or SDK register generator.

The source of truth is `rtl/tiny`, `configs/ci/ics55-tiny.mk`, the explicit
`configs/ci/ihp130-tiny.mk` compatibility profile, the active shared
RTL/SDK and the locked Common/Hazard3/peripheral repositories. The reviewed
SHA belongs in [tiny.json](tiny.json). Address, IRQ and pad mappings are read
from Tiny's canonical inputs. The register profiles select only applicable
families; the owned SYSCTRL and ARCHINFO overrides are checked separately.

## Build and check

The 2026-11-18 RM0486 review compares all Tiny IP views against the PR #289
baseline. Source-qualified local routes in adjacent details use the same
functional graph as their overview. Keep all declared product interfaces in the
main view and validate each printed view using the
[shared standard](../../ip-block-diagrams.md).

The 2026-11-17 IP detail round keeps v0.2 DRAFT and Gen1. It starts from
publication dev `80486b9f`, with the 455-page delivered PDF as comparison
baseline. The integrated edition uses the reviewed technical snapshot
`4db113e17efb3932dc3778b736011f87fc271495` used by the integrated PIOLITE-P3 topic. Edit
function/source bindings and final millimetre
coordinates in `diagram-circuits.json`; do not edit generated SVG/PDF or use the
legacy circuit coordinates as v2 layout. Follow the shared
[IP drawing standard](../../ip-block-diagrams.md) and
[current review](../../ip-block-detail-review.md). Mini has separate product
configuration and artifacts.

From the repository root, with the pinned publication Python dependencies and
Typst version available:

```sh
python3 publications/build_tiny_datasheet.py setup
python3 publications/build_tiny_datasheet.py check --source-only
python3 publications/build_tiny_datasheet.py build --typst /path/to/locked/typst
python3 publications/build_tiny_datasheet.py check --pdf build/<tiny-variant>/retrosoc-tiny-gen1-datasheet.pdf
python3 publications/check_tiny_examples.py --cc gcc
python3 -m pytest -q tests/test_publication_tiny.py tests/test_publication_registers.py tests/test_publication_waveforms.py
python3 -m pytest -q tests/test_publication_tiny_refresh.py
```

The optional `--config` selects a Tiny configuration file. Outputs belong to
`build/datasheet-tiny-<UTC-date-time>-<input-hash>/`. The only latest-build marker
written is `.cache/retrosoc/publications/latest-tiny`; Mini markers and products
are not replaced. Font/package caches are shared and hash-checked. Tiny setup
requires only the managed inputs it uses, not MPW, VexiiRiscv or accelerator data.

## Content and validation boundary

- [Layout supplement](style.md) defines the Tiny use of the approved Mini visual language.
- [Content review](content-review.md) records retained coverage and known gaps.
- [Chapter review](chapter-review.md) binds chapter/IP coverage to the delivered PDF.
- [Structure contract](structure-contract.json) freezes entry order and labels independently of page count.
- [Source contract](source-contract.json) binds numerical maps and critical behavior.
- [Evidence](evidence.json) distinguishes dated repository narratives from matching executed reports.

The broad validation report and PDF hash accompany each build. Verify links,
source/parameter consistency, character sizes, outlines, complete register/IP
coverage and complete-page native-size color/grayscale rendering. Repeat the build offline
and compare PDF bytes. New test counts must come from the current run.

The RCU register family owns SYSCTRL offsets 0x100..0x15C without claiming a
second decoded window. Expanded register-index addresses are unique. SPI's raw
DMA capability bit remains zero despite its connected Tiny DMA path; DMA's
maximum-burst discovery field still truncates 16 to zero. Both discrepancies
are documented rather than repaired by publication code.

The final closing page has a manifest-bound page role; all other pages retain
their running furniture and numbered footers. `layout-regions.json` bounds the
8.5 pt continuation-notice exception; ordinary text remains at least 9 pt.
Old/new comparisons use a manual, hash-bound report because the previous Tiny
artifact does not implement Mini's change-report record contract.

SAFE24 and PLL192/240 are not timing-qualified ratings. Publication checks do not
establish simulation, physical, board or silicon qualification. Do not repair
RTL, relax checks, or change warning/metric baselines as a document workaround.

## Mini-alignment implementation

`sections/` owns the full-book hierarchy. `navigation-contract.json` freezes all
outlined entries; `structure-contract.json` keeps the major/IP compatibility
contract. IP detail headings are unnumbered bookmarks, with the actual IP depth.
`engineering-figures.typ` adapts all 24 IP primary figures and their details to
the shared locked CeTZ [IP renderer](../../ip-block-diagrams.md). Three system
figures retain Circuiteria; Bytefield and Blockcell retain their scope.
`diagrams.typ` owns the CeTZ overview, matrix and
workflows. `soc-functional.typ` draws the functional overview from
`soc-functional.json` and the geometry validated by the Tiny collector.
The Tiny collector uses common validation functions without loading Mini data.
Each build writes `diagram-coverage.json` and checks every actual drawing against
its expected inventory. Layout/type/source exceptions are not broadened.

## Shared specification maintenance

Use the [shared standard](../../specifications/README.md) and this book's
[parameter catalog](specifications/parameters.json). Tiny QFN64 and examples stay
separate from Mini. Current builds emit specification-data/status/usage/replacement
audits, CSV/SVG/PDF curves, editable standalone engineering vectors and paired
change markers. The tape, reel and reflow references use the
[Tiny source catalog](specifications/sources.json) and the same parameter records
in the plates, tables and audits. The Tiny QFN64 assembly update compares against
the 452-page delivery from dev `33c61f9a` using `report_changes.py`. Tests and
successful publication builds do not qualify hardware.
