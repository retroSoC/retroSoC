# Tiny ICS55 SAFE24 platform

This runbook implements the boundary of
[TINY-ICS55-P1](tiny-soc.md#tiny-ics55-p1---default-pdk-and-pll-platform-enablement).
Acceptance and exact artifact roots belong in the [ledger](tiny-soc-verification.md).
The implementation starts from `ecac3559b0ba67fa2630003ad718657969c78af4`.

## Platform and ownership

`configs/ci/ics55-tiny.mk` selects TINY/ICS55, HAVE_PLL=YES, 128 KiB macro SRAM
and external 24 MHz SAFE24. `make SOC=TINY` selects this profile; explicit
`PDK=IHP130` selects the existing compatibility profile. Mini defaults remain
unchanged. This phase does not add a crystal input, change the frozen package
or pin map, add a clock mux, or implement the RCU register bank.

The ASIC wrapper selects `UseIcs55EcosPll=1` and `Ics55Parked=1`. The retained
PLL macro has constant EN=0 and N=32; it cannot drive SYS. The digital monitor
and control cone are unused in this configuration. SAFE24 CPU release never
waits for a PLL or an external peripheral clock. P2's five-edge reset chains,
CPU-last startup, watchdog POR boundary and payload retention remain intact.
Full clock switching and system clock-fault recovery remain R2-P7.

Shared `onchip_ram` defaults still use the legacy ICS55 16 KiB geometry for
Mini. Tiny explicitly selects `Ics55SmallBanks=1`, restricted to the 32-bit
interface, to bind 32 OpenECOS 1024x32 macros. This changes technology selection,
not arbitration or the future four logical bank services. IHP130 remains on
its original 32 4 KiB macros. Memory aperture, byte masks, response semantics
and software bank discovery remain unchanged for Tiny.

Tiny's generated GPIO pad instances explicitly select `ReadWhileDriving=1`.
ICS55's IE and OE are independent; enabling IE while driving preserves Tiny's
pad-input readback contract. The shared wrapper default is still zero for
Mini. Dedicated tests check both settings against native Icarus and functional
Verilator pad views. Firmware tests real technology pull capabilities instead
of assuming the IHP130 lack of pulls. ARCHINFO reports technology 0x02040037
and PLL presence for ICS55; the IHP130 reference remains 0x02010082/no PLL.
Presence does not advertise a working RCU control API; unsupported writes and
HAL operations remain rejected. No address/IRQ/DMA/register ABI is added.

The source lists select native Icarus IO, functional Verilator IO, or synthesis
library inputs explicitly. The unused shared 4096x32 wrapper has only its
official interface stub in Tiny simulation; the netlist audit rejects any
actual instance. Managed sources and dependency versions are unchanged.

## PLL backend verification boundary

The locked OpenECOS PLL revision is
`6ebb1a8f7f4ccbccdb7f587664fdfe63cd39e61b`. Standalone tests select the unparked
backend and use its actual behavioral view, not a pass-through stub. Selectors
5/7 configure N=32/40, SELECT=0 and OD=2 for nominal 192/240 MHz from REF24.
Other selectors disable the backend. Held APPLY is consumed once; each new
request deasserts EN for two reference cycles before restart.

Clock qualification waits 512 reference cycles, discards the first 128-cycle
window and requires four good windows. A registered 16-bit Gray count crosses
through Common's two-stage synchronizer. Expected counts are 1024/1280 with
16/20-edge tolerance. A bad window removes lock; 4096 unqualified reference
cycles exhaust the acquisition budget and require a new request. Source-domain
reset release takes five edges. The interface's lock output is a digital
activity/rate observation, not analog lock or jitter qualification.

The macro has no LOCK output; its Liberty has no timing arcs and its license
is unresolved. Ideal simulation supplies are not a physical ground/rail merge
decision. Reference loss cannot be diagnosed by a stopped reference clock;
the frozen external-reset recovery boundary remains. None of the standalone
tests qualifies CPU/main SRAM at a high rate.

## Validation sequence

Activate the existing locked development environment and use one timestamp
across commands. Run focused tests, RTL/C policy and host checks before the
full Pytest suite or product regressions. Tests requiring a model/simulator
must execute; a skip is not that gate's acceptance.

```sh
source .cache/retrosoc/development/tiny-r2-p1/activate.sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
python3 -m pytest -q tests/test_tiny_ics55_platform.py tests/test_tiny.py \
  tests/test_tiny_r2_baseline.py tests/test_tiny_r2_p2.py \
  tests/test_clock_reset_domains.py tests/test_mgmt_debug.py \
  tests/test_publication_tiny.py tests/test_commercial_flow.py::test_ics55_pll_wrapper
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 \
  rtl-format-check rtl-style-check rtl-readiness-check \
  sw-format-check sw-policy-check sw-host-test
ruff check .
python3 -m pytest -q
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke firmware
tiny_ics_root=$(make -s CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke config | awk '$1 == "VARIANT_ROOT" {print $2}')
python3 scripts/tiny_ics55_platform.py --variant-root "$tiny_ics_root" capture
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite nightly --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
python3 scripts/regress.py --root . --suite pr --soc MINI --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130
python3 scripts/tiny_ics55_platform.py --variant-root "$tiny_ics_root" report
```

Tiny PR RTL simulation enables `+tiny_jtag_smoke`: IDCODE/DTMCS, DMI halt and
resume must finish before the testbench can accept firmware TEST_STATUS.
Normal workload replay leaves JTAG untouched. Tiny always requires command
success, valid TEST_STATUS/SIM_TEST_PASS and no forbidden errors; UART or the
Mini boot-only marker is insufficient. Tiny's filtered nightly matrix matches
PR, so verify that equivalence rather than repeating identical long runs.

Replay the retained original P1 HEX using `tiny-r2-baseline-sim` under the new
profile with APP=bringup and explicit TINY_BASELINE_HEX. Each simulator executes
three cold starts; Icarus uses SOC_SIM_TIME=14400 and JOBS=3 and is polled every
30 minutes. If host timeout is exhausted, retain the failed attempt and do not
count an incomplete sample. An identical-model retry may increase only the
host budget, retaining successful cold starts and recording each run's budget;
the actual campaign recovery and its executable driver are in the ledger.
Keep the original image manifest/source/phase and binaries intact.
The P1 label identifies the measurement protocol; the new RTL/config/PDK and
outer phase record identify ICS55-P1. Historical IHP130 samples remain labeled
references, not current-source cross-PDK performance qualification.

## Netlist, STA and evidence

Yosys imports the PLL's library blackbox; it never synthesizes behavioral clock
delays. Its final Verilog and JSON are bound by hashes to a structural report:
32 4 KiB SRAM macros, one constant-disabled PLL, and CPU/SRAM clock connectivity.
The 16 KiB stub must have no instance. A modified audit script or consumed
artifact invalidates the report. Netlist configuration must match SOC/PDK,
capacity, PLL presence, 41667 ps synthesis target and the actual config digest.

OpenSTA accepts only this verified parked Tiny/ICS55 exception to the existing
PLL guard. Active PLL configurations remain unsupported. SYS remains the
41.666666667 ns primary clock at the existing buffer output, with JTAG as the
separate asynchronous domain. No active PLL generated clock is invented.
The original core-only IO/reset exceptions remain unchanged. Reports include
coverage, clocks, SYS setup/hold, SRAM input/return paths and electrical,
recovery/removal, pulse-width and minimum-period observations.

`TINY_ICS55_STA_AUDIT_PASS` means the audit ran, not timing closure. Negative
WNS/TNS and other timing violations remain failures in the report but do not
block this functional phase. Missing arcs, full-chip IO, extracted PVT, package,
power and analog qualification remain final-campaign gaps. The legacy pad
wrapper and Mini padless ECC runs do not qualify the frozen QFN64 product.

Evidence lives under `build/<profile>-<timestamp>-<config-hash>/meta/tiny-ics55-p1/`.
Capture snapshots before final synthesis/STA; a later capture cannot relabel an
older run. Archive source/generated input hashes, consumed models/libraries,
configuration, tool identities, commands/results and original binary identity.
The native report covers synthesis/STA only; functional and matched-workload
acceptance must be joined explicitly in the phase delivery index. Warning
baselines and global observe-mode metrics are not promoted or regenerated here.
