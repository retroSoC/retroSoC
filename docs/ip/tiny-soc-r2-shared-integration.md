# Tiny R2-P6 shared integration

Implementation in progress from `b3b30a72cd6ef5340c28e5044c96cd13258ec5a6`,
against specification blob `7e19de49d49efaafacccfa85671e314d53dd15a4`.
The maintainer approved the single-phase P6 preflight. No phase acceptance,
new operating-frequency claim, commit or publication promotion follows.

Default `configs/ci/ics55-tiny.mk` remains SAFE24 with its PLL parked off;
`configs/ci/ihp130-tiny.mk` remains no-PLL compatibility. CPU and all 32 main
SRAM macros share SYS. Crypto adds its six private 4 KiB macros on the current
SAFE24 PCLK alias, without reducing the 128 KiB main aperture.

## Product boundary

The eight-channel DMA enables requests 0-8 and 12/13 (`0x31ff`). I2C1 requests
9/10, DVP11 and future requests stay unsupported. Default owners are UART0=0,
I2C0=1, camera reservation/explicit memory borrowing=2, serialized bulk=3,
Crypto=4/5 and audio=6/7. The application lease on channel 3 persists across
all WS2812 refill batches; CRC and XPI must acquire it only after release.
SPI16/17 remain outside the existing V2.0 selector ABI and are rejected by
the SDK. This does not claim hardware rejection of arbitrary raw extended
selector writes: the common DMA specification explicitly records their legacy
truncation and requires V2.2 identity/capability guards before SPI integration.

The 20 independent APB branches occupy fabric targets 5-24. SRAM remains
0-3, XPI memory 4, and decode/protocol errors are 25/26. The original three
external owners remain; owner 2 is now the actual SDIO private DMA producer.
P5 response retention, write drain, fault routing and ownership are preserved.
The 21 system reset leaves exclude the independently released AUDIO reset;
neither an absent audio reference nor Crypto initialization holds CPU reset.

Gen1 default GPIO routes are SDIO0-5, UART8/9, I2C10/11, audio12-17,
PWM18-25 (plus its frozen ALT1 outputs), WS26 and XPI chip selects29-31.
Unfrozen UART/I2C alternate inputs, camera, SPI and CLKOUT remain inactive.
The historical ASIC wrapper still has legacy dedicated UART/XPI-CS ports and
its old power-pad inventory. It is not a QFN64 binding. This explicitly
approved compatibility boundary leaves the complete package/power wrapper
to final physical implementation, without changing the frozen package table.

## Shared correctness and software

Tiny's shared DMA validator now accepts integrated streams and eight channels.
Known absent I2C1/SDIO1 and UART flow-control operations fail before MMIO.
SD/SDIO enumeration caps a protocol clock request at half the actual input
frequency; the existing low-level clock calculator still rejects invalid
requests. The bounded SDSC CSD multiplier uses a 32-bit shift factor inside
the unchanged 64-bit capacity calculation, avoiding an absent RV32 runtime
helper without replacing the locked GNU toolchain.
The SD Memory RCA extraction uses raw R6 frame bits 39:24; the preceding
31:16 selection incorrectly shifted the assigned card address by eight bits.

The independent P6 I2S payload fixture reproduced an existing receive-bit
assembly defect in both simulators. Completion now follows capture of the
current sample's LSB at the LRCK boundary. Both widths preserve the existing
register ABI, FIFO/CDC topology and master-only integration. Shared Mini/APU
checks remain required; this is not an I2S slave extension.

Adding partial external GPIO drivers exposed a locked-Verilator simulation
limitation: a packed `tri1` bus loses pulls on its otherwise undriven bits.
The original I2C test consequently saw released SCL/SDA low and timed out.
A minimal reproduction fails in Verilator and passes in Icarus; explicit
independent scalar board nets retain both weak pulls and driven readback in
both tools. Tiny's generated testbench bindings use those scalar nets and an
observation-only packed view. ASIC ports, pad cells, power counts and I2C RTL
are unchanged by this verification repair.

