# Repository Tests

This directory contains tests for deterministic SDK behavior and build/quality
tooling.

- `c/test_runtime.c` is the host C test program used by `make sw-host-test`.
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
- `test_user_ip_register_parity.py` keeps the integrated slot 1 timer and slot
  2 GPIO register offsets synchronized with their application-owned C
  definitions and checks their extension-manifest slot assignments.
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
