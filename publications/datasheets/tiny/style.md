# Tiny datasheet layout supplement

## Functional IP figure revision

Apply the shared [v2 IP figure standard](../../ip-block-diagrams.md) to all 23
Tiny primary figures and their details. Display the selected Tiny instances and
local functional logic, including lifecycle/clock/reset limits. Thin solid
payload/control arrows use explicit source-bound endpoints and channels;
segments are at least 4 mm, with at most four turns. Mark actual fanout with a
dot and unrelated crossings with a horizontal bridge. Check full arrow, bridge,
line and text footprints. Keep 9 pt text and the 172 x 200 mm frame limit. Other
figure families retain their conventions and selected-product facts.
Check the named functional port assignment inside each IP, not only its outer
module, and keep every label at least 1 mm clear of the IP border. The source
and geometry audits enforce both rules; Tiny SYSCTRL separates APB decode,
first-fault capture, TEST_STATUS and the AON RCU bridge without adding RTL.

Tiny follows the reviewed [Mini visual language](../style.md), but owns an
independent [style implementation](style.typ). This addition does not edit,
import or reflow Mini's template. Changes to Tiny must preserve the publication
isolation boundary rather than inserting fake Mini/HP data into its model.

Use A4 portrait, 19 mm horizontal margins, a 172 mm body, 10.5 pt Inter body,
9 pt tables/source links and Fira Code identifiers, and the existing gold/gray
palette. Headings, table continuation notices, Contents hierarchy, figure/table
directories and underlined links follow the approved layout. Short critical
phrases use true Inter Bold, not an extra font-weight increment. Code remains
regular. Continuation notices retain the existing 8.5 pt exception.

The cover title is `retroSoC Tiny` (30 pt) / `Gen1` (23 pt). The 13 pt positioning
line is `An Open-Source, Single-Core RISC-V MCU`. The Rill bilingual metadata,
version/date, author email and maintainer retain the established two-line grid.
Keep the right-hand title area empty for a logo. The Chinese label uses the
locked Noto CJK Bold and the same cap-edge compensation as the approved cover.

Available is full pale gold; Functional uses a vertical left-half fill;
Reproduced/Tapedout are empty. Marks remain manually controlled prototype status,
not a score derived from a document build or historical test count.

Every IP starts on a new page. Shared UART layouts have one canonical reference
with instance-specific address, IRQ and software qualifications. GPIO views and
DMA/PWM repeated groups preserve exact base/stride/index formulas. A constant
zero capability field must not be mislabeled reserved when it has defined
semantics, such as Tiny's truncated DMA maximum-burst discovery field.

Use the [shared IP drawing standard](../../ip-block-diagrams.md) and locked
CeTZ 0.5.2 for all 23 IP primary diagrams and their details. The system media
figure uses Circuiteria. Formats use Bytefield and storage diagrams use
Blockcell. CeTZ also owns the system fabric, clock tree, overview, connectivity matrix and
software workflows; retain the existing locked waveform renderer. Keep labels at least 9 pt; Tiny has no need to invent compact bus CDC
boxes. Explain diagram abstraction: functional control reach is not a complete
netlist, and representative waveforms are not measured cycle timings. Register
bit layouts and the source-derived 64-byte DMA diagram must match their tables.

Keep implementation, configuration, available tests, executed results and
physical qualification separate. In particular, preserve the negative timing
record and external-device qualification gaps. Record full source/asset hashes,
font/package revisions, PDF digest, page map and actual verification results.

The v0.2 structure adds independent RCU, SPI and shared-IP chapters, including
PPALite in this source refresh, and moves the retired UART1 anchor to the
migration appendix; I2C0 retains the stable `i2c` anchor.
RCU uses a SYSCTRL subregion address card, with one canonical definition per
absolute address in the global index. Main and compatibility profile facts
remain distinct even when their digital layout is identical.

Use the current Mini closing-page visual language in Tiny's independent
`closing.typ`: one final A4 page, bottom-aligned logo reservation and reviewed
notice, with no running header/footer or printed page number. Its paired role
markers are hashed in the manifest; they cannot exempt any ordinary page.
Only marked continuation notices may use 8.5 pt within their exported, hashed
`layout-regions.json` rectangles. Do not lower the global 9 pt threshold.