The Tiny `HAVE_SVA=YES` flow now also emits `+define+HAVE_SVA`, which the
owned P4/P5 assertions use. Previously it only omitted the Common
`SV_ASSRT_DISABLE` define; focused fixtures explicitly enabled the owned
assertions but ordinary firmware flows did not. Mini flag behavior is unchanged.

The first full integration reached Crypto but timed out before audio completion.
A smaller actual-SoC diagnostic isolated an I2S status load fault: Tiny's
AXI-to-APB bridge retained the preceding write strobes on reads. Read PSTRB is
now zero as required by APB4, while writes retain their byte lanes. A directed
write/read sequence checks full/partial writes with a strict receiver.
The Tiny firmware limits exception skipping to its explicit CPU probes;
unexpected later load/store faults fail immediately instead of being masked.

Audio shutdown keeps the consumer running while aborting/draining its leased
TX DMA session. A held stream beat cannot retire into an already stopped/full
audio FIFO. Only after DMA retirement does the acceptance image disable I2S
and flush. After a missing-clock flush timeout it polls the outstanding command
through clock recovery instead of issuing another protected COMMAND write.

SDIO's reused card model originally required manual enumeration/data stimulus;
its default ACMD41 never reports READY. The command trace confirmed the
initialization loop. An opt-in SDHC response profile and the existing explicit
data API now support the Tiny board fixture while preserving standalone defaults.
The fixture checks wire-command/data-policy agreement and drives only external
pins. Card timing/protocol/electrical qualification remains excluded. The native
Icarus parser also needs an equivalent explicit enum branch in this model.
Tiny Icarus builds now retain separate testbench/header dependencies, including
the shared card model and P6 board include. Its serial observer emits measurement
records on ordinary runs; TEST_STATUS and strict error checks remain authoritative.

The 12 MHz command case exposed a running-clock start-bit duplication in the
shared SDIO sender. Output admission now waits for its first scheduled launch;
the independent pad sampler covers both admission phases. The card sampler
retains the complete frame across host OE release, including the pulled-high
end bit. This preserves the command/register ABI and does not extend card modes.

The full four-lane SDIO block exposed a separate transmit pause defect: when
memory delayed the next word, a late clock stop corrupted its first bit
(`0x57` became `0xD7`) and caused CRC rejection. The shared data engine now
requests the pause before that launch; the clock wrapper honors it while
draining the current high half-cycle. A full 1024-byte fixture with read-beat
gaps checks payload, CRC and descriptor retirement. Its scalar three-state
variant also caught card-model assumptions about unused lanes being zero;
token and partial-tail checks now account for their pulled-high state.

The receive roundtrip isolated premature descriptor completion after one
64-byte write burst. SDIO private DMA retains ownership until every payload
burst retires or an error is reported. A separately reproduced receive stop
delay shifted the next word (`0x13579BDE` to `0x26AE37BD`); immediate stop
qualification prevents the extra launch. The card's read-CRC sequencer also
skipped one bit and is corrected independently. Delayed descriptor/payload
tests check full readback, CRC, descriptor retirement and both simulators.
These repairs add no masters, channels, descriptor fields or operating modes.

## Validation and historical publication

Workloads keep the ordinary Tiny boot, SRAM/DMA tail, trap, interrupt, RTC,
I2C NACK, JTAG and watchdog-reset checks. P6 adds real GPIO8/9 UART echo;
eight-channel/unsupported-request checks; RNG qualification rejection and IRQ;
CRC DMA, empty input and byte tails; Crypto initialization, AES/SHA/public RSA,
channels 4/5 and zeroization. Audio uses the fixed 18.432 MHz external reference
and 48 kHz master presets, checks 256 stereo frames at both 16 and 24 bits,
and drives paced 33/65-word WS frames in each case. Channel 2 concurrently runs
bounded 256-byte jobs, then four-descriptor chains; channels 6/7 own audio.
The board independently decodes I2S/WS pins, checks FIFO/service bounds and
stops AUDIO low/high for recovery tests. SDIO uses 400 kHz enumeration/one-bit
PIO and 12 MHz four-bit DMA, transfers 1024 bytes in each DMA direction and
512 PIO bytes, overlaps a separate 1024-byte central-DMA job and checks IRQ,
CRC-error, timeout and recovery behavior.

