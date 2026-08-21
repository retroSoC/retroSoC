# SPI-SD Host Verification

This document records the verification evidence and commercial delivery gap
for [`spisd.md`](spisd.md). Passing these tests is evidence for the stated RTL
contract; it is not SD Association certification or physical interoperability
signoff.

## Verification components

| Component | Evidence |
| --- | --- |
| `tests/rtl/spisd_crc_tb.sv` | Published command CRC7 vectors and data CRC16 vectors. |
| `tests/rtl/spisd_clock_tb.sv` | Mode-0 phase events, divider, low-only pause, and stop. |
| `tests/rtl/spisd_command_tb.sv` | Exact 48-bit command frame, R1 capture, and command timeout classification. |
| `tests/rtl/spisd_data_tb.sv` | Multi-word read/write byte order, tokens, CRC16, FIFO backpressure, and accepted write response. |
| `tests/rtl/spisd_wrapper_tb.sv` | APB ID/capability/error behavior, exact 80-clock CS-high training, clock reporting, APB-to-card CMD0 response, and early descriptor-error abort propagation. |
| `rtl/mini/dv/tb/spisd_card.sv` | Reusable SPI-mode SDHC behavioral model with initialization, CSD, CMD6, single-block storage, CRC, busy, and timeout/CRC/write-reject injection controls. |
| `tests/test_spisd.py` | Reproducible Icarus compilation and execution of the focused RTL tests. |
| `tests/test_spisd_register_parity.py` | Handwritten SystemVerilog/C register offset and field parity. |
| `tests/c/test_runtime.c` | Clock rounding, SDSC/SDHC address conversion, CSD v1/v2 parsing, descriptor validation, and publication helpers. |

The behavioral model exposes `force_command_timeout`,
`force_data_crc_error`, and `force_write_reject` through hierarchy. Its
backing store is deterministic and parameterized by block count. The current
wrapper regression consumes CMD0 from the model; broader model functions are
available for the next full initialization and sector-transfer testbench.

## Requirement traceability

| Requirement | Current evidence | Remaining evidence |
| --- | --- | --- |
| One clock, launch falling/sample rising | clock, command, data, and wrapper tests | SVA bound to production wrapper; gate-level phase check |
| 80 clocks with CS high | wrapper test | board power-up trace |
| CRC7/CRC16 | vector, command, and data tests | randomized payloads and injected full-wrapper CRC errors |
| R1 and timeout | command plus model CMD0 tests | R1b/R2/R3/R7 full-wrapper sequences and busy timeout |
| PIO byte order/backpressure | data engine test | APB FIFO 512-byte full-wrapper test and partial final strobes |
| Single/multi-block | engine paths and software command selection | full-wrapper CMD17/18/24/25/CMD12 test |
| SG DMA and native AXI4 | reused SDIO DMA regression and SoC elaboration | SPISD-specific descriptor chains, both directions, 4 KiB split, response errors, and abort drain |
| APB protection/PSLVERR | wrapper test | all offsets, strobes, busy writes, W1C, IRQ test matrix |
| Handwritten RTL/C ABI | parity test | semantic field/access review at release freeze |
| SDSC/SDHC/CSD | deterministic host tests | end-to-end enumeration against both model types and real cards |
| FatFs integration | firmware build and existing regression image | destructive media read/write filesystem test on hardware |
| 36 MHz target | divider simulation and IHP130 STA flow | pad/package/board STA and real-card margin sweep |

## Required checks

Focused development checks are:

```sh
python3 -m pytest -q tests/test_spisd.py tests/test_spisd_register_parity.py
make sw-format-check sw-policy-check sw-host-test
make rtl-format-check rtl-style-check
make CONFIG=configs/ci/ihp130.mk firmware
```

The repository PR regression then runs Verilator and Icarus simulation, Yosys
synthesis, Icarus netlist boot simulation, OpenSTA, warning observation, and
metrics. `--netsim-boot-only` may terminate the long netlist simulation after
the boot marker while allowing the remaining regression steps to execute.
`sim.log`, structured result JSON, and the terminal SYSCTRL test result remain
the verdict; UART text alone is diagnostic.

## Commercial delivery alignment

| Deliverable | Current state | Release gate |
| --- | --- | --- |
| Synthesizable RTL and integration wrapper | Implemented | Clean supported elaboration, synthesis, STA, and reviewed warnings |
| Versioned register and descriptor ABI | Implemented manually with parity test | Freeze/version compatibility review |
| Freestanding HAL and FatFs adapter | Implemented | Target firmware plus real-media error/recovery tests |
| Behavioral card model | Implemented foundation | Full init, sector, multi-block, and fault regression |
| Directed simulation | Implemented at engine/wrapper level | Requirements closure plus randomized stress |
| Assertions/formal | Not SPISD-specific | APB/AXI/phase/descriptor safety and bounded liveness proof |
| Functional/code coverage | Not collected | Reviewed coverage targets and exclusions |
| CDC/RDC | Structurally one clock/reset domain | Tool report confirming no unintended generated-clock logic |
| Lint/format/style | Repository gates available | Zero unreviewed new findings |
| Synthesis/STA/PPA | IHP130 regression available | Archived reports and target margin across required corners |
| PHY/board validation | Not available in simulation | 3.3 V pad assignment, SI/timing, vendor-card matrix, endurance/removal tests |
| Compliance/VIP | Not included | Licensed specification review and external compliance plan if claimed |

Release must not describe the IP as production-ready, silicon-proven,
standards-compliant, or performance-qualified until every applicable gate has
reviewed evidence. In particular, the single-clock architecture removes CDC
complexity but does not prove pad timing, metastability handling at MISO, or
board-level setup/hold margin.
