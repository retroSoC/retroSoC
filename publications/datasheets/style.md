# Mini Datasheet Layout Standard

This document records the implemented layout of the English **retroSoC Mini
Gen2/Gen2+**, **v0.4 DRAFT**, datasheet. It is a maintenance specification, not a
new visual design or a hardware specification. The spacing follows the reviewed
ST RM0486 Rev 4 reference, adapted to the retained Mini page width and fonts.

[style.typ](style.typ), especially its `rhythm` configuration, is the executable
source of truth for shared typography and spacing. Local behavior is implemented
in [ip-reference.typ](ip-reference.typ), [figures.typ](figures.typ),
[waveforms.typ](waveforms.typ) and [sections/overview.typ](sections/overview.typ).
Update this document together with any intentional change to those rules. If
documentation and rendering disagree, inspect the implementation and the PDF;
do not silently apply an older proposal instead.

## System-use content and evidence

The publication includes a complete system-use reference around the detailed IP
chapters. Keep the cover and Overview, then place Product Configuration and
Feature Availability and Typical Applications before Reading this datasheet.
Contents and the two figure directories follow the complete Product Brief.
Memory Attributes/Cache/DMA follows Interconnect; operating-state/reset guidance
extends Clock and Reset. Multicore Ownership, Security Boundaries and Debug/Fault
Recovery follow Interrupt System and precede Peripherals. Connection constraints
extend Packaging. Software owns boot/recovery and the support matrix. Technical
Report owns performance methods; Known Limitations precedes Document Control.

Organize system-use topics as capability/prerequisites, key table, normal steps,
failure handling and sources. Use native numbered lists for actionable sequences
and CeTZ vector diagrams for system connections, state transitions and buffer
handoffs. Keep the existing diagram font sizes and palette; label logical flows
as ordering rather than measured cycle timing. Do not imply direct IP wiring,
new operating modes or a complete application from a conceptual system diagram.

`system-reference.json` is publication-only metadata for every IP chapter's
support row, known limitations and their engineering sources. The builder adds
it as `data.json.system_reference` and hashes all declared sources, tests and
report/profile dependencies. Boot-image addresses and bounds are read from the
existing loader header; the index does not define or generate RTL, registers or
SDK APIs. Keep implementation status separate from verification evidence.

Use `Source reviewed`, `Tests available` and `Reported pass` precisely: a source
or test file's existence does not establish a passing run. A reported pass needs
the actual report, matching full source revision, profile, platform stage and
result. Simulation, FPGA and silicon are different stages. Never promote an old
summary, a device-tree node or a published HAL into unqualified platform support.
When no matching reviewed report is attached, say so in the matrix and retain
physical/performance results as unavailable. A limitation records its impact,
trigger, integration response, applicable snapshot and sources.

Publication-only source references lead to Sources and Reproducibility, where
the matching release manifest and source set are identified. Do not construct
hardware-commit GitHub links for publication files authored after that commit.
Engineering and managed-IP references retain their frozen source destinations.

Executable configuration and implementation take precedence over old narrative
summaries. Correct stale publication prose and diagrams together; do not change
hardware to fit a description. Identify recommended integration policy and
pseudocode explicitly. Do not invent callable APIs, cache services, boot retry,
ready timeout, authentication, power isolation or silicon qualifications. Keep
code examples in the existing syntax-check flow when new C examples are added.

Electrical tables must identify device/process/package, supply/temperature,
load/activity and evidence basis. Separate stress ratings, recommended operating
conditions, typical observations and guaranteed limits. TBD never means zero.
Configuration clocks, behavioral-model checks and analytical bandwidth ceilings
are not characterized operating limits or measured system performance. Keep the
benchmark profile, workload, placement, measurement boundary and report with any
published result; quick CoreMark regression is not a qualified public score.

## Cross-IP programming and usage appendices

Bus Transaction Rules and Arbitration belongs inside Interconnect; Clock,
Divider and Timebase Programming belongs inside Clock and Reset. Place the
DMA Request/Interrupt/Event map after Interrupt System and the coexistence
matrix after Multicore Operation. Register Access and Programming Conventions
precedes Peripherals. Device Compatibility is a child of External Interfaces.
The Software Memory/Buffer and Terminology/Document Map appendices precede
Document Control. Keep existing per-IP register details and link to exceptions
instead of reproducing them in every global table.