MCYCLE/MINSTRET measure the audio/WS service loop after prefill; elapsed CLINT
time also includes its bounded preparation. The independent AXI observers count
handshakes over the complete firmware run, including boot/control accesses;
they are not payload-only bandwidth measurements. Write counts mean accepted
strobes, not rollback guarantees. Descriptor fetch bytes, per-owner AR/AW/W/R/B
backpressure, WS service gaps and actual SDIO/DMA overlap with CPU progress
remain explicit. `scripts/tiny_r2_p6.py` retains ELF/hex/bin/map, linker/generated
software inputs, simulator binaries/filelists, manifests, logs and their hashes.
Both simulators on both PDKs must have successful commands, Tiny's terminal
`SIM_TEST_PASS`, all workload/independent-observer records and no forbidden
error marker. Component diagnostics never satisfy that collector.

The current Tiny PR and nightly dry-run command matrices are identical for
each PDK. After focused/quality checks, execute full Pytest once and one full
PR per PDK in independent build directories; these broader gates may run in
parallel but must all finish before acceptance. Collect warnings/metrics with explicit `APP=ci_smoke`,
`SYNTH=YOSYS`, `STA=OPENSTA` and the same build timestamp. Do not rerun an
identical nightly matrix. Shared I2S and SDIO standalone/formal checks plus the
affected Mini firmware path remain separate compatibility evidence. Core STA
must execute and bind all 38 exact macros; its slack remains observational.
The legacy IHP130 LibreLane floorplan generator still places the 32 main macros
only. It has not placed/connected the six private Crypto macros or implemented
the final QFN64 wrapper. Full-chip APR/PDN/package work remains outside this
campaign; neither its old floorplan nor smoke STA establishes P6 physical closure.

Development artifacts begin at the manually selected `2026-10-12-12-00`
build label, with subsequent diagnostic labels recorded in each command.
Those labels are not wall-clock measurements; JSON start/end times are.
Some diagnostic firmware directories were reused while finding defects and
must not be rebound to later binaries. The `11-42` snapshot's Make-format gate
failed before long validation. The fresh `2026-10-12-11-50` campaign retains
its input snapshot under `build/ics55-tiny-2026-10-12-11-50-2eb98c0e1fae/meta/tiny-r2-p6/`.
Failed attempts retain their own verdicts and are not acceptance evidence.

Both original PR attempts passed complete Verilator/JTAG acceptance and then
stopped at native Icarus elaboration: `s_token_lanes` referenced `s_data_bytes`
before its declaration. The declaration relocation changes no expression or
other model byte. `verification-update.json` retains the second snapshot;
the collector checks that exact equivalence and rejects any DUT, firmware,
constraint, tool or other model-behavior change. Only the card model and its
collector/tests differ. Original Verilator and Mini results retain their
original source identity. Native Icarus and the remaining physical smoke stages
resume from the failed step; the original failed PR verdicts are not rewritten.
Full Pytest retains its original collection, with the equivalent model edit
during execution; the updated 48-case P6 suite separately covers the native
parser and fail-closed provenance checks. Counts overlap and must not be added.

The one full Pytest attempt reports 1634 passed, one optional `pypdf` skip,
five failures and 60 fixture errors. These reduce to two source-consumer issues:
Mini's publication parser counted inactive Tiny enum branches as Mini channel
allocations, and the commercial Tiny overlay retained its pre-P6 two-domain
allowlist. The parser now selects and checks Mini's actual bulk aliases; no book
identity, chapter, PDF or historical evidence changes. The commercial policy
and Tcl inventory now include the canonical AUDIO root; no licensed flow or
qualified I/O run is implied. `consumer-update.json` binds this separate scope
and rejects changes to RTL, firmware, models or smoke constraints.

