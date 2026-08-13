# Repository Tests

This directory contains tests for deterministic SDK behavior and build/quality
tooling.

- `c/test_runtime.c` is the host C test program used by `make sw-host-test`.
- `test_script_tools.py` covers setup, dependency, filelist, warning, metric,
  archive, and regression-helper behavior.
- `test_rtl_readiness.py` covers the machine-readable RTL maturity and
  synthesis-intent checks.

Add a host C test when changing deterministic runtime or media logic; add a
Python test when changing scripts or build policy. Run:

```sh
make sw-host-test
python3 -m pytest -q
```

These tests complement, but do not replace, firmware builds, RTL simulation,
synthesis, timing, or hardware validation.