`system-reference.json.programming` owns reviewed route bindings, channel
conventions, conflicts, device-profile evidence and terminology. The publication
collector checks RTL/SDK request-number parity (including explicit QSPI/XPI
aliases), coverage, actual connection snippets and referenced instances. Channel
conventions are supported by driver call sites, not inferred from selector IDs.
Private masters and central DMA contexts are different resources. Preserve
endpoint IRQ, aggregate DMA IRQ, LP vector bit and HP PLIC source as separate
fields/namespaces. Derive PLIC assignments and normal master credits from the
current implementation; mark a zero-credit connected route explicitly.

Cross-IP rules are explanatory defaults with documented exceptions. Do not
invent a global atomic-register alias, exclusive-access guarantee or universal
multiword read/write order. Describe PSTRB, W1C, FIFO pop, busy-write and dynamic
reset behavior at the correct register/instance scope. A value present in an SDK
enumeration does not establish that the current hardware start validator accepts it.

Timing examples state input clock, target, integer register values, achieved
nominal rate and rounding/error. Cross-check UART/I2C/timer/I2S calculations
against the existing pure C helpers, including illegal and boundary inputs.
For I2S also check the actual toggle-divider implementation. Nominal digital
rates do not qualify board timing or device speed grades. Never substitute STA
periods for a peripheral's configured functional input frequency.

Compatibility tables distinguish protocol/geometry, model source/test coverage,
board validation and silicon validation. A board/silicon pass needs matching
report context, source revision and profile; absent evidence remains explicit.
Do not pick an arbitrary commercial part or copy its rated speed into Mini ratings.

Buffer examples state payload packing, word padding, alignment, buffer count and
overflow bounds. Distinguish VMA/LMA, static section sizes, image allocation and
runtime demand. A linker stack-top or heap-start symbol is not an actual usage
measurement. DVP odd-line partial words and I2S 16/24-bit packing must be accounted
for; an illustrative double-buffer budget does not imply a hardware ping-pong,
cyclic-descriptor or frame-ring capability. Missing ELF/MAP or high-water evidence
must remain unprovided, not filled with a calculated maximum allocation.

Validate duplicate/missing routes, number mismatches, missing connections, unknown
instances and unsupported qualification claims. Check rounding, field limits,
sample packing, alignment and allocation overflow. Host-only C calculation tests
do not touch MMIO and are not firmware or hardware measurements. Render all new
wide tables, formulas and appendices, check every directory destination, compare
unchanged IP engineering data, and repeat the PDF build in an independent directory.

## Page, typography and color

| Element | Current rule |
| --- | --- |
| Paper | A4 portrait, 210 x 297 mm, including the matrix page |
| Margins | Left/right 19 mm; top 21 mm; bottom 20 mm |
| Body area | 172 mm wide and 256 mm high |
| Body | Inter Regular, 10.5 pt, English, left aligned, no first-line indent |
| Heading levels 1 / 2 / 3 / 4 / 5+ | Inter Semibold, 21 / 16 / 13 / 11 / 10.5 pt |
| Tables, captions, source metadata and header/footer | 9 pt |
| Continuation notices only | Inter Regular, 8.5 pt; renderer-marked size exception |
| Contents entries | 9.5 pt |
| Signals, addresses and code | FiraCode Nerd Font, 9 pt |
| Engineering diagram labels | At least 9 pt at final PDF size |

The `code` helper permits line wrapping after underscores and dots using
zero-width break opportunities. Do not alter identifiers to make them fit.
Preserve the font sizes when content grows; reflow or enlarge the containing
layout instead of shrinking the entire figure or page.

| Token / purpose | Color |
| --- | --- |
| `ink`: body text, engineering strokes | `#292C31` |
| `gold`: heading numbers, accents and emphasis | `#A38442` |
| `pale-gold`: selected diagram cells and integration notes | `#F4EFE4` |
| `gray`: table headers, code blocks, neutral diagram cells | `#F1F2F3` |
| `rule`: secondary separators and placeholder borders | `#D5D6D8` |
| `table-stroke`: ordinary table frames, row rules and bit-layout grids | Black `#000000`, 0.6 pt |
| Figure/table captions and continuation notices | Black `#000000` |
| `muted`: nonlinked metadata, table notes and secondary labels | `#62666C` |
| `link-color`: body links and their underlines | `#245A81` |
| `inline-code-color`: nonlinked Fira Code outside code blocks | `#B12146` (RGB 177, 33, 70) |

