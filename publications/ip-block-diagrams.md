# Source-bound IP block diagrams

This standard governs Tiny's 23 and Mini's 42 primary IP figures and their
adjacent details. The renderer is [ip-block-diagrams.typ](ip-block-diagrams.typ),
with geometry, traceability and export in
[ip_block_reference.py](ip_block_reference.py). Existing product circuit
catalogs remain the single source of publication facts; current RTL, selected
instance parameters and product integration remain authoritative.

## Reference and scope

The visual references are ST **RM0486 Rev 4, May 2026**, RCC Figure 34, page
412, and GPU2D Figure 449, page 2154, in the
[official manual](https://www.st.com/resource/en/reference_manual/rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf).
The reviewed PDF has 4669 pages and SHA-256
`83cb7e9c7f784a4c5dbbedec428adf58d2cbac8cd802d11e2cdc4d504cceaa86`.
Borrow the engineering drawing language, not ST hardware or drawing identifiers.
GA2D must not acquire a texture/rasterizer pipeline; RCU must not acquire absent
oscillators, PLLs or power domains.

The seven system Circuiteria figures, SoC overview, timing diagrams, register
bit layouts, binary/storage figures and package/PCB figures retain their own
design. Other content retains the gold/gray brand. No RTL, software interface,
pin function, model coefficient, product source SHA or qualification is changed.

## Functional provenance

Review groups, ownership, real instances/local logic, direction, width,
clock/reset, enable condition and integration limits before placing boxes.
Serial IP separates registers, buffers, protocol and pins. Clock IP shows actual
selection, division, gating and reset. DMA/memory separates configuration,
scheduling, buffers and transactions. Multimedia follows real processing
stages; small identity/monitor/extension blocks stay small.

`block_diagram` stores product, title, wrapper, boundary ports, rows, external
context, buses, symbols, interface bundles, review rationale and details.
`node.units` stores real modules, instances, port associations, raw/selected
parameters, conditions and source bindings. Detail `members` reference those
IDs, rather than copying facts. A parent-local staging box is a logical group,
not an invented module. Preserve CDC, shared pins, tied inputs, unused outputs,
inactive configurations, blocked admission and qualification limits in the
figure or adjacent note.

Every connection has source-bound endpoints. APB/AXI request/response bundles
can use bidirectional connectors without implying a second initiator. Streams
retain explicit direction. Clock/reset/IRQ declarations belong to the chosen
IP wrapper, not a whole-SoC wrapper used as a substitute. Unknown widths remain
logical bundles without invented numbers. Retain primary `circuit-<IP>` anchors;
details use `circuit-<IP>-detail-<group>` and reviewed semantic group names. Do not automatically pair instances or
split by list position. Every view is a normal Figure with a directory entry.

## Visual language at final size

| Element | Rule |
| --- | --- |
| Canvas | White, at most 172 mm wide and 200 mm high; never scale down |
| Functional block | White, square corners, black 0.6 pt border |
| Owned boundary | Black 0.9 pt border, neutral `#F2F2F2` background |
| Condition/group | Dashed rectangle with an explicit condition/group name |
| External bus | Black 3 pt spine; confirmed protocol and data width |
| Internal data | White-filled, black-outlined wide arrow, 2 mm shaft |
| Control/clock/reset/status | Black 0.65 pt solid line, filled arrowhead |
| Connections | Orthogonal; dot only for an actual same-source/net branch |
| Text | Horizontal, transparent Inter Regular, at least 9 pt |
| Figure caption | Above frame, centered, 9 pt Bold, `<IP> block diagram`; normal book Figure number and punctuation |
| Multiline text | Explicit 3.7 mm line grid; minimum node inset 2 mm horizontal, 1.5 mm vertical |
| Clearance | At least 1 mm to unrelated lines; preserve arrow shafts |

MUX is trapezoidal; divider/gate are named rectangular functional symbols; FIFO
has an internal buffer rule. FIFO dimensions come from selected source
parameters. Control signals are not dashed merely because they are control.
No colored/white text backplates, gradients or rounded IP blocks. Existing
scientific subscript/superscript rules remain; no new size exception is allowed.

Use semantic rows and explicit boundaries. The Manhattan router records final
ports/routes separately from functional facts. A short callout may replace a
wire label only with a complete adjacent 9 pt legend. Do not omit connections
to simplify a drawing. Complex primaries retain all boundary interfaces and
group connections; put internals in adjacent details. Each frame/note is
nonbreaking and may occupy one page. Never split frames or shrink text. Preserve
chapter/register anchors and navigation contracts despite page growth.

## Outputs and acceptance

Keep both setup/build/check entrypoints and locked CeTZ 0.5.2/fonts. No vendor
edits or extra dependencies. Each build emits:

- `ip-blocks/<id>.svg` and `.pdf`, carrying title and limitations;
  `ip-blocks/ip-views.typ` and `data.json` retain editable sources.
- `ip-block-sources.json`: product/style, groups, ownership, symbols, real
  instances/parameters, boundary signals, interface widths, conditions,
  source fingerprints and connection bindings.
- `ip-block-geometry.json`: final-size nodes, text, routes, arrows and junctions.
- `ip-block-coverage.json`: exact primary/detail counts and actual pages.
- Manifest `ip_block_vectors` / `ip_block_audits`: output hashes; normal input
  hashes bind renderer/catalog/product/shared sources and locked tool versions.

Build/check reject missing/duplicate/unknown diagrams, renderer mismatches,
cross-product metadata, invalid directions/widths, changed named ports/raw
parameters, invented units, invalid source paths and wrong owned boundaries.
Geometry rejects bounds, node overlap, diagonal/zero-length paths, unrelated-box
intersections and text collisions. Recompute audit content from fresh inputs as
well as checking hashes. Negative tests live in `tests/test_publication_ip_blocks.py`.

Technical snapshot and incremental-CI inventory consumers explicitly use
`tiny_reference.collect(..., check_snapshot=False, layout=False)`: they retain
the same complete source paths and functional binding checks without loading
fonts or generating routes. These records are not publication layout evidence.
Normal publication build/check keeps layout enabled and requires the locked
font, every view and all geometry checks; a missing font still fails closed.

Preserve baseline PDFs/manifests. Run source checks, example syntax, Ruff,
publication/full Pytest, lock/document checks and `git diff --check`. Check final
PDF fonts, bounds, size, links, directories, continuations and inventories.
Render every page in color and grayscale at native size; inspect every new
primary/detail and rearranged page, comparing retained content to baseline.
Contact sheets aid triage, not native-size acceptance. Repeat offline in the
same locked environment and compare both main PDFs and standalone vector bytes.
Retain failures/unrun checks. Publication acceptance is not hardware qualification.

Scientific display audits remain mandatory in every round. Set the explicit
boolean `scientific_change_markers` to false for an IP-only layout round so
retained formulas are not labeled as newly modified. Enable it for a reviewed
scientific-notation edit; unknown display uses still fail either way.

Route different nets with distinct shafts and keep their bends separate; ordinary
perpendicular crossings carry no dot. Reserve every endpoint access stub before
routing. Only identical source-port/net bundles may share a branch. Record the
selected deterministic routing strategy in geometry audits. A wire name that
repeats its source-block title may be omitted. Where a safe callout does not fit,
a source-to-target mapping including connection type is allowed only if that
directed pair/type identifies exactly one connection; ambiguous parallel paths
still require distinct on-figure labels. Keep legends clear of all routes.