## Same-version Mini alignment

The front matter follows Features, Overview, Product Configuration and Feature
Availability, Typical Applications and Reading this datasheet. Contents depth is 5.
Peripheral categories follow Memory Interface/NVM/VM, GPIO, DMA, Timers, IO
Interface, Multimedia and Encryption and Data Integrity. XPI/SDIO0/SRAM/UART0
have level-five IP headings; GPIO/DMA use level three; other IPs use level four.
All six standard IP detail headings are bookmarks and are excluded from contents.
Parenthesized IP suffixes in Contents use the existing uppercase-only bold
rule. The reviewed suffixes are PPALITE and CRYPTO.

Contents uses `toc-gap: 4pt` between the measured number column and title, with
14 pt indentation per level. Measure the column from the longest numbered
heading at the same level and keep all titles at that level left aligned;
continuation lines hang under the title. Shorter numbers retain the unused
column width in addition to the fixed gap. This Contents-only parameter is
independent of the 8 pt `heading-gap` for body headings.

List of tables and List of figures use `directory-gap: 4pt` after the measured
prefix column. Measure its width from the longest complete `Table N.` or
`Figure N.` prefix in the respective directory. Titles and continuation lines
share one left edge; shorter prefixes retain the unused column width. Keep
these flat lists independent of Contents hierarchy indentation and body spacing.

The system media Circuiteria figure uses thin rounded blocks,
1 pt signal/control wires and 1.5 pt data buses;
solid data and dashed control paths have horizontal labels on white backing.
Avoid routing through unrelated boxes and retain visible arrow shafts. Source
bindings and logical abstraction notes are mandatory. Never copy Mini LP/HP,
cache, pad or external-memory restrictions into Tiny captions.

Figure 5 uses a 172 × 165 mm maximum plate with Inter labels at 9 pt or
larger. Keep I and D decoding and the two 1.4 pt gold local routes distinct.
Square terminals mark ports and the three owner columns lead to grouped
target rows. Open circles mark structural fabric connections. Draw separate
AXI arrivals for B0–B3 in the shared SRAM block. Keep the XPI memory CDC and
the MEM-domain register bridge on separate routes into the XPI controller.
Group the independent APB4 targets by clock domain. Keep the caption,
`circuit-system-fabric` anchor, and connection-summary reference to Figure 8.

Figure 9 uses a single clock plate up to 172 × 180 mm with Inter labels at
9 pt or larger. Draw external inputs, build-specific paths, SYS distribution,
dividers and consumer branches in that order. Use trapezoids for selectors,
rectangles for dividers and `EN` inputs for leaf hold and output controls.
Draw clock wires as solid 0.65 pt shafts and identify controls and reset
signals with dashed shafts and named paths. Use junction dots on one shared
shaft and a gap at unrelated crossings. Keep labels clear of the wires and
use the existing gold and pale-gold swatches to identify the optional ICS55
PLL group. Label its dashed boundary so it remains legible in grayscale.
Route external AUDIO, PIXCLK and TCK separately. The bottom strip shows
reset sources and synchronizers. Preserve the `circuit-system-clocks` anchor
and keep a source binding for each signal path.

The Overview keeps the product description, six IP groups and reference
configuration on one page. Use three columns and two rows with Mini's outline
icons, gold headers and gray IP cells. All 23 labels appear once. Reuse the
collected profile and SRAM values in the summary and detailed configuration table.

Place the functional architecture in Section 2.1.1. Its seven labeled clock
domains use the 172 mm body width and 9 pt Inter. Draw CPU local I/D separately
from the three AXI initiators. Separate the XPI memory path and register access,
and group APB4 branches by their actual destination clocks. Source validation
checks domain ownership and draws the same orthogonal paths and arrowheads as
the geometry checker. Review title and wire clearances in color and grayscale.
Wire labels in this functional architecture have transparent backgrounds.
Place their text clear of the wires so the domain colors remain visible.

