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
| `bringup` | Minimal firmware used for startup and basic SoC regression. |
| `shell` | Interactive application that adds shell services, board drivers, media, FatFs, CoreMark, and UserIP integration. |

The application manifest is loaded from `app/apps/<name>/app.mk`. It appends
`APP_SRCS` and, when necessary, `APP_INC_DIRS` to the SDK sources selected by
the central build.

Build and simulate the supported profiles from the repository root:

```sh
# Bringup firmware and Verilator simulation
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR firmware sim

# Shell firmware and Verilator simulation
make CONFIG=configs/ci/ihp130-shell.mk SIMU=VERILATOR firmware sim
```

For a firmware-only build, omit `SIMU=VERILATOR sim`.

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
