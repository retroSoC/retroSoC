# Repository Tests

This directory contains tests for deterministic SDK behavior and build/quality
tooling.

- `c/test_runtime.c` is the host C test program used by `make sw-host-test`.
- `test_script_tools.py` covers setup, dependency, filelist, warning, metric,
  archive, and regression-helper behavior.
- `test_rtl_readiness.py` covers the machine-readable RTL maturity and
  synthesis-intent checks.
- `test_rtl_style.py` covers ownership, named connections, and staged naming
  rules for new owned RTL.
- `test_crypto.py` runs directed AES, SHA-2, RSA/Montgomery, streaming, and
  APB4 simulations; `test_crypto_register_parity.py` checks the handwritten
  RTL/C register ABI and `test_dma.py` covers the crypto DMA endpoints.
- `test_user_ip_register_parity.py` keeps the integrated slot 1 timer and slot
  2 GPIO register offsets synchronized with their application-owned C
  definitions and checks their extension-manifest slot assignments.

Add a host C test when changing deterministic runtime or media logic; add a
Python test when changing scripts or build policy. Run:

```sh
make sw-host-test
python3 -m pytest -q
```

These tests complement, but do not replace, firmware builds, RTL simulation,
synthesis, timing, or hardware validation.
