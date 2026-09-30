# Mini publication workflow

Read the [publication guide](../../../../publications/README.md), applicable
sections of the [style contract](../../../../publications/datasheets/style.md),
and the current content/chapter review records before editing. The publication
identity is [mini.json](../../../../publications/datasheets/mini.json); inspect
its selected hardware profiles instead of assuming a configuration maximum is
the shipped value.

Use [build_datasheet.py](../../../../publications/build_datasheet.py). Its
`--config` selects a publication JSON, not a hardware `.mk` profile. All commands
below run from the repository root, using the locked tools and dependencies.
They are execution examples, not an instruction to run them in inspect mode.

```sh
python3 publications/build_datasheet.py setup
python3 publications/build_datasheet.py check --source-only
python3 publications/build_datasheet.py build
python3 publications/build_datasheet.py check --pdf build/<mini-variant>/<filename>.pdf
python3 publications/check_examples.py --cc gcc
```

Use `--typst PATH` on setup/build if necessary. Normal build/check stays offline
after setup. `setup --update` reconciles managed inputs to the current reviewed
lock; it is not a dependency-version upgrade and must not overwrite dirty
repositories. Inspect its effects and obtain any missing authorization before
using it. Prefer an explicit `--pdf` during validation so a last-build marker
cannot silently select the wrong deliverable.

For content refreshes, reconcile the frozen structure, IP catalog, canonical
address/IRQ/pad/register sources, prose, illustrations, and examples. Do not
regenerate the structure contract merely because a heading changed. Retain
the previous PDF and its supporting manifest before rebuilding. Current-round
change markers must describe this edit rather than repeat an older claim.

After the PDF checks pass, use the Mini change-report contract:

```sh
python3 publications/report_changes.py --baseline build/<previous>/<filename>.pdf --pdf build/<final>/<filename>.pdf
```

This requires compatible manifest-backed PDFs, change markers, and page-role
records. Review the reported ranges against rendered pages, separating
substantive edits, navigation, global presentation, and pagination. Do not
fabricate a report when the baseline or required records are absent.

Follow the guide's complete-page visual review at 100% scale and in grayscale,
including links, bookmarks, register/table continuations, diagrams, and the
closing-page exception. Run the affected publication/exporter tests and other
root-contract checks proportionate to the actual edits. Example syntax checks
do not execute firmware. Source/PDF validation does not establish electrical,
software-runtime, timing, or silicon qualification.

Deliver the PDF, source identity, manifest, check report, applicable coverage
and page records, changed-pages report, actual visual-review coverage, and
remaining gaps. Keep outputs under the builder's `build/datasheet-mini-*` root.
