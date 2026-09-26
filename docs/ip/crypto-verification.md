# Crypto P1 Verification Mapping

The normative contract is [crypto.md](crypto.md). This document maps the
CRYPTO-P1 review fixes to executable checks; it does not change acceptance
requirements or constitute a PASS report. Read the current variant's
`functional.json`, `formal.json`, `coverage.json` and raw results for verdicts.

| Contract / review finding | Executable evidence | Scope |
| --- | --- | --- |
| Clear old DONE on a new command | `crypto_v2_tb.sv` consecutive AES/SHA commands and RSA PREPARE/START; `crypto_apb_formal.sv` command/IRQ next-state assertion | No intervening W1C is required. Fresh unrelated events retain W1C precedence. |
| Configuration reads require READY | `test_runtime.c` counts configuration accesses during FAULT/scrub; `crypto_firmware.c` calls zeroize before initialization and joins maintenance through real LP APB | The host array test complements the full-SoC bus-error behavior. |
| Timeout versus lock completion | `crypto_v2_tb.sv::timeout_cancel_boundaries` and `crypto_firmware.c` | Six APB cases surround COMMIT completion; the LP's 2050-poll budget expires after COMMIT. Cleanup uses the existing ZEROIZE operation and never unlocks a completed image. |
| Readback padding independent of CRC | `crypto_v2_tb.sv::initialize` | Post-load bank-0 rows 528/529 become `0x1`/`0xb8bc6765`. CRC stays `0x99ca52fe`, but padding validation must reject and permit retry. |
| Fault must not retract a held DMA beat | `crypto_v2_tb.sv::fault_with_stalled_output`, `crypto_stream_formal.sv` | Inject a SHA FIFO scrub fault while AES output is stalled. Check TVALID/payload, key revocation, one-beat drain, no new input, no DONE and physical output-FIFO clearing. |
| DMA transport errors | `crypto_dma_v2_tb.sv`, plusargs `dma_read_error` and `dma_write_error` | Real channels 4/5 with AXI read/write errors and backpressure. Abort cannot reclaim a held producer beat; coordinated reset recovers both endpoints. |
| Interruptions throughout computation | `crypto_apb_formal.sv`, `crypto_stream_formal.sv`, `crypto_rsa_release_formal.sv` | Universal next-state properties cover all active engine states, including limb copies and RSA release. AES abort chooses drain/clear; SHA/RSA revoke published state. Global clear resets engine scalar state. |
| Reset at initialization boundaries | `crypto_control_formal.sv`, `crypto_v2_tb.sv::reset_boundaries` | The control proof allows reset on any cycle, including load/verify. Directed cases inspect counts/lock and repeat initialization. |
| Scrub progress and physical erasure | `crypto_scrub_progress_formal.sv`, `crypto_v2_tb.sv::erasure`, `scrub_failure`, `fifo_scrub_failure` | Universal row/progress properties under functioning one-cycle SRAM responses; directed IHP FUNCTIONAL/fallback checks inspect every mutable bank row and all FIFO slots. |
| Numerical and capacity preservation | Existing AES/SHA cases, full RSA-2048 fixture, `crypto_storage_tb.sv`, `crypto_concurrent_tb.sv` | Preserve key sizes/modes, SHA padding, Montgomery carry edges, private verification and equal private schedules. Reduced-width arithmetic is not substituted. |
| Evidence belongs to the tested build | `crypto_p1.py firmware/report`, `test_crypto_p1_evidence.py` | Capture source/config before execution, bind ELF/log/result hashes, reject stale source/artifacts and unsuccessful commands. Pytest execution remains subject to the maintainer's instruction. |

`crypto_response_fault_tb.sv` is the focused response-fault fixture. It uses
verification-only store parameters to model a delayed response, a duplicate
response after retirement, a stale response after an epoch change, and a
missing response. Engine transactions carry both an operation epoch and a
per-bank transaction token; write retirements are never consumed as read
responses. The default product store remains fixed-latency with no fault
injection. Generated VexiiRiscv output, its manifest, and the selected
IHP SRAM behavioral models are included in each firmware run's source hash.

The interruption argument combines universal control properties with bounded
scrub properties and physical-data inspection. The APB proof excludes DMA
traffic; the separate AES stream proof permits arbitrary backpressure and
fault/abort inputs. Its unit-level START assumption requires an idle engine,
a valid key, no held output and no fatal fault; it does not model an illegal
software command flushing a live output FIFO. SRAM arithmetic data is unconstrained in control proofs,
so those proofs do not prove AES/SHA/RSA mathematics. Algorithm fixtures use
independent known answers and the real IHP FUNCTIONAL model.

Storage responses have the frozen one-cycle latency in the product build. The
fault fixture separately exercises delayed/duplicate/missing responses.
Control proofs assume
functioning macro responses and a running clock; they do not establish SRAM
analog correctness, arbitrary silicon fault tolerance, DPA/FIA resistance or
physical timing. P2 still owns full-chip synthesis, functional netlist
simulation, STA, physical views and isolated clean-revision A/B measurement.

Run the committed `configs/ci/ihp130.mk` profile through `crypto-p1-rtl`,
`crypto-p1-formal` and `crypto-p1-synth`, then the recorded LP/CI firmware runs
and focused quality checks described in the specification. Preserve failed
attempts and P0 evidence; a missing proof, test or artifact cannot become PASS
through report assembly.
