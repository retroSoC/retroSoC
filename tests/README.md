# Repository Tests

This directory contains tests for deterministic SDK behavior and build/quality
tooling.

- `c/test_runtime.c` is the host C test program used by `make sw-host-test`.
- `test_npu_framework_reference.py` checks model-specific Softmax scaling,
  all 65536 VWW two-class input combinations, seeded KWS vectors, unchanged
  hardware artifacts and complete sample-model outputs against the locked
  TFLite integer kernels. The C++ adapter under `cpp/` is host verification
  code, not an embedded runtime or an alternative production datapath.
- `test_npu_qualification.py` proves that common-mode Python errors, missing
  oracle tools, stale source revisions and incomplete tensor records fail
  closed. Full corpus qualification is the explicit `npu-p0-qualify` target;
  ordinary Pytest results alone do not establish full-corpus acceptance.
- `test_npu_compiler.py` covers all ABI-1 placements, branching ADD lifetime,
  pooling/Clamp, malformed input, reproducible deployment packages, strict
  host compilation and generated C Softmax vectors. `npu-p5-rtl` separately
  runs the prescribed KWS/VWW inputs on Icarus and Verilator with per-layer
  write traces; `npu-p5-lp-sim` and `npu-p5-hp-sim` establish the two
  bare-metal submission paths and SYSCTRL verdicts.
- `test_npu_p6.py` checks deterministic corpus framing and CRCs, exact PRODUCT
  UART record parsing, cycle-accounting consistency, and fail-closed
  1000-case/2x report rules. The `npu-p6-*`
  targets, rather than Pytest alone, produce formal, PRODUCT Verilator,
  synthesized-block, physical and regression evidence.
- `test_script_tools.py` covers setup, dependency, filelist, warning, metric,
  archive, and regression-helper behavior.
- `test_agent_skills.py` checks the repository feature-skill metadata,
  references, eval corpora, and manual hand-off policy.
- `test_rtl_readiness.py` covers the machine-readable RTL maturity and
  synthesis-intent checks.
- `test_rtl_style.py` covers ownership, named connections, and staged naming
  rules for new owned RTL.
- `test_crypto.py` runs directed AES, SHA-2, RSA/Montgomery, streaming, and
  APB4 simulations; `test_crypto_register_parity.py` checks the handwritten
  RTL/C register ABI and `test_dma.py` covers DMA bursts, TCD fetch, CRC,
  tail-byte writes, and crypto endpoints.
- `test_apu.py` checks the fail-closed APU APB4/IRQ shell plus the P2 private
  DMA, ring scheduler, stream router, Gateway A, and verification-only backend;
  `test_apu_register_parity.py` keeps its handwritten RTL/C ABI and matrix
  coverage synchronized. `test_apu_primitives.py` compares the P4 assembler,
  BAM, loader, sequencer, local SRAM, FIFOs, and production primitive engines
  with Icarus and Verilator while keeping its injectors out of product
  filelists.
- `test_apu_codecs.py` and `test_apu_codec_transport.py` check the P5 target,
  deterministic coefficient/APUMC artifacts, integer WAV/FLAC and PCM models,
  direct/ring product paths, and identical Icarus/Verilator execution of the
  production class-6 transport. The explicit `apu-p5-corpus` target qualifies
  every pinned official FLAC file against locked libFLAC and records matching
  released-APUMC production results from identical verification-only Icarus
  and Verilator fixtures.
- `test_apu_p9_coefficients.py` checks the frozen APUC hashes and complete
  logical-to-bank inverse map with an independent frozen oracle.
  `test_apu_p9_storage.py` runs the synchronous
  coefficient clients and macro-memo clear/insert/lookup boundary fixture;
  the P8 quiesced-loader test covers the successful integrated APUC DMA and
  readback path. The full corruption/retry/reset/abort lifecycle remains a
  separate required P9 evidence matrix and is not inferred from that smoke.
- `test_apu_p8_quiesce_load.py` drives the full `apb4_apu` shell and checks
  that MICROCODE_LOAD and MODEL_LOAD DMA fetches are admitted and complete
  while the LP quiesce is held (the APU-P8 loader-admission regression).
- `test_user_ip_register_parity.py` keeps the integrated slot 1 timer and slot
  2 GPIO register offsets synchronized with their application-owned C
  definitions and checks their extension-manifest slot assignments.
- `test_lp_irq.py` checks the 64-bit LP vector, 62-input metadata, Xh3irq
  wrapper/backend contract, CSR-disabled stubs, and generated routing.
- `test_hp_boot_bundle.py` checks the HP flash ABI, CRCs, payload placement,
  and handwritten mailbox RTL/C offset parity. `test_hp_platform.py`,
  `test_hp_mailbox.py`, `test_plic.py`, and the AXI tests cover the remaining
  HP integration contracts. `test_xpi_fast_flash.py` covers the explicitly
  selected Verilator slot-0 read accelerator, including backpressure and
  negative completion paths.

Add a host C test when changing deterministic runtime or media logic; add a
Python test when changing scripts or build policy. Run:

```sh
make sw-host-test
python3 -m pytest -q
```

These tests complement, but do not replace, firmware builds, RTL simulation,
synthesis, timing, or hardware validation.
