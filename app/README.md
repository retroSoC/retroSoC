# retroSoC Applications

`app/` contains the firmware applications and the components assembled by those
applications. It builds on the freestanding SDK in [`../crt`](../crt) and keeps
application policy separate from common runtime and HAL code.

## Layout

| Path | Purpose |
| --- | --- |
| `apps/` | Selectable application profiles. Each profile owns `main.c` and an `app.mk` source manifest. |
| `board/` | Board-specific device drivers and public board headers. |
| `media/` | WAV, video, and visual-demo components with public media headers. |
| `middleware/` | Application middleware configuration and integration, including FatFs. |
| `network/` | Optional network or user-IP integration. |
| `ports/` | Ports and configuration for external libraries, such as LVGL. |
| `benchmark/` | Project integration for benchmark workloads, including CoreMark. |
| `asm/` | Standalone assembly firmware used by low-level simulation self-tests. |

Versioned third-party source trees are managed by the setup flow. Do not
reformat or treat them as ordinary application code: use their integration
directory and setup tooling when updating FatFs, CoreMark, or LVGL.

## Application Profiles

The build selects an application with `APP=<name>`. The supported profiles are:

| Profile | Description |
| --- | --- |
| `benchmark` | Fixed-workload memory and DMA baseline with machine-readable wait counters and readback checksums. |
| `bringup` | Manual startup diagnostic that prints complete application and archinfo details. |
| `ci_smoke` | Fast deterministic CI smoke test for UART, ARCHINFO V2 ABI/build identity, RNG V2 integration, SDRAM 8/16/32-bit mapped-window access, and test-status completion. |
| `coremark` | SRAM-resident Hazard3 CoreMark measurement; use the committed quick or standard profile. |
| `debug` | Minimal SRAM image used only by the Hazard3 OpenOCD/GDB acceptance flow. |
| `shell` | Interactive application that adds shell services, board drivers, media, FatFs, CoreMark, and UserIP integration. |
| `xpi_flash_loader` | SRAM-resident, GDB-called service image for sector-preserving JTAG programming of the qualified NSS0 NOR. |

The application manifest is loaded from `app/apps/<name>/app.mk`. It appends
`APP_SRCS` and, when necessary, `APP_INC_DIRS` to the SDK sources selected by
the central build.

Build and simulate the supported profiles from the repository root:

```sh
# Bringup firmware and Verilator simulation
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR firmware sim

# Explicitly run the CI smoke firmware used by regressions
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke SIMU=VERILATOR firmware sim

# Shell firmware and Verilator simulation
make CONFIG=configs/ci/ihp130-shell.mk SIMU=VERILATOR firmware sim

# IHP130/Hazard3 Verilator baseline; result is written below build/*/meta/
make CONFIG=configs/benchmark/ihp130-hazard3.mk SIMU=VERILATOR benchmark-report

# IHP130/Hazard3 fixed-workload CoreMark; result is written to meta/coremark.json
make CONFIG=configs/benchmark/ihp130-hazard3-coremark.mk SIMU=VERILATOR coremark-report

# Hazard3 remote-bitbang, OpenOCD, and GDB acceptance flow
make CONFIG=configs/ci/ihp130-debug.mk SIMU=VERILATOR debug-sim

# Build the SRAM-resident XPI NOR loader used by the host JTAG tool
make CONFIG=configs/ci/ihp130-xpi-flash-loader.mk firmware
```

For a firmware-only build, omit `SIMU=VERILATOR sim`.

The Verilator harness uses a zero-delay SDRAM protocol model so that memory
and DMA readback are checked in the fast emulator. The Icarus testbench keeps
the Micron SDRAM timing model and remains the timing-oriented behavioral flow.

## Adding an Application

1. Create `app/apps/<name>/main.c` and `app/apps/<name>/app.mk`.
2. List the application-owned sources in `APP_SRCS` and export only required
   include directories through `APP_INC_DIRS`.
3. Add `<name>` to the allowed `APP` values in the top-level `Makefile`; this
   keeps profile selection explicit and rejects misspellings.
4. Add a committed configuration profile under `configs/` that selects
   `APP := <name>` and the required ISA, CSR, and linker options.
5. Add host tests for deterministic parsing or utility code, and add a
   regression command when the application must execute in simulation.

Applications should consume public SDK headers through `<retrosoc/...>`.
Application-specific public headers belong below their own component include
directory, such as `board/include/retrosoc/board/` or
`media/include/retrosoc/media/`.

DMA users must select an explicit SDK channel. UART0 owns channel 0, I2C0
channel 1, I2C1 channel 2, and media/benchmark clients serialize on bulk
channel 3. See [DMA MVP](../docs/ip/dma.md) before adding a concurrent DMA
client.

The SD/SDIO HAL exposes `rs_sd_memory_*` for SD Memory v2 block devices and
`rs_sdio_function_*` for SDIO functions; these APIs must not be conflated.
Bring-up can run the controller ID/capability/IRQ self-test without a card.
The delivered software is limited to fixed-present 3.3 V SDR, 1/4-bit
operation, aligned SG DMA buffers, and the validated 72 MHz 24/36 MHz versus
`>=100 MHz` 50 MHz clock boundary. It makes no filesystem, hotplug,
compliance, or vendor Wi-Fi claim.

Self-owned application C/H code follows the project
[MISRA C:2012 Amendment 2 policy](../docs/misra-c-2012.md). Managed upstream
sources and exclusions listed in `quality/embedded_c_policy.json` are outside
that scope; project glue must not be presented as evidence of upstream MISRA
conformance.

## Quality Checks

Run the shared checks from the repository root before submitting changes:

```sh
make sw-format-check
make sw-policy-check
make sw-host-test
python3 -m pytest -q
```

The embedded-C checks apply to self-owned code and deliberately exclude managed
third-party source trees. Required-rule deviations need a reviewed entry in
[`quality/misra/deviations.md`](../quality/misra/deviations.md). Use the
repository regression suites for end-to-end
firmware, RTL, netlist, synthesis, and timing coverage:

```sh
make regress-pr
make regress-nightly
```

See the [repository README](../README.md) for prerequisites, supported
configurations, and build artifact locations.
