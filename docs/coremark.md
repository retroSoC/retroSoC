# Hazard3 CoreMark Measurement

## Scope

The committed IHP130 CoreMark profiles measure the fixed Hazard3 management
core while code, read-only data, writable data, heap, and stack execute from
the Mini SoC SRAM region. The port reads the machine-mode `mcycle` counter and
explicitly enables that counter before the timed workload. This avoids timing
the UART, flash fetches, or a peripheral timer.

The benchmark application emits a single machine-readable UART record:

```text
COREMARK_RESULT mode=quick qualified=0 memory=sram iterations=4 cycles=<n> cpu_hz=72000000
```

`scripts/parse_coremark_log.py` converts the record to `meta/coremark.json`.
`coremark_per_mhz` is calculated as `iterations * 1,000,000 / cycles` and is
rounded to three decimal places. The result also requires `COREMARK_PASS` and
the common `SIM_TEST_PASS` terminal software result.

## Quick Regression Measurement

Run the fixed four-iteration workload with Verilator:

```sh
make CONFIG=configs/benchmark/ihp130-hazard3-coremark.mk \
  SIMU=VERILATOR coremark-report
```

The quick profile is included in the IHP130 nightly regression. It verifies
the CoreMark CRCs, SRAM linker placement, machine cycle counting, report
parsing, and terminal test status. Its short fixed workload is reproducible
for regression trending, but it is not an EEMBC-qualified CoreMark score and
must not be used for public performance claims.

## Standard Hardware Measurement

Build the standard profile for a board or other target where a minimum
ten-second workload is practical:

```sh
make CONFIG=configs/benchmark/ihp130-hazard3-coremark-standard.mk firmware
```

The standard profile lets CoreMark calibrate its iteration count and requires
at least ten seconds of measured execution. It is intentionally not run in
the Verilator CI matrix. A report intended for external comparison also needs
the complete CoreMark/EEMBC run rules, toolchain record, target frequency,
memory configuration, and independent result review.

## Terminal Status

On success or failure, the application calls `rs_test_finish()` from
`<retrosoc/service/test.h>`. It writes SYSCTRL `TEST_STATUS` at `0x1000b084`:

| Bits | Name | Meaning |
| --- | --- | --- |
| 31 | `VALID` | The terminal result is valid. |
| 15:8 | `CODE` | Application-defined diagnostic code. |
| 0 | `PASS` | One for pass and zero for failure. |

The hardware records the first valid full-word write after reset and ignores
later writes. Icarus, Verilator, and VCS pass only when the resulting log
contains `SIM_TEST_PASS`; a timeout or `SIM_TEST_FAIL` is a failure.
