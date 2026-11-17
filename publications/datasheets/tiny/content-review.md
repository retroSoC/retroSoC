# Tiny Gen1 v0.2 DRAFT content review

Current 2026-11-14 implementation: reviewed dev 6f3f3c83e42eab9ce4acfe4afa8093d7e4c7ac87.
See [the shared round review](../commercial-reference-review.md) for the source delta, independent book scopes, new data/graphics,
comparison baseline and remaining qualification. Earlier records below are historical.

Reviewed source: `f5f58a36758968e984a43159a3e155c56cbe1f38` from `dev`.
Main profile: `configs/ci/ics55-tiny.mk`; compatibility: `configs/ci/ihp130-tiny.mk`.
The approved update reviews the R2-P3..P10 and SPI-P1..P4 increment from the
v0.1 source `9c706ba0ff1da1028c299cfff573010a86dfd7ce`.
The retained 204-page v0.1 PDF has SHA-256
`44d2b6140395ab3adea6e1ca64ce72ba65fa4727213bfca136a6e47010958d4a`.
Mini's publication identity, template, configuration and delivered PDF are unchanged.

The prior delivery-time dev advance from `65028468809f2ac57018b71ce3dc98c96c497167`
to `921a4abfcc099a479892f26883e7ca1cc3b50c19` was reviewed across all 19 changed files.
It adds PIO-lite P1 host ISA/model/assembler sources, ten handwritten programs
and tests; it changes no RTL, HAL, hardware profile or dependency lock.
At that historical checkpoint, the generated PIO-lite acceptance flag was false and Tiny integration was absent.
Historical test counts remain attributed to the original source and environment.

The current structure contains 23 IP chapters and 86 frozen major/IP entries, with 132 outlined navigation entries.
There are 626 canonical register definitions, 1210 expanded instance addresses,
27 address regions and 21 allocated core interrupt causes. The executable wrapper
has 52 signal pads and 32 power pad cells; this is distinct from the approved
QFN64 target with 48 signal and 16 power/ground perimeter terminals.

## Mini hierarchy and engineering-figure alignment

The preceding same-version alignment retained source 921a4abf and its 22-IP inventory.
It compares against the retained 345-page v0.2 PDF, SHA-256
`06528a937d97e764f9514ec7f154954efbc0f97c5f037a370543a0edc9d7d638`.
Twelve main chapters follow Mini's applicable organization. The printed contents
uses five levels; IP internals remain bookmarked without entering printed contents.
Stable Tiny, IP, register and retired-UART1 anchors remain intact.

The current Tiny illustration catalogs contain 26 Circuiteria connection diagrams,
15 Bytefield layouts and 20 Blockcell storage/budget illustrations, plus CeTZ
workflows/overview/matrix and the retained source-checked waveform figures.
Actual port bindings, selected array words, FIFO geometry, fields and source
snippets are checked; missing/duplicate renderings fail build/check.

The imported shared-IP shapes were reviewed against Tiny. XPI's old Mini AXI64/read-only
caption was replaced by Tiny AXI32 and qualified NSS1 writes; UART CTS is tied low
and RTS has no external route. SRAM counter arrows point toward APB observation.
CPU local I/D, DMA CDC and SDIO private ownership remain distinct.
The final visual review removed an inherited UART1 storage note, separated RTC/WDG
response and I2S receive lanes, made external input/output directions explicit,
and included SYS among the APB branch domains. Paired wire labels remain legible
in native-size color and grayscale output.

No RTL/HAL/ABI/dependency version or Mini publication changes are part of this round.
The staged starting patch is preserved independently of the new working-tree edits.

## Functional architecture and reading order

The functional follow-up uses the reviewed 396-page Tiny artifact as its layout
baseline. The introduction now opens with a seven-domain CeTZ diagram. The
collector checks the two CPU paths, three external AXI owners, destination APB4
clocks and selected clock crossings. The detailed fabric figure separates the
two CPU routes at their source ports.

The Overview places the brief reference configuration under the six-group IP
inventory. The DMA chapter carries the primary 64-byte TCD figure alongside the
FIFO and waveform. The memory-budget appendix links back to the figure and
retains the descriptor fields and buffer-lifetime guidance. Each short fault
entry keeps its canonical register link and capture table on the same page.
Final page positions and visual evidence are recorded with the built PDF.

## Register pagination and interface labels

