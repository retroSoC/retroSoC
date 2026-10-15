# Tiny R2-P8 XPI PSRAM transport

This phase implements optional NSS1 framebuffer storage through shared XPI V2.
It does not add a PSRAM controller, external boot dependency, DVP integration
or physical rate qualification. P7 was explicitly accepted by the maintainer
on 2026-10-15 at `655c587`; its retained physical and final-Icarus gaps remain.

## Implementation and ownership

`crt/include/retrosoc/hal/xpi_psram.h` and the corresponding shared HAL sources
own the ESP-PSRAM64H reference profile. The caller owns XPI exclusively, runs
code and interrupt paths from SRAM, selects GPIO29 ALT0 and provides external
inactive-high NSS1 bias. No startup path initializes or allocates external RAM.
The helper reserves slot 1 and LUT sequences 8..11 without changing NSS0 or
LUT 0. SPI reset/identification checks manufacturer `0d`, KGD `5d` and density
`26`, then enters QPI. Three ID bytes are sufficient to identify the selected
geometry; extended ID bytes are not advertised as read. Reinitialization exits
QPI first, including when the device survived a controller/system reset.

Mapped access is enabled only after identification succeeds. The actual
capacity is 8 MiB (`0x54000000..0x547fffff`); the 64 MiB slot aperture is not
usable capacity. Missing/unrecognized devices return `RS_ENOTSUP`, with mapped
NSS1 disabled and NOR access restored when bounded cleanup succeeds. A cleanup
timeout remains a failure requiring coordinated recovery. A clock change or
reset invalidates the software session: quiesce all users and initialize again
before exposing buffers. No helper owns a DMA channel implicitly.

MEM24/48/96/120 use SCK=MEM/2, six quad-read dummy clocks, at least 3 ns setup,
20 ns hold and 50 ns inactive CS. The core timeout leaves two MEM cycles below
the model's 8 us active-CS limit. Direct DMA uses SOFTWARE requests, aligned
32-bit words and at most four-beat bursts. Align a four-beat job to 16 bytes;
the unchanged DMA splits at 4 KiB and these bursts cannot cross the configured
1 KiB serial boundary. This deliberately bounded starting profile is not a
maximum-throughput or physical-device claim.

Shared `xpi_mm` fixes preserve the register ABI: correct byte-lane masks and
narrow-burst collection addresses, reject configured serial-boundary crossings,
retire writes when the serial core terminates before all payload, preserve
presented read responses across timeout, reject short sequences, and wait for
physical-command completion before exposing the command's final read beat.
Failures were reproduced before these changes; their logs remain retained.

The reference device model moved from Mini verification into
`rtl/model/ESP_PSRAM64H.sv`, retaining model behavior and parameters. Mini
filelists and its separate-controller tests consume the same shared model;
their results remain compatibility evidence, not Tiny XPI acceptance.

## Workloads and verdicts

`TINY_P8_ACCEPTANCE=YES APP=ci_smoke` selects the SRAM-resident P8 image and a
distinct configuration digest. It is mutually exclusive with P7 acceptance.
The model is populated only with `+tiny_p8_psram`; `+p8_absent` disconnects it.
The ordinary baseline does not depend on its presence.

Each supported functional clock profile initializes through actual XPI pins,
checks CPU byte/halfword/word access and first/last physical addresses, then
writes 1024 deterministic bytes from SRAM through leased DMA3 into
`0x54000c00`. The range ends exactly at a 1 KiB serial and 4 KiB page
boundary; crossing cases are rejected by the HAL and focused tests. CPU and DMA independently read back every word; adjacent
canaries must remain unchanged. A second round overlaps independent CPU SRAM
work and records its progress. Firmware returns to SAFE24 and checks NOR
readback. This finite transport workload is not a camera frame or P9 capture
qualification.

Firmware records elapsed SYS cycles from DMA start through observed completion,
payload bytes and CPU progress. `tiny_p8_observers.svh` independently records
MEM-clock window length, mapped byte counts, and maximum consecutive
VALID-without-READY cycles for all five AXI channels. These are verification
observations, not new hardware registers. Payload rate is bytes times clock
rate divided by elapsed cycles; stall time is observed MEM cycles divided by
MEM rate. Software/setup/polling costs and observation-window boundaries must
remain visible when interpreting the numbers. They are not unrestricted
worst-case bounds or proof of a safe camera input rate.

Both simulators must succeed with SYSCTRL TEST_STATUS / `SIM_TEST_PASS` and
without forbidden markers. `scripts/tiny_r2_p8.py` rejects missing profile or
measurement rows, partial byte counts and zero CPU progress. Optional absence
has a separate verdict and cannot qualify populated-device transport. The
report captures source/runtime inputs, locked tools, firmware and simulator
binaries; historical or changed-input runs cannot be promoted as fresh results.

## Execution

Activate the locked local environment when available. Start with focused tests
and SDK/style/policy checks, then the explicitly selected committed profile:

```sh
python3 -m pytest -q tests/test_tiny_r2_p8.py tests/test_tiny_r2_p8_evidence.py
make sw-format-check sw-policy-check sw-host-test
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk ICS55 --dry-run
python3 scripts/regress.py --root . --suite pr --soc TINY --pdk IHP130 --dry-run
make CONFIG=configs/ci/ics55-tiny.mk SOC=TINY PDK=ICS55 APP=ci_smoke \
  TINY_P8_ACCEPTANCE=YES BUILD_TIMESTAMP=2026-10-15-05-00 firmware comp
```

Build Icarus with the same profile, timestamp and software settings using
`SIMU=IVERILOG comp`, and reuse the retained HEX. Before each final replay,
capture inputs with `scripts/tiny_r2_p8.py capture --variant-root <variant>
--simulator <simulator> --output <attempt>/source.json`. Run the selected
binary through `scripts/run_flow.py` with `<attempt>/sim.log` and
`<attempt>/result-sim.json`, explicit firmware path, `+tiny_p8_psram` and the
recorded cycle/time budget. Report with `scripts/tiny_r2_p8.py report` using
the same source, variant, simulator and attempt. Use a separate attempt and
`--absent` for the absent-device case; never overwrite prior evidence.

Repeat affected checks for explicit IHP130 compatibility and the committed
XIN48/XIN96 profiles. Default ICS55 covers SAFE24/PLL192/PLL240 functional
profiles in one image. Synthesis, macro binding, netlist function and
observational STA remain required; full long-running Icarus peripheral
firmware and physical/board qualification remain in the final campaign.
Consult the verification ledger for actual passed/failed/unrun gates; these
commands are not themselves evidence of completion.
