# Tiny publication workflow

Read the [Tiny guide](../../../../publications/datasheets/tiny/README.md),
[Tiny style supplement](../../../../publications/datasheets/tiny/style.md), and
applicable shared publication/style rules. Use
[tiny.json](../../../../publications/datasheets/tiny/tiny.json), its source and
structure contracts, register profiles, and evidence/content/chapter records.
Tiny facts come from Tiny's own configuration and canonical inputs, plus only
the shared RTL/SDK components it actually uses.

Use [build_tiny_datasheet.py](../../../../publications/build_tiny_datasheet.py).
Its `--config` selects a Tiny publication JSON, not a hardware `.mk` profile.
The current adapter has no Mini `--update` option. Check the actual CLI before
reusing any argument or artifact contract from another book.

Execution examples from the repository root, after authorization:

```sh
python3 publications/build_tiny_datasheet.py setup
python3 publications/build_tiny_datasheet.py check --source-only
python3 publications/build_tiny_datasheet.py build
python3 publications/build_tiny_datasheet.py check --pdf build/<tiny-variant>/retrosoc-tiny-gen1-datasheet.pdf
python3 publications/check_tiny_examples.py --cc gcc
python3 -m pytest -q tests/test_publication_tiny.py tests/test_publication_registers.py tests/test_publication_waveforms.py
```

Pass `--typst PATH` on setup/build when necessary. Tiny setup prepares only the
managed inputs it uses. Outputs belong under `build/datasheet-tiny-*`, and the
latest marker is `.cache/retrosoc/publications/latest-tiny`; do not replace Mini
markers or deliverables. Shared fonts/packages remain locked and hash-checked.

Preserve the book's independent identity and stable structure. Check address,
IRQ, pad, register, clock/reset, and SDK facts against Tiny rather than copying
Mini LP/HP assumptions. Keep source-reviewed support separate from matching
executed reports. A configured clock value is not a timing-qualified rating.

Follow the Tiny guide's source/parameter, register/IP coverage, typography,
navigation, and color/grayscale visual checks. Repeat the authorized build
offline and compare PDF bytes as required by that guide. Record actual checks
and visual-review coverage, not historical test counts.

Retain the old PDF and manifest when available. Inspect the current Tiny
builder's emitted records before selecting a change-report tool: the Mini
`report_changes.py` contract requires specific change markers and page roles
that must not be assumed for Tiny. If those records are unsupported, provide
a labeled manual old/new page comparison with both PDF hashes and page-number
conventions; do not manufacture Mini artifacts or extend the builder as a
publication workaround. Without an old PDF, report that comparison as unrun.

Deliver the Tiny PDF/manifest/check report, source and configuration identity,
chapter/coverage records, applicable comparison, and missing evidence. Never
claim board, physical, simulation, or silicon acceptance from publication tests.