The 398-page functional follow-up is the baseline for this presentation pass.
Register identities and bit layouts share a page. Large integral address
windows use MiB in the IP headers and the canonical address map. Supplemental
IP source links display their filenames. The system figure labels the major
external signal groups from the pad inventory and alternate-function routes.
The publication's page comparison distinguishes these changes from pagination.

The preceding presentation pass used the 403-page artifact as its baseline. Explicit
short emphasis spans cover the 22 IP chapters, with plain text checked against
that baseline. The functional overview adds GPIO, UART0, I2C0, SPI0, PWM and
WS2812 signal labels bound to the pad and alternate-function sources.

## Current dev source refresh

The source delta from `921a4abfcc099a479892f26883e7ca1cc3b50c19` to
`5f460ee02b5403cb3d4a7ae4905bf21173536f53` adds standalone PIO-lite P2 and
PPALite P1-P3. PIO-lite remains outside Tiny. PPALite is wired at
`0x1001E000`, IRQ27 and RCU17 with capability `0x3FF`, exclusive RAW/PROCESS
routing and exact request-11/DMA2 direct admission. The existing request mask,
eight channels, three AXI owners, pad map and main SRAM capacity are retained.
The review follows the route/DMA guard, source epoch/error/configuration
handshakes, DVP crop/stop changes, RCU guards and bounded HAL lifecycle.

At submission, remote `dev` advanced through `fdd1565d57e953aff9a2fa34adb7d3f0ecac6e04`
to `dba9d209a2ddce4aceb6cc0256beae7ea7fdc496`.
The combined 19-file synchronization delta changes CI dispatch/formal budgets, local-only GA2D evidence, PR workflow
and ownership guidance; it changes no RTL, HAL, hardware profile or dependency.
`AGENTS.md` and `docs/engineering.md` are hashed publication inputs, so this
reviewed policy-only advance is included in the final source identity and rebuilt
manifest. The earlier 5f460ee0 publication and validation remain separately identified.

The new chapter includes all 40 SV/C-matched registers, processing formats,
per-row padding and geometry, completion/recovery ordering, circuit/storage/
format/waveform/flow diagrams and a syntax-checked SDK fragment. Existing
DVP, DMA, RCU, system/overview diagrams, maps, register index, roadmap and
source contracts are reconciled. All earlier stable anchors are retained;
the reviewed structural addition is the PPALite chapter and its address-index
entry. The baseline for this comparison is the 403-page PDF with SHA-256
`ae9b8be8f67aba329d7c889c2390286d2ce8bd2ac07d198a5039ff18ff6ddc08`.

PPALite P3 acceptance in [the ledger](../../../docs/ip/ppalite-verification.md)
is attributed to `07cde48e11ed504e0b939d286bf0e0dfcdb924d6`. Its historical
simulator/netlist/host counts are not current-source publication results.
P4 camera/memory/display application qualification and P5 complete-product
physical/timing qualification remain open; negative observational timing is
retained. Earlier freeze text describing PPALite as future hardware is
historical and does not override the reviewed executable integration.

## Content decisions

| Area | Reviewed change | Qualification boundary |
| --- | --- | --- |
| Configuration | ICS55 main; independent IHP130 PLL/ARCHINFO/GPIO capability values. | DRAFT identity is not a hardware acceptance. |
| CPU/SRAM | RV32IMC, A disabled, RV32IM firmware, dual local I/D and four 32 KiB groups. | No second hart, cache, MMU or Linux; reset does not erase SRAM. |
| Fabric | Active CPU slow, central DMA and SDIO owners; target-local service and response retention. | Progress requires running clocks and cooperating peers. |
| DMA | Eight channels, V2.2, mask 0x339FF, streams and qualified SPI admission; TCD bit 25 carries request bit 4. | Endpoint-specific burst bounds and resource leases survive timeout. |
| RCU | Independent chapter within SYSCTRL+0x100..0x15C, IRQ31; AON/SYS/MEM/PCLK/AUDIO/TCK and reset/lifecycle contracts. | SAFE24/PLL192/PLL240 are digital profiles, not silicon speed ratings. |
| Shared services | New RNG, CRC, WS2812, Crypto, I2S and SDIO chapters; Crypto has 24 KiB private PCLK SRAM. | CRC is not authentication; entropy is unqualified; I2S is master-only; SDIO has private DMA. |
| XPI PSRAM | Explicit NSS1/GPIO29 initialization, slot/LUT ownership and 8 MiB capacity. | A 64 MiB aperture is not fitted capacity; clock/reset invalidates the software session. |
| DVP | 8-bit snapshot/crop, GPIO12-23 ALT1, IRQ15, DMA2/request11, exact length and final drain. | Model snapshots do not establish continuous FPS or physical sensor timing. |
| PPALite | P3 APB/IRQ/RCU and exact camera DMA integration; 40 registers and bounded HAL. | P4 applications and P5 complete-product qualification remain open. |
| SPI | Session/GPIO guard, packing, quotas, held-CS, DMA ports, abort/recover and display/snapshot. | DMA done is not wire completion; ST7789VI-style model evidence is not arbitrary-panel qualification. |
| Pins/package | Canonical routes, conflict table, QFN64 target and legacy wrapper shown separately. | Bond map, package outline, PVT/electrical and board evidence remain missing. |
| Migration | UART1 anchor retained in migration; I2C0 retains `i2c`; old I2C1 window/requests removed. | PIO-lite remains unintegrated; PPALite P3 is now explicitly covered. |
| Evidence | Dated R2-P7/P8/P9/P10, SPI-P4 and PPALite-P3 records, with human acceptance separate from generated collector flags. | No historical result becomes a current-SHA hardware pass. |
| Layout | Mini fonts/palette/grid applied in Tiny-owned templates; updated vector paths/waveform domains and unique closing page. | Hash-bound page roles and continuation rectangles constrain exceptions; ordinary checks remain strict. |

