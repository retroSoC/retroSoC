# Tiny Gen1 publication

This directory owns the English **retroSoC Tiny Gen1 / Rill (清溪)** datasheet,
its independent v0.1 DRAFT identity, 14 IP chapters and 39 frozen structural
entries. It is a publication adapter, not an RTL or SDK register generator.

The source of truth is `rtl/tiny`, `configs/ci/ihp130-tiny.mk`, the active shared
RTL/SDK and the locked Common/Hazard3/peripheral repositories. The reviewed
SHA belongs in [tiny.json](tiny.json). Address, IRQ and pad mappings are read
from Tiny's canonical inputs. The register profiles select only applicable
families; the owned SYSCTRL and ARCHINFO overrides are checked separately.

## Build and check

From the repository root, with the pinned publication Python dependencies and
Typst version available:

```sh
python3 publications/build_tiny_datasheet.py setup
python3 publications/build_tiny_datasheet.py check --source-only
python3 publications/build_tiny_datasheet.py build --typst /path/to/locked/typst
python3 publications/build_tiny_datasheet.py check --pdf build/<tiny-variant>/retrosoc-tiny-gen1-datasheet.pdf
python3 publications/check_tiny_examples.py --cc gcc
python3 -m pytest -q tests/test_publication_tiny.py tests/test_publication_registers.py tests/test_publication_waveforms.py
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
coverage and representative color/grayscale rendering. Repeat the build offline
and compare PDF bytes. New test counts must come from the current run.

The 24 MHz configuration is not timing-qualified. Publication checks do not
establish simulation, physical, board or silicon qualification. Do not repair
RTL, relax checks, or change warning/metric baselines as a document workaround.
