# Source-bound functional IP block diagrams (v2)

This standard governs Tiny's 24 and Mini's 42 primary IP figures and their
adjacent details. The renderer is [ip-block-diagrams.typ](ip-block-diagrams.typ),
with geometry, traceability and export in
[ip_block_reference.py](ip_block_reference.py) and
[ip_block_layout.py](ip_block_layout.py). Existing product circuit
catalogs remain the single source of publication facts; current RTL, selected
instance parameters and product integration remain authoritative.

## Reference and scope

The primary reference is ST **RM0486 Rev 4, May 2026**, in the
[official manual](https://www.st.com/resource/en/reference_manual/rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf).
The reviewed PDF has 4669 pages and SHA-256
`83cb7e9c7f784a4c5dbbedec428adf58d2cbac8cd802d11e2cdc4d504cceaa86`.
Select the closest functional chapter first. Key references include RCC Figure
34 (412), GPDMA Figure 93 (941), DMA2D Figure 132 (1033), GPIO Figure 66
(784), USART Figure 840 (3282), and SPI/I2S Figure 881 (3428). Record whether
each match is functional, structural or an illustration example, including the
particular feature borrowed. DMA2D is the GA2D reference for separate layer
inputs and output conversion. GPU2D Figure 449 (2154) contributes only
organization. Bind each graph to retroSoC source, including buffers, clocks,
resets, selected widths and protocol paths.

The seven system Circuiteria figures, SoC overview, timing diagrams, register
bit layouts, binary/storage figures and package/PCB figures retain their own
design. Other content retains the gold/gray brand. No RTL, software interface,
pin function, model coefficient, product source SHA or qualification is changed.

## Functional provenance

The active style is `ip-block-v2`. A primary must expose the actual functional
path, not delegate the whole implementation to a detail: register access and
control, request/ownership decisions, buffering, protocol/computation stages,
and completion/error feedback where present. There is no minimum box count for
small identity or monitor blocks. Do not invent a FIFO, timer, oscillator,
pipeline, decoder or power domain to meet a visual quota.

The existing product record contains a `functional` projection. Each drawn unit
references an existing RTL instance or binds local logic to an owning module,
real signal names and executable/declaration excerpts. It retains the original
source-group ownership. Multiple local functions in one RTL module are logical
groups, not additional modules. Selected-product parameter references bind
numeric labels to the actual instance, not its generic defaults.

Every parent connection must remain represented by source-qualified functional
endpoints. A bundled connection may be refined into named constituent outputs.
Physical clock/reset/IRQ and bus/stream interfaces retain complete, directional
coverage. A port either reaches the affected functional block or names its
explicit distribution scope. Named pin lists align every arrow with its actual
signal label. Never terminate a clock/reset arrow at an otherwise empty frame.

Local connections require signal and relationship evidence. Only explicit,
source-checked net expressions authorize a shared trunk; a structure name alone
does not join different fields. A shared trunk is emitted once and actual fanout
is dotted. Distinct channel vectors, clock outputs and control fields must not
be joined because they happen to share a source module.

Review groups, ownership, real instances/local logic, direction, width,
clock/reset, enable condition and integration limits before placing boxes.
Serial IP separates registers, buffers, protocol and pins. Clock IP shows actual
selection, division, gating and reset. DMA/memory separates configuration,
scheduling, buffers and transactions. Multimedia follows real processing
stages; small identity/monitor/extension blocks stay small.

`block_diagram` stores product, title, wrapper, boundary ports, external
context, buses, symbols, interface bundles, review rationale, functional
projection, explicit geometry and details. Legacy rows retain source-group
membership; they do not constrain the final placement to an equal-width grid.
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
| Internal data/control/clock/reset/status | Black 0.65 pt solid line and filled arrowhead; name and confirmed width identify its meaning |
| Connections | Orthogonal; no co-linear overlap, ambiguous contact or shared unrelated bend |
| Straight segments | At least 4 mm, including terminal access; collapse duplicate/co-linear points |
| Turns | Prefer zero or two; maximum four per connection |
| Parallel channels | At least 3 mm centre pitch; labeled corridors reserve at least 6 mm |
| Non-connection crossing | Straight segments only, at least 4 mm from bends/ports/arrow tips; horizontal wire carries a 1 mm bridge |
| Crossing budget | At most 12 non-connection crossings in each printed view |
| True connection | Filled node only for source-proven fanout; canonical shared shafts are drawn once |
| Text | Horizontal, transparent Inter Regular, at least 9 pt |
| Figure caption | Above frame, centered, 9 pt Bold, `<IP> block diagram`; normal book Figure number and punctuation |

Functional MUX, divider and gate groups use rectangular port contours and
explicit function names. Do not draw a sloping cell outline while retaining
rectangular north/south port coordinates. A FIFO's inset storage mark is a
symbol, not an instance count. Source-qualified interface aliases stay in the
coverage audit; a unique functional bus name, protocol and width are sufficient
on the figure. Keep raw clock/reset/IRQ names readable and avoid isolated suffix
letters or splitting ordinary English words. Shorten prose rather than fonts.

Numeric labels bind to selected-instance parameters or exact module-scoped
literal templates (including generate bounds). Unknown values must not become
zero. Each physical instance is referenced once per view; split functions in
one instance use local-logic bindings. Shared RTL may be reused, while another
product's wrapper/profile cannot provide its selected facts. Detail boundaries
name their local selection and review; the primary retains the complete product
boundary. Reference Only models and hardware qualification are unchanged by a
drawing review.
| Multiline text | Explicit 3.7 mm line grid; minimum node inset 2 mm horizontal, 1.5 mm vertical |
| Clearance | At least 1 mm to unrelated lines; preserve arrow shafts |

MUX, divider and gate are named rectangular symbols. FIFO has an internal
buffer rule. FIFO dimensions come from selected source
parameters. Control signals are not dashed merely because they are control.
No colored/white text backplates, gradients or rounded IP blocks. Existing
scientific subscript/superscript rules remain; no new size exception is allowed.

Use IP-specific functional zones, unequal block sizes and explicit boundaries.
Place blocks, choose port sides/orders and reserve channels before recording
routes. The build consumes those explicit coordinates and polylines; it never
searches a one-millimetre grid or chooses another routing strategy on failure.
There is no fallback to letter keys, a source/target-only legend or a generic
`Parent connections` / `Control / status` box. Signal labels are on the line,
at a named endpoint, or at their aligned boundary pin; their visible identity
is checked. Preserve literal RTL spelling in the trace records, with concise
functional names in the figure. Do not split ordinary English words to fit a
narrow box; resize/rearrange or choose a precise shorter label.
Keep at least 1 mm clear between text and the IP border as well as unrelated
routes; measure the border's stroke, not only its centreline. Include lower
signal labels when sizing the frame. All owned functions stay inside the gray
boundary; external context keeps its own ownership. Routing labels use actual
reset/ready/enable roles rather than calling every local handshake a command.

Each local function also records `functional_ports`, the named parent-instance
ports assigned to that function. These are references to the existing circuit
facts, not another IP interface definition. Check exact membership, including
within one owning module: a GPIO output cannot move to its input filter, an
I2S receive word cannot originate in its TX serializer, and an XPI return byte
cannot originate in the clock generator. Preserve the real register/core IRQ
pass-throughs and the separate return-data direction. Exclude assertion-only
helpers such as `xchecker`; an enabled configuration register is drawn as its
actual latch. Keep short RTL pin suffixes together when wrapping identifiers.
For input clock/reset paths, distinguish a local module port from its parent's
actual instance association. Validate the full RTL expression, including ORed
resource-stop requests. AUDIO clock/reset must enter the I2S serial domain;
resource reset enters GA2D stop/drain and JPEG job abort/drain logic. Neither is
an APB-register reset. Logical function groups keep executable source bindings
when no separate RTL instance exists. Recheck these paths after any expansion.

If a route fails, revise its placement, ports or channels. If the frame cannot
fit at 9 pt, retain the important functional path in the primary and add an
adjacent semantically named detail. Use `block_diagram.route_details` for
local routes already bound in the primary functional graph. Each entry names
its scope and lists the exact edge IDs. Each moved edge appears in one detail.
The overview retains every declared bus, external signal, clock, reset and
IRQ connection. Isolated internal functions may appear in a scoped detail
when the overview still describes the primary data, control and result
paths. Check this during figure review and link the related views in the
main figure note. The print audit lists the actual edge IDs in each frame.
Each frame/note is
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
- Geometry also records source-qualified nets, individual segment lengths,
  bend counts, canonical shafts, non-connection bridges and rendered arrow
  triangles. Check their full footprints, not only centreline intersections.
- `ip-block-coverage.json`: exact primary/detail counts and actual pages.
- Manifest `ip_block_vectors` / `ip_block_audits`: output hashes; normal input
  hashes bind renderer/catalog/product/shared sources and locked tool versions.

Build/check reject missing/duplicate/unknown diagrams, renderer mismatches,
cross-product metadata, invalid directions/widths, changed named ports/raw
parameters, invented units, invalid source paths and wrong owned boundaries.
Geometry rejects bounds, node overlap, diagonal/short paths, excessive turns,
arrow/line overlap, unrelated-box intersections, invalid bridges and text
collisions. Bridge and pin-label footprints are included. Recompute audit content from fresh inputs as
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

The former wide-arrow and automatic Manhattan implementation is historical.
Keep its delivered PDFs/manifests as the comparison baseline, without accepting
v1 routes as current v2 evidence. New negative tests must retain the former DMA
one-millimetre jog, excessive-turn, arrow-overlap and ambiguous-junction cases.