Every one of the 65 original failed/error nodes passes in the explicit repair
selection. The complete affected publication/commercial suite reports 512 passed
and one optional PDF-library skip; 35 selected provenance tests also pass.
These counts overlap the full attempt and each other. There is no claimed clean
full-suite rerun: unaffected long tests were retained with their original scope.

### Completed Verilator observations (partial campaign)

`verilator-observations.json` and `report-functional-before-physical.json` bind
the following values to successful command/log artifacts. Each row verifies 256
stereo frames and two WS frames, with 64 completed background jobs. These values
are functional observations, not phase acceptance or timing closure.

| PDK | Audio bits | Service-loop cycles | Retired instructions | Elapsed including preparation (us) |
| --- | ---: | ---: | ---: | ---: |
| ICS55 | 16 | 141917 | 41351 | 8044 |
| ICS55 | 24 | 138353 | 40283 | 7892 |
| IHP130 | 16 | 141917 | 41351 | 8065 |
| IHP130 | 24 | 138350 | 40283 | 7903 |

The independent WS service-gap maxima are 2375/2374 SYS cycles
(98.96/98.92 us), below the 4800-cycle budget; FIFO peak occupancy is 15/16.
Both runs observe 4124 cycles of actual SDIO/private-DMA versus central-DMA
overlap, with 1185 CPU instruction-fetch handshakes in that interval. SDIO's
external owner reads 1056 bytes and accepts 1032 write bytes, including its
descriptor fetch/writeback. Central-DMA descriptor fetches total 16384 bytes.
No cross-architecture speedup or physical rate is inferred from these samples.

Both complete Icarus runs subsequently pass: ICS55 at 16036387 cycles and
IHP130 at 16035743 cycles, with the
same workload, WS, contention and bus observations as its Verilator run.
Its UART observer leaves a partial human-readable line before the testbench's
terminal `SIM_TEST_PASS Tiny cycles=...` record. `collection-update.json`
records a collector/test-only correction to accept that exact terminal token
without requiring a fresh line; JTAG-only/Mini markers, malformed cycle values
and forbidden errors remain rejected. Forty focused collection/provenance
checks pass. Raw logs, RTL, firmware, models and constraints are unchanged.

Both netlist boot checks pass at 30030 cycles. Yosys synthesis and OpenSTA run
for both PDKs and report the exact 32 main plus 6 private Crypto macro bindings.
Observed top-cell/area values are ICS55 412515/2461020.464702 and IHP130
433861/13320370.152627. Setup/hold remain negative: ICS55 WNSmax/WNSmin
−84.93/−0.31 ns, IHP130 −165.41/−0.51 ns. These are smoke-flow observations;
the frozen phase does not use synthesis slack as an intermediate blocking gate.
Warning checks retain new Yosys/Verilator/RTL-lint and IHP130 Icarus signatures
as non-promoted observations under the existing policy; no baseline was edited.

The old Tiny publication remains frozen at its advertised technical revision
`9c706ba0ff1da1028c299cfff573010a86dfd7ce`. Tests execute the original
publication adapter/test snapshot `2805ea91833a6bede32f3a82df3d17d20eb5ec77`
and, separately, the later P5 contract snapshot `b3b30a72cd6ef5340c28e5044c96cd13258ec5a6`.
Neither snapshot becomes P6 publication evidence. Current P6 source must be
rejected by the historical collector. The reset mutation checks still run
against the current target RTL. No frozen chapter, reviewed SHA or old PDF is
rewritten; unavailable PDF/media inputs remain a separate publication gap.

P7 RCU/variable clocks, PWM dependency upgrades, alternate-input ABI, slave
audio, PSRAM, DVP and later extensions remain outside this phase. Timing is
observational before complete-product qualification; exact macro/clock/source
binding and successful functional verdicts remain mandatory.
