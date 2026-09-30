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

Use native Typst/CeTZ vector structure diagrams and the existing locked waveform
renderer. Keep labels at least 9 pt; Tiny has no need to invent compact bus CDC
boxes. Explain diagram abstraction: functional control reach is not a complete
netlist, and representative waveforms are not measured cycle timings. Register
bit layouts and the source-derived 64-byte DMA diagram must match their tables.

Keep implementation, configuration, available tests, executed results and
physical qualification separate. In particular, preserve the negative timing
record and external-device qualification gaps. Record full source/asset hashes,
font/package revisions, PDF digest, page map and actual verification results.
