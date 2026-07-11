# retroSoC Runtime and SDK

`crt/` contains the freestanding RISC-V runtime and software development kit
used by every retroSoC firmware image. It provides startup code, linker
layouts, public SoC interfaces, hardware abstraction layers, and small runtime
services. It does not provide an application entry point; applications live in
[`../app`](../app).

## Layout

| Path | Purpose |
| --- | --- |
| `arch/riscv/` | RISC-V startup, interrupt assembly, compiler runtime helpers, and architecture-specific support. |
| `include/retrosoc/core/` | Public status, SoC, architecture, interrupt, and bounded-wait interfaces. |
| `include/retrosoc/hal/` | Public memory-mapped peripheral interfaces. |
| `include/retrosoc/lib/` | Freestanding console, formatting, string, and conversion interfaces. |
| `include/retrosoc/service/` | Public boot, shell, and benchmark service interfaces. |
| `src/core/`, `src/hal/`, `src/lib/`, `src/service/` | Implementations grouped by the same ownership boundary as the public headers. |
| `linker/` | Supported linker layouts, selected through `LINK_TYPE`. |

The active public include root is `crt/include`. Include SDK headers through
the `retrosoc` namespace, for example:

```c
#include <retrosoc/core/status.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
```

`crt/inc/` is legacy or generated compatibility material. It is not an active
public include root for the firmware build; new code must not add dependencies
on it.

## Build Integration

The central software build assembles the runtime sources in
[`../rtl/mini/mk/software.mk`](../rtl/mini/mk/software.mk). It selects the
RISC-V ISA, optional CSR interrupt support, linker layout, and the application
profile. Applications add their own sources after the common runtime is
selected.

Start from a committed configuration profile:

```sh
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk setup
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk firmware
```

The resulting firmware and generated headers are isolated under
`build/<profile>-<config-hash>/sw/`. Do not commit build outputs.

## API and Contribution Rules

- Keep public interfaces in the matching `include/retrosoc/<layer>/` directory
  and implementations in the corresponding `src/<layer>/` directory.
- Use the `rs_` API namespace and `rs_status_t` for operations that can fail.
- Keep the runtime freestanding: do not add hosted-library, dynamic-allocation,
  or operating-system dependencies.
- Prefer bounded APIs such as `rs_strlcpy`, `rs_strlcat`, `rs_snprintf`, and
  timeout-based register waits over unbounded operations.
- Add deterministic host tests when new code does not require real registers,
  timing, or board hardware.

## Quality Checks

Run the SDK checks from the repository root:

```sh
make sw-format-check
make sw-policy-check
make sw-host-test
```

`sw-format-check` requires the project formatter version (`clang-format-14` in
CI). `sw-policy-check` enforces the self-owned embedded-C naming and unsafe API
policy. `sw-host-test` compiles deterministic runtime, parser, and compiler
helper tests with a host C compiler; it does not replace RTL simulation or
hardware validation.

For the complete firmware, simulation, synthesis, and timing flow, see the
[repository README](../README.md).
