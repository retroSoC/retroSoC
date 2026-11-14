# Tiny datasheet layout supplement

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

Use the locked Circuiteria connection renderer, Bytefield formats and Blockcell
storage diagrams. CeTZ owns the six-panel overview, connectivity matrix and
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
Continuation notices alone may use 8.5 pt within their exported, hashed
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

Circuiteria uses thin rounded blocks, 1 pt signal/control wires and 1.5 pt data buses;
solid data and dashed control paths have horizontal labels on white backing.
Avoid routing through unrelated boxes and retain visible arrow shafts. Source
bindings and logical abstraction notes are mandatory. Never copy Mini LP/HP,
cache, pad or external-memory restrictions into Tiny captions.

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