Keep the AXI width on the bus or bridge symbol. Use wire labels for function
and ownership. Place grouped JTAG, SDIO0, XPI, I2S and DVP signals near their
interfaces, with names bound to Tiny's fixed pad and alternate-function routes.
Use the left margin beside the PCLK rows for GPIO, UART0, I2C0, SPI0, PWM and
WS2812 signal groups. Mark GPIO alternate functions with asterisks and keep
their leaders clear of the APB4 branches.

Apply the Mini short-phrase emphasis rule to each IP's features, functional
description and software steps. Select capability limits, prerequisites and
completion or recovery conditions explicitly. Use Inter Bold 700 at the
surrounding size, with regular code identifiers and diagram labels.

Keep the register title, identity, description and bit layout in one page block.
Field-description tables keep their existing independent pagination and
continuation headers. Use exact MiB units for integral large address windows
and retain the smaller KiB and byte units. Label each supplemental IP source
with its filename so that readers can distinguish the destinations.

Draw the DMA descriptor once in the DMA chapter with the FIFO and protocol
example. Link the descriptor-lifetime appendix back to the figure. Keep each
short fault-capture entry, reference and table together as a page block.
Use explicit shared and not-applicable coverage in the diagram inventory.

## 2026-11-14 commercial-reference supplement

The [shared specification standard](../../specifications/README.md) is normative
for states, provenance, reference blocks, curves and replacement. Keep Tiny
v0.2 DRAFT / Gen1 / ICS55-main / IHP130-compatibility independent of Mini.
The current reviewed source is the frozen 2026-11-14 dev commit.

QFN64 is Tiny's confirmed package family with 64 frozen perimeter assignments;
EP is separate and unnumbered. The preferred 9 x 9 mm / 0.5 mm pitch planning
geometry remains Reference Only until supplier outline, die fit, bond map,
metallurgy and assembly approval. No other current Tiny package is advertised.
Use ADI UP64 05-08-1705 Rev C as one coherent outline/land-pattern reference.
Top pin 1 is upper left; numbering is counterclockwise. Bottom mirrors x; PCB
component view follows top. Test uniqueness, mirror, pitch, EP and pad spans.
Never independently renumber a view or call EP pin 65.

### QFN64 drawing layout

#### Target pinout

Open Pin Mapping with a dedicated 172 × 180 mm target pinout plate. Read all
64 main names and positions from the QFN64 target model. Put terminal numbers
inside the left and right edges and between the outline and tags at the top
and bottom. Keep side labels horizontal and rotate the top and bottom tags
along the terminal axis. Put the Pin 1 dot
in the upper-left corner and draw the independently named EP with a dashed
projected outline. Display the frozen target and pending binding states, and
flag the three unbound signal targets by name. Caption the plate `QFN64 target
pinout — top view` and register its standalone `qfn-pinout` SVG and PDF exports.

Share Figure 4's palette. Use system blue-gray for supply, rail gray for ground
and EP, peripheral green for GPIO and UART, memory violet for boot XPI, debug
teal for JTAG, and AON gold for clocks, reset and straps. Use the audio and DVP
domain fills for the respective input-clock callouts. Use dark Inter text at
9 pt or larger and name each category in the legend. Draw selected alternates in
a separate outer lane with a leader from the GPIO name and print the RTL-bound
ALT mode. Keep the full route matrix in its own subsection. Draw reference
body, pitch and EP dimensions from the package catalog, and label them inside
both the book figure and standalone exports.

#### Numbered, mechanical and assembly views

Reuse publication gold (`#A38442`) for view headings, dimension strokes, extension
lines and Pin 1. Use light gray for the drawing field, medium gray for copper,
and dark text for values. Solid outlines, dashed projections, centerlines and
labels retain their meaning in grayscale. Keep panel width within 172 mm and
ordinary labels at 9 pt or larger. Apply the scientific renderer to dimension
subscripts.

Stack the two numbered pin views on one page after the pin-description table.
Place the top and bottom mechanical
views above the numbered dimensions table and the side view. Derive the table
and drawing values from the same ADI-backed records. Show the standoff range
with a blank nominal cell, and distinguish the finished package EP from PCB EP
copper using their respective tolerances. Give the component-side copper pattern
its own page and anchor dimension lines to edges or contact centers as applicable.
Pair solder-mask and paste views above the thermal-via view and assembly notes.
Put REFERENCE ONLY inside each standalone view and its document caption.
Export the individual views and the mechanical plate with the shared geometry.