## Retained source discrepancies

The register-semantics audit also restores XPI PERF_CTRL bit 1 as a write-one
counter-clear command despite its zero readback. Bit 0 remains stored enable.
The publication correction is bound to the actual readback and clear equations
and protected by a regression test; the hardware is unchanged. The final audit
also binds RTC SECOND_CYCLES to Tiny's 24 MHz AON source, uses committed PCLK
for I2C/WS2812 timing, and replaces inherited ARCHINFO zero/reserved descriptions
with generated build metadata, ICS55 technology fields and tied-off device-ID
error semantics. Short SDK fragments stay on one page; historical commit text
uses a readable abbreviated SHA while structured evidence retains its full SHA.

- DMA's four-bit maximum-burst field reads zero after truncating configured 16.
  Publish that readback separately from the engine's 16-beat maximum and the
  smaller PSRAM/SPI endpoint restrictions.
- SPI CAPABILITY is `0x00003F7F`, with DMA bit 7 clear, while Tiny connects the
  DMA V2.2 origin, pacing and admission path. The table preserves the raw
  value; the chapter separately describes actual routing and phase evidence.
  This task does not repair RTL or HAL discovery.
- PPALite SOURCE_GEOMETRY latches the selected post-crop size in current RTL;
  the original freeze describes full FRAME_SIZE. This publication follows the
  route-controller expression and records that specification/source discrepancy.
- ARCHINFO FEATURES0 is the actual platform word, not a substitute for the
  current per-IP inventory. Build identity remains build-dependent and no
  provisioned unique device identity is advertised.

## Evidence and delivery

The original IHP130 negative timing result remains historical. Later phase
records retain source, profile, PDK, workload, tool and stage identity. A
successful observational STA process is not timing closure. Human acceptance
of R2-P8/P9/P10 on 2026-10-25 and the SPI-P4 ledger decision do not close the
final SPI/PIO-lite/PPALite-inclusive product campaign.

Final page numbers and PDF digest belong to chapter-review.md. Actual commands,
input hashes, full-suite limitations, visual coverage, offline reproduction and
manual old/new page comparisons accompany the final artifact. Publication
checks are not new simulator, physical, board or silicon results. No RTL/HAL,
MISRA deviation, dependency version, warning baseline or metric policy changes
are introduced.

## 2026-11-11 presentation and source review

The reviewed source advances to `f5f58a36758968e984a43159a3e155c56cbe1f38`.
The post-publication dev delta from `74404760308d80a86625a102866e68c188046674`
changes seven CI, dependency-recovery and test/guide files. Tiny RTL, HAL,
hardware profiles and locked dependency versions retain their reviewed values.

The previous delivered 425-page PDF is retained with SHA-256
`c411911532e0e2ddcf3f3ac9eaa85c7575b711b2d022a04bfb4120c0b4d27467`.
The approved title suffixes become PPALITE and CRYPTO across Contents,
headings and the matching navigation/structure records. The uppercase-only
Contents emphasis rule is retained. Functional-architecture wire labels have
transparent backgrounds and positions clear of their wires. Its note links to
the application and PPALite chapters for the RAW/PROCESS data route.