Non-block, nonlinked Fira Code uses `inline-code-color` in prose, lists, tables
and register metadata. This includes identifiers, addresses, offsets, field
names and function declarations, through both the `code` helper and native
inline raw text. Keep the existing FiraCode Nerd Font at 9 pt and the current
wrap opportunities.

The color matches the inline monospace identifiers and table addresses in the
[RP2350 datasheet](https://pip-assets.raspberrypi.com/categories/1214-rp2350/documents/RP-008373-DS-2-rp2350-datasheet.pdf),
build date 2025-07-29, printed page 30 (PDF page 31). It was read from the PDF's
text color values, not sampled from an antialiased screenshot. Only the color
is adopted; no reference-document font or asset is added.

Link color takes precedence: linked Fira Code remains `#245A81`; body links keep
their blue underline, while register-summary name links omit it. The shared
`inline-code` wrapper preserves an inherited link-color
scope and applies the red color in other contexts, including muted metadata.
Block-level raw code keeps its syntax palette and gray background. Inter
paragraphs, register headings and bit-layout labels retain their existing colors.

Color supplements names, labels and line styles. It must not be the only way to
read access permissions or distinguish a meaningful engineering state.

Body links use `link-color` with a same-color 0.4 pt underline, offset 2 pt
below the baseline. This applies to external sources and ordinary internal body
links. Normal heading cross-references displayed as `Section N` use the same
`link-color` without an underline. Identify them by their referenced heading,
not by matching the rendered words; preserve automatic numbering and the link
destination. Register-name links in Register Summary tables are an explicit
local exception: keep their blue Fira Code text and destination, without an
underline. This does not affect source links beside register descriptions.
Underlines follow wrapped text rather than
forming one unbreakable line. Source links retain their 9 pt size but do not
override link color with muted gray; nonlinked metadata remains muted.
The printed navigation directories (Contents, List of tables and List of
figures) use ink-colored clickable entries without underlines. Abbreviation
emphasis remains confined to Contents.

## Shared spacing

All lengths below are points unless another unit is stated. A visual baseline
pitch is not the value passed to Typst `par(leading:)`: `leading` separates text
boxes. With the retained Inter font, the relevant box height is approximately
7.639 pt at 10.5 pt and 6.548 pt at 9 pt. Consequently, `leading: 4.96pt` produces
approximately 12.6 pt body baselines, not 4.96 pt baselines. Font changes require
measurement in the rendered PDF.

| Context | Visual target | `rhythm` setting / implementation |
| --- | --- | --- |
| Body lines | Baseline pitch approximately 12.6 | `body-leading: 4.96pt` |
| Body paragraphs | Approximately 6.3 extra between paragraphs; last-to-first baseline approximately 18.9 | `body-spacing: 11.26pt` |
| Small text | Baseline pitch approximately 10.8 | `small-leading: 4.25pt`, `small-spacing: 8.25pt` |
| Lists | Body line pitch; approximately 3 extra between ordinary items | `list-spacing: 7.96pt`, `list-indent: 0pt`, `list-body-indent: 8pt` |
| Figures and numbered tables | 12 before and after | `figure-space: 12pt` |
| Figure caption | Above the image, separated by 6 | `figure-caption: 6pt` |
| Table caption | 4 from the table | `table-caption: 4pt` |
| Continuation notice | 8.5 pt type; 2 pt visible space below its text | `continuation-size: 8.5pt`, `continuation-gap: 2pt`; internal padding in `continuation-notice` |
| Table cells | Horizontal 6, vertical 5 inset | `table-inset: (x: 6pt, y: 5pt)` |
| Table notes | 6 before the note group | `table-notes: 6pt` |
| Code blocks | 8 outside before/after, 8 inside | `code-space: 8pt`, `code-inset: 8pt` |
| Notes and placeholders | 12 outside before/after, 10 inside | `note-space: 12pt`, `note-inset: 10pt` |
| Standalone source / IP metadata groups | 4 before, 6 after | `metadata-before: 4pt`, `metadata-after: 6pt` |
| Register bit layout | 6 before/after; one shared boundary between 16-bit halves; horizontal 3, vertical 5 cell inset | `bits-space: 6pt`, `bits-inset: (x: 3pt, y: 5pt)` |

Fira Code blocks use the small-text leading and 9 pt raw text. Their actual
baseline pitch is font-dependent (approximately 10.6 pt in the checked PDF),
close to the 10.8 pt small-text target. Do not describe a Typst parameter as an
exact measured pitch for every font.

Code-block backgrounds fill 100% of their containing content width, rather than
shrinking to the longest code line. In ordinary body flow this is 172 mm; inside
a nested list it is the available width after indentation. The 8 pt inset is
inside that width. Preserve code font size, syntax coloring, line content and
existing wrapping/breakability; never stretch the text to fill the background.
Continued code blocks retain the same background width on each page segment.

### Headings and flow

| Heading | Before | After |
| --- | --- | --- |
| Level 1 | 28 | 18 |
| Level 2 | 24 | 10 |
| Level 3 | 18 | 8 |
| Level 4 | 12 | 6 |
| Level 5 and deeper | 10 | 5 |
| Functional subheading / minor title | 12 | 6 |
| Register title | 12 | 4 |

Use `heading-layout` with one owner for the surrounding margins. Numbered
headings have an 8 pt number-to-text gutter and a hanging text column; wrapped
lines align with the title text. Functional subheads override spacing without
changing the retained size hierarchy. Register identity wrappers own the 12 pt
leading margin; their inner heading has zero leading margin and 4 pt trailing
margin. Do not add those margins a second time on an enclosing block.

Headings and metadata use sticky blocks to stay with following content. Page-top
spacing must not acquire artificial leading blank space. Adjacent block margins
can merge; the table above is a component specification, not a requirement to
sum all neighboring margins. Verify the rendered transition when nesting blocks.

Use real Typst `list` and `enum` elements for features and software procedures.
The publication converter preserves nested Markdown lists, wrapped item text,
explicit ordered-list numbers and embedded code. Do not substitute paragraphs
beginning with a literal dash or number. Continuation lines align with the item
text, not its marker.

## Navigation and pagination

The entry document requests `contents(depth: 5)`. Preserve this depth and the
existing heading hierarchy. Contents starts on a new page after "Reading this
datasheet", with its title and first entry together. The front-matter order is
**Contents -> List of tables -> List of figures -> System Architecture**.
Each directory starts on a new page and keeps its title with its first entry.
Retain the page break after each complete directory and avoid additional blank
pages. The two figure-directory titles are unnumbered, excluded from Contents,
included as PDF bookmarks, and used as the running header on their pages.

All contents text, including numbering, dot leaders and page numbers, uses the
body ink color `#292C31`, without underlines. This locally overrides ordinary
link color and decoration without
removing clickable destinations or changing links elsewhere in the document.
Within the Peripherals section and its descendants only, uppercase abbreviations
inside parentheses are bold. This includes category and multi-IP forms such as
`(NVM)`, `(OCM / SRAM)` and `(TIM0, TIM1)`. Parentheses, separators and qualifiers
remain regular: in `(APU, partial)`, only `APU` is bold. Titles without parentheses
receive no additional emphasis. Apply this formatting to rendered contents
entries only, preserving the body headings, bookmark text and technical content.

Deeper functional and register headings remain
available through PDF bookmarks and internal links while being excluded from
the printed contents. Register summaries link to their detailed descriptions;
shared UART/SDIO descriptions use explicit instance-to-common-section links.

Contents entries use approximately 16 pt baselines (`toc-leading: 9.09pt`),
14 pt indentation per level, and an 8 pt number-to-title gap. The number column
is measured from the longest outlined, numbered heading at the same level.
Wrapped titles hang under the title text; page numbers remain right aligned
with stretching dot leaders. Each entry is unbreakable. Level-one groups add
12 pt before and 4 pt after to the ordinary entry spacing.

The shared `figure-directory(tables: false)` helper generates List of figures;
`figure-directory(tables: true)` generates List of tables. Follow the single-level
layout of [RM0486](https://www.st.com/resource/en/reference_manual/rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf),
Rev 4, pages 116 and 134, while retaining the publication's typography. Include
every numbered table or non-table figure with a caption, including register
tables, native vector diagrams and waveform figures. Read numbers, full captions
and actual start-page destinations from the document elements; do not maintain a
separate entry list or renumber the body. Include a continued table only once.
Unnumbered address tables, bit layouts and decorative components are excluded.

Both directories use Inter 9.5 pt, the approximately 16 pt Contents baseline,
and ink-colored clickable entries without underlines. Prefix entries with
`Table N.` or `Figure N.` and measure one number-column width from the longest
prefix in each directory. Use an 8 pt prefix-to-title gap, hanging wrapped titles,
stretching dot leaders and right-aligned page numbers. Each whole entry links to
the corresponding figure or table start and remains unbreakable. Do not apply
Contents hierarchy indentation, chapter-group spacing or abbreviation emphasis
to these flat directories. Complete coverage takes precedence over a fixed page
budget; allow the directories to grow as numbered material is added.

Outlined, numbered level-one and level-two headings in the body start on a new
page, including software, implementation and appendix sections. The entire
Product Brief chapter is exempt: Features, Overview, Reading this datasheet and
the bottom-aligned first-page note retain their existing flow and explicit
breaks. Identify this exception by chapter membership, not chapter number.

A chapter opener and its immediately following first level-two heading share
the new page. Do not create a page containing only the level-one title. Later
level-two sections start independently, even when their content is short.
The shared `heading-layout` helper applies this rule to body headings, not
contents entries, unnumbered detail headings or bookmarks.

Each actual IP still starts on a new page. Keep a category heading with its
first IP rather than leaving an isolated category title page. Level-three and
deeper headings otherwise retain their existing flow. Automatic chapter/section
breaks are weak so they merge with existing breaks at an empty page; never
require odd-numbered pages or insert a blank page for a duplicate break.
Preserve the explicit page breaks around the matrix figure and its explanatory
text, and the independent contents start/end breaks.

Keep figures with their captions, headings with their first content, and short
examples with their explanatory notes. Long imported code may break across
pages; the minimal SDK example group remains unbreakable. Avoid indiscriminately
making a whole IP or long register table unbreakable.

## Tables and register pages

Numbered tables use `ds-table`; their captions remain **above** the table.
Figures and tables have separate numbering. Captions are 9 pt, pure black (`#000000`) and
centered by the figure layout. All figure captions, including Overview, matrix,
IP diagrams, waveforms and appendix images, appear above their image with a
6 pt gap. Table captions retain their 4 pt gap. Top captions are sticky and
stay with their image or table opening; keep figures unbreakable rather than
binding a caption to an unrelated paragraph. Do not add captions to unnumbered
images or change figure/table numbering when moving a caption.

Table headers have a light-gray fill and semibold text. Ordinary tables have
a complete outer frame and internal horizontal row rules in black (`#000000`),
all 0.6 pt, using the shared `table-stroke` value. Do not add internal vertical rules. Keep left alignment
and vertical centering. The shared `table-rules` helper supplies the outer cell
edges and row boundaries for numbered tables and unnumbered IP address tables.
Each continued segment has its own closed frame around the repeated column
headers and data rows. Captions, continuation notices and final notes remain
outside the frame; the continuation-notice row has only a bottom rule, which
forms the top edge of the actual table header below it.
All ordinary column headers, including IP address tables and repeated column
headers, use `gray` (`#F1F2F3`). The bit-number rows in register bit-layout tables
remain white; field-name rows retain their existing reserved/field fills.
Individual cells cannot split across pages. The helper keeps tables of eight
or fewer data rows together and permits larger tables to break. Column headers
repeat on continuation pages. Above the repeated column header, show only the
exact text `(continued)`, including parentheses, without a caption or table number.
A logical table is numbered once. Do not add a repeated bottom caption
or silently replace this behavior with a previously proposed footer scheme.

Continuation notices use 8.5 pt Inter Regular in pure black (`#000000`), aligned left.
Keep 2 pt of visible space between the last line of notice text and the table's
top rule. Use internal bottom padding rather than collapsible external block
spacing. The notice stays with the repeated column header. Regular table
captions and other text retain their existing sizes.
The caption color applies to both the Figure/Table prefix and its title text.
Table notes, waveform explanations, headers/footers and other secondary text
retain their existing colors; do not make them black through an enclosing rule.

The `continuation-notice` helper labels its text box; the template exports its
page/rectangle metadata in a layout report separate from the IP header markers.
The build records these markers in `layout-regions.json`, hashes that file in
the PDF manifest, and permits 8.5 pt text only inside those marked regions.
Unmarked or partly outside text still requires 9 pt, and continuation text
below 8.5 pt fails. Missing or changed region data requires rebuilding; do not
lower the global font-size threshold to accommodate notices.

Table notes occur once, after the final table segment, in a nonbreaking 9 pt
muted block. Inspect their continuity with the table during layout changes.
IP address tables and bit-layout tables are unnumbered. IP address tables use
the same black 0.6 pt outer frame and horizontal rules and shared 6/5 pt cell insets.
Bit-layout tables retain their complete internal grid; CeTZ matrices and other
engineering drawings do not inherit ordinary table-frame rules.

Register entries follow this order:

1. Register title, internal anchor and bookmark.
2. Group, offset, access and reset metadata, followed by RTL and C/HAL source
   links on the next line. Keep this identity group together, in 9 pt small-text
   rhythm, with 6 pt trailing space.
3. Register description in body typography.
4. One four-row bit-layout table: bits 31:16, their fields, bits 15:0, then their
   fields. The upper field row and lower bit-number row share one black 0.6 pt rule,
   with no gap or doubled stroke. Keep the whole component unbreakable and
   paragraph spacing zero. Use 9 pt labels, the shared 0.6 pt `table-stroke`, and gray reserved /
   pale-gold field cells.
   Both the bit-number and field-name rows have 3 pt horizontal and 5 pt vertical
   cell insets. Keep the existing total width and 16 columns per segment: extra
   vertical padding increases row height rather than scaling the text or diagram.
   Allow the enlarged layout to reflow the document; ordinary field-description
   tables retain their separate 6/5 pt insets.
5. A numbered field-description table and any register-specific notes.

Long field names use the existing `F1`, `F2`, etc. references when they cannot
fit a bit span; the field table carries the full name. Do not reduce bit-label
font size or change field widths, offsets or semantic data to fit the page.

## Cover and engineering figures

### Compact first page

The 13 pt positioning line reads exactly:
**An Open-Source, Linux-Capable Asymmetric Dual-Core SoC**.

The cover uses Inter Semibold product lines at 30 and 23 pt, a 13 pt positioning
line, and a 9 pt document-status label. Features remain 10.5 pt in two columns
with a 7 mm gutter and the existing six groups. This is an explicit compact
exception to the ordinary body/list rhythm:

| Cover setting | Value |
| --- | --- |
| Paragraph leading / spacing | 4.96 / 3.675 pt |
| Level-one / deeper heading before | 20 / 12 pt |
| Heading after | 6 pt |
| General / metadata / rule gaps | 9 / 10 / 8 pt |
| List | Non-tight; `cover-list-spacing: 7.96pt`; body indent 0.5 em |

Features list continuation lines have approximately 12.6 pt baseline spacing,
with approximately 3 pt extra between items. Keep all six groups, both columns,
10.5 pt text and the existing group-title styling. Use the elastic space above
the Integration Note to accommodate this rhythm, not smaller type or an extra
page.

The Product Brief heading shares a normal-flow row with an Artifact Evaluation
component at the right. Keep the original heading body, numbering, contents
entry and bookmark unchanged; the component is separate display content, not a
numbered figure or an additional heading.

The outer box is 92 x 10 mm with a 1.5 mm corner radius, a 0.6 pt ink border and
white fill (no gray background). Four equal columns show **Available**, **Functional**, **Reproduced**
and **Tapedout**, with 9 pt Inter Regular labels above 3 mm circles. The current
explicit `artifact-status` configuration in `sections/overview.typ` fills only
Available in the existing pale gold (`#F4EFE4`), with a 0.6 pt gold outline;
the other circles are white with 0.6 pt ink outlines.
Keep 4 mm between the heading and box, and vertically center the heading against
the box body. The unnumbered 9 pt black label **Artifact Evaluation** is centered
2 pt below the box. These are native Typst vector shapes and grid content, not
a raster asset or a third-party badge image.

Use the cover's elastic space to accommodate the heading row without reducing
Features typography or moving content to a second page. Marks are manually
maintained publication status; PDF compilation or test success must not
automatically select Functional, Reproduced or Tapedout.

The Integration Note uses the shared pale-gold note style, including the 2 pt
gold left rule and 10 pt inset. A normal-flow `v(1fr)` precedes it and its trailing
external margin is zero. Its bottom aligns with the first-page body boundary,
20 mm above the sheet bottom. It must not overlap Features or move to page two.
Do not achieve this by absolute positioning or shrinking the text.

### Vector diagrams and Overview

Use the locked CeTZ implementation for engineering diagrams. Shared boxes have
0.6 pt ink borders and a 0.6 mm radius; directed wires are 0.65 pt, with solid or
dashed lines as appropriate. Coordinates in `figures.typ` are centimeters at
final size. Diagram labels retain `diagram-leading: 0.4em`; Overview IP labels
use `inventory-leading: 0.35em`. These are deliberate local rules, not body
paragraph spacing.

The PRODUCT Overview uses a 172 x 164 mm outer rectangle with a 2 mm radius and
0.85 pt ink border. Its title is 12 pt semibold, with a short gold line, a subtle
separator and category icons. Side padding is 4 mm; category gaps are 3 mm.
The top and middle rows have three equal-width panels, each 40 mm high. The
55 mm lower area places Connectivity across two columns, with Multimedia and
Security and Integrity stacked at the right (29 and 23 mm, separated by 3 mm).

Category titles are 9.5 pt semibold on pale gold. Panels have 0.55 pt muted
borders and 1 mm radii. IP cells have 0.5 pt muted borders, 1 mm radii and gray
fill; the two processor cells are pale gold. Cells adapt to the item count:
Connectivity uses three columns and splits its last row between two items.

[overview-groups.json](overview-groups.json) is the sole source of category and
IP names (currently nine categories and 43 IPs). Show each integrated PRODUCT
IP once, without external chips, reserved windows, MPW-only blocks, topology
arrows, capacities, frequencies or state badges. Decorative icons express
category only. Keep Overview-only drawing helpers separate from shared boxes.

The Interconnect Matrix remains on a portrait page, 172 mm wide: a 45 mm
initiator column and five 25.4 mm target columns. Header height is 8.5 mm; the
eight data rows are 8.2 mm high. Labels stay at least 9 pt. Permissions are
printed as `R / W`, `R`, `W` or `-`; cells allowing writes also use pale gold.
Do not rescale the complete drawing or change data to make it fit.

### Waveforms

[waveforms.typ](waveforms.typ) renders the locked wavy/jogs output as vector
SVG, normalizes its typography to Inter, and keeps diagram text and edges dark.
Signal names and text inside multibit data blocks use Inter Regular (explicit
SVG weight 400), never bold, and remain at least 9 pt at final size. This includes
bus values, addresses and protocol-phase labels. Normalize the base SVG text
weight as well as the signal-name style in the local renderer wrapper; do not
edit the locked third-party renderer. Preserve data-label text, size, color and
waveform geometry. Lane names must be lowercase real port, interface
member or internal-signal names; retain `_i`, `_o`, `_n` and verified bit/array
selections. Do not turn a prose event such as "memory fence" into a fictitious
signal by replacing spaces with underscores.

[waveforms.json](waveforms.json) owns both the WaveDrom source and each lane's
`signals` provenance record: RTL file, module/interface scope, declared symbol,
polarity and meaning. Each figure records its `clock_domain`, `review_note` and
`review_sources`; parameter overrides require a `parameter_note`. The visible
note identifies the scopes and clock domain. Software actions and compressed
protocol phases belong in that explanation or in data-value labels, not lane
names. Data labels keep their protocol meaning and are not mechanically lowercased.

[waveform_reference.py](../waveform_reference.py) checks one-to-one lane/source
coverage, declaration presence in the correct scope, lowercase names, parameter
resolution, array/bit bounds and scalar-versus-bus notation. Comments and names
from unrelated modules do not establish a declaration. This bounded checker
does not elaborate arbitrary SystemVerilog or simulate behavior; the stored
behavior review supplies the semantic qualification. Unsupported declaration
forms require an explicit, tested parser extension rather than a silent bypass.
All source/review files enter the publication input hash. Each build emits
`waveform-audit.json` with resolved widths, declaration lines and review notes.

Retain a trajectory only when it expresses the real signal's behavior. Split
combined address/data lanes and distinguish sampled inputs, driven outputs and
output enables. Move unmappable behavior rows into prose or replace them with a
reviewed transaction. Omitted intervals and example parameters must be explicit;
never present a schematic waveform as measured latency or electrical signoff.
Long names must fit without reducing text below 9 pt; adjust the label area or
split a dense example when necessary.

Each figure's multi-bit signal rows receive these valid-data fills in order,
including rows inside nested signal groups:

| Sequence | Fill |
| --- | --- |
| 1 | Pale gold `#F4EFE4` |
| 2 | Blue gray `#E7EFF6` |
| 3 | Green gray `#E8F1EA` |
| 4 | Purple gray `#EEEAF5` |

Cycle after four rows and restart at each figure. All valid data segments of a
row use its assigned color. Modify only the rendering copy's valid bus color
codes (`=`, `2` through `9`); keep the canonical WaveDrom data unchanged. Clocks,
single-bit signals, unknown-state patterns, high impedance, edge positions,
labels, nodes and connections retain their meaning and geometry.

The top caption, waveform and bottom explanatory note form one nonbreaking
group spanning the full body width with 12 pt before/after. The note is
center-aligned within that width, uses 9 pt muted small-text rhythm and
4 pt leading space. Keep outer figure spacing on the group only. Inspect the
actual SVG as well as color and grayscale PDF renders.

## Header, footer, assets and maintenance

The header displays `retroSoC Mini Gen2/Gen2+` from `doc.title` on the left and the active IP identifier,
or current level-one chapter outside an IP, on the right. It uses 9 pt muted
text, a 4 pt gap and a 0.6 pt gold rule. The footer uses a 0.35 pt separator,
a 4 pt gap and 9 pt muted text: document ID/version/status at left, current/total
page count centered and the document date at right. Identity values come from
[mini.json](mini.json); do not duplicate them in layout helpers or add a watermark.

Fonts, font licenses and static assets remain in the independently managed,
ignored `publications/media/` repository. Editable engineering drawings remain
Typst source. The [shared dependency lock](../../dependencies/dependencies.lock.json)
owns media and package revisions, including CeTZ, wavy and jogs. Retain Typst
0.15.1 and the existing manual publication workflow; do not add root Makefile
targets, downloads, assets or package dependencies for a spacing adjustment.

Run the documented commands from the repository root:

```sh
python publications/build_datasheet.py setup
python publications/build_datasheet.py build
python publications/build_datasheet.py check
git diff --check
```

Setup is needed to prepare locked resources; ordinary builds use the prepared
resources offline. Pass `--typst PATH` to setup/build when needed. See the
[publication guide](../README.md) for output paths, reproducibility, dependency
checks and validation requirements when Python or technical inputs change.

For layout changes, render the whole PDF and inspect the cover, contents, long
titles, nested lists, continued tables, dense registers, code, Overview and
matrix at final size and in grayscale. Verify font embedding, links, bookmarks,
IP starts, clipping and the cover-note position. Measure baseline pitches after
font or spacing changes. Confirm technical text and generated data are unchanged
for a style-only change, and verify byte-identical offline repeat builds.

For figure-directory changes, verify one-to-one coverage against numbered body
captions, with no duplicates or omitted entries. Check each displayed page and
link destination against the body start page, including continued tables.
Inspect both directories' first, intermediate and final pages, long captions,
four-digit table numbers and the transition to System Architecture. Confirm
that body caption numbers and text are unchanged, new titles do not appear in
Contents, bookmarks and running headers are correct, and Contents links and
footer page totals reflect the added pages.

For heading-link or waveform-weight changes, verify that every normal heading
reference is blue, has no underline and still reaches its original heading.
Sample ordinary source links and all three navigation directories for style
isolation. Export every waveform and inspect the effective font weight of signal
names and multibit data labels, including inherited SVG text styles. Render short,
long and successive bus labels at final size to check for overlap or clipping.
Confirm technical text, figure numbering and generated data are unchanged.

For system-use additions, check the support inventory against every IP chapter,
reject duplicate/missing identifiers and broken source paths, and test rejection
of verification claims without the required report context. Verify boot-layout
extraction and dependency hashing. Review every new engineering statement against
its source; compare the existing hardware/register data before and after the
change. New chapter/table/figure numbers may change automatically, but labels,
destinations and existing technical content must remain valid. Render the full
PDF, inspect new tables/flows and chapter transitions, and verify a byte-identical
offline repeat build in a separate output directory. Do not replace missing
hardware evidence with a successful publication build.

For an edit confined to this Markdown specification or its README link, verify
the descriptions, relative links and commands and run `git diff --check`;
rebuilding the PDF and running hardware validation are not required.