Copper, mask, paste and via layers are separate. Constructed values belong in
the model catalog and inside standalone vector status labels. Paste coverage
is total aperture area divided by reference EP area. MSL/reflow, thermal values,
order codes and physical binding remain TBD. EP supplements perimeter grounds.

### Tape, reel and reflow references

After Assembly Layers and Reliability, give Carrier Tape Dimensions, Reel
Dimensions, and Reflow Soldering Profile one page each. Put the English heading
and source link above one numbered plate and one numbered parameter table. Use
the QFN64 drawing palette, 172 mm maximum plate width, and 9 pt minimum base
label size. Apply scoped scientific subscripts to tape, reel and temperature
symbols. Place REFERENCE ONLY in each plate and its caption and identify the
status of each table row.

Show the component side of the tape with the sprocket row above the pockets and
the user feed arrow pointing right. Draw the selected Pin 1 quadrant from the
source record. Anchor tape width to the edges, pitch to adjacent pocket centers,
pocket dimensions to the cavity edges, and depth from the web surface to the
pocket floor. Anchor reel diameter to the outer rim and width to the outer
flange faces. Label unpublished geometry as schematic and keep Tiny's supplier
dimensions, orientation, tolerances, hub, bore and pack quantity TBD.

Use a schematic, unticked time axis for the reflow curve. Derive its temperature
levels from the table and align the interval arrows with the soak, liquidus and
near-peak crossings. Identify the peak's package thickness class and the source's
classification and preconditioning scope. Tiny's package limits, MSL and board
profile require product evidence. Maintain nominal values and bounds in the
Tiny parameter catalog and source page, date and fingerprint in the Tiny source
catalog. Export the same plates as standalone SVG and PDF and verify the English
labels, dimensions and grayscale differentiation at 144 dpi.

Minimum-system drawings use external 24 MHz XIN. XOUT, BOOT_MODE, TEST_MODE and
EP separately state target allocation, executable connection and physical binding.
Do not imply a passive-crystal amplifier or production strap decoding. VDDIO
A/B/C/D labels do not establish independent qualified voltage domains.

Keep uppercase-only Contents suffix emphasis, with PPALITE and CRYPTO suffixes.
Architecture wire labels remain transparent. Field captions include IP context.
Tiny now emits paired change markers and their manifest hash for the shared
change-page report. PLL192/PLL240 are conditional functional R2-P7 profiles. SAFE24 boots with the
PLL off; runtime switching requires backend capability, digital lock and the
drain/park/commit protocol. No qualified physical operating rate is implied.

## Scientific formula and quantity typography

Use the shared [scientific display component](../../specifications/scientific.typ) for mathematical powers,
quantity subscripts and mechanical dimension suffixes. Keep raw formulas,
coefficients, units, statuses and numerical CSV values machine-readable and
unchanged; the restricted publication grammar creates inert display tokens
without evaluating source text. Use a multiplication sign and true exponent
for arithmetic; distinguish voltage quantities such as V with OH/OL/IO
subscripts from literal power-pin names such as VDDIO. Only mechanical contexts
attach D2, E2 and A1 suffixes. Software, register, RTL, pin and protocol
identifiers, inline code and code blocks retain their exact source spelling.

Native Typst attachments and Matplotlib MathText use the locked Inter font.
Script size is 70 percent of the surrounding size, with an absolute 6.3 pt
minimum and a parent size of at least 9 pt. This exception applies only to
source-attributed script glyphs inside tight measured rectangles; ordinary
labels and body/table text retain their existing size limits. Never exempt an
entire formula, chart, page or arbitrary small label. Export the script identity,
text, role, font size and rectangle in the hashed layout audit. Independent
SVG/PDF exports keep the same typography and reference-state labels.

Retain scientific-notation.json, plot script metadata, the manifest and the
normal PDF font checks. Verify raw-source preservation, mechanical/protocol
context, exponent parsing, managed fonts and rejection of unrelated small text.
Review changed pages in color and grayscale, including exponent baselines,
line breaks, table rows and standalone figures, then repeat the offline build.
