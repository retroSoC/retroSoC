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

`<retrosoc/hal/sdram.h>` provides cycle-count timing calculation, configuration,
initialization/reinitialization, precharge-all, refresh, status, interrupt
helpers, and a bounded self-test for the 64 MiB AXI4 SDRAM controller. See the
[controller contract](../docs/ip/sdram.md). Applications include this header
rather than `soc.h` register macros. The booter only prints the SDRAM window;
it does not force a software reinit.

`<retrosoc/hal/psram.h>` provides timing calculation, configuration,
initialization, per-chip recovery, status/ID, restricted indirect commands,
interrupts, and bounded self-test for the four-chip ESP-PSRAM64H controller.
See the [controller contract](../docs/ip/psram.md) before using its destructive
self-test or changing the memory timing.

`<retrosoc/hal/sysctrl.h>` owns typed access to SystemCtrl legacy compatibility,
PLL/clock, memory-pad, fault, performance, RTC-wake, and terminal-test functions. Existing
clock, user-core, performance, and test-service APIs use this HAL; direct
`reg_sysctrl_*` register macros are not public SDK interfaces. See the
[SystemCtrl contract](../docs/ip/sysctrl.md).

`<retrosoc/hal/extension.h>` owns product EXT-L/EXT-H discovery, lifecycle,
ownership, status, and ACL operations. `<retrosoc/hal/user_ip.h>` remains the
MPW compatibility API; selector mutators return `RS_ENOTSUP` in product builds.
See the [extension contract](../docs/ip/extensions.md) and
[legacy user-IP contract](../docs/ip/user-ip.md).

`<retrosoc/hal/memory.h>` provides the uniform Mini memory inventory for
SRAM, SDRAM, QPI PSRAM, OPI/HyperBus PSRAM, and XPI. It reports the fixed
window, device/initialization/ready/active state, shared-pad mode, DMA and
cache visibility, and the controller fault summary by composing the existing
per-controller HALs. It does not merge heterogeneous memories into one
allocator or provide hardware cache coherency.

`<retrosoc/hal/dma.h>` provides the channel-aware direct and linked-list DMA
API. UART0, I2C0, I2C1, bulk/media clients, and the HP boot loader have
deterministic channel assignments; see the [DMA V2 contract](../docs/ip/dma.md).
The SDK accepts aligned 32-bit transfers, partial final beats for MM-to-MM,
and 64-byte aligned TCD chains.

`<retrosoc/hal/crypto.h>` provides bounded AES PIO/DMA, SHA-224/256, raw
RSA-2048 modular exponentiation, zeroize, and known-answer self-test APIs.
AES DMA reserves channels 4/5; private RSA input is write-only at the APB
boundary and assumes public exponent 65537 for result verification. See the
[crypto controller contract](../docs/ip/crypto.md) before handling production
keys or composing an RFC 8017 scheme.

`<retrosoc/hal/sdio.h>` provides separate low-level native SD host,
SD Memory v2, and SDIO function APIs for `sdio0` and `sdio1`. The controller
scope is fixed-present 3.3 V SDR at 1/4-bit width; it does not claim SD
Association compliance or a vendor Wi-Fi driver. The 72 MHz SoC profiles use
the validated 24/36 MHz operating range, while a 50 MHz SD clock requires a
separately validated `clk_i >= 100 MHz` environment. SG DMA descriptors and
their buffers must be 16-byte/32-bit aligned as applicable; callers must use a
bounce buffer for an unaligned head. PIO and DMA use little-endian byte lanes:
bits `[7:0]`/strobe lane 0 is the first wire byte, and `DATA_START` is the
coordinated DMA/card-data launch. The SDK does not provide hotplug,
filesystem, combo-card, UHS, DDR, or 1.8 V support.

`<retrosoc/hal/usb2.h>` provides the ULPI USB 2.0 controller primitives for
role configuration, eight bidirectional device endpoints, sixteen host
channels, interrupts, USB3320 register viewport access, and 32-byte AXI4
scatter-gather descriptors. The register ABI is mirrored by hand in
`<retrosoc/hal/usb2_regs.h>` and checked against RTL without a register
generator. This layer is a DCD/HCD foundation; enumeration, class, hub, cache
maintenance, and USB-IF compliance remain integration responsibilities. See
the [USB2 controller contract](../docs/ip/usb2.md).

`<retrosoc/hal/spisd.h>` provides the separate SPI-mode SD Memory host API.
It supports bounded SDSC/SDHC enumeration, PIO and native-AXI SG-DMA sector
transfers, interrupt/error handling, CSD geometry, and an explicit verified
CMD6 high-speed switch. Its descriptor/buffer alignment and retired-aperture
compatibility behavior are defined in the
[SPI-SD controller contract](../docs/ip/spisd.md).

`<retrosoc/hal/xpi.h>` and `<retrosoc/hal/xpi_regs.h>` provide the typed XPI V2
HAL and its manually maintained register ABI. The API covers four mapped
slots, LUT programming, PIO and central-DMA indirect transfers, hardware
polling, interrupts, errors, performance counters, and configuration locks.
Reset-time NSS0 boot behavior and JTAG NOR programming are defined in the
[XPI V2 controller contract](../docs/ip/xpi.md).

`crt/inc/` is legacy or generated compatibility material. It is not an active
public include root for the firmware build; new code must not add dependencies
on it.

## Build Integration

The central software build assembles the runtime sources in
[`../rtl/mini/mk/software.mk`](../rtl/mini/mk/software.mk). It selects the
RISC-V ISA, optional CSR interrupt support, linker layout, and the application
profile. Applications add their own sources after the common runtime is
selected.

`<retrosoc/service/test.h>` provides `rs_test_finish()`, the terminal-result
service used by automated firmware. It writes the sticky SYSCTRL test-status
register and does not return. It is for finite regression applications, not
interactive firmware such as the shell.

Start from a committed configuration profile:

```sh
make CONFIG=configs/ci/ihp130.mk setup
make CONFIG=configs/ci/ihp130.mk firmware
```

The resulting firmware and generated headers are isolated under
`build/<profile>-<config-hash>/sw/`. Do not commit build outputs.

## API and Contribution Rules

- Self-owned C/H code in `crt/` follows the project
  [MISRA C:2012 Amendment 2 policy](../docs/misra-c-2012.md). Assembly,
  linker scripts, compatibility material, and excluded paths are outside that
  C-language scope.
- Keep public interfaces in the matching `include/retrosoc/<layer>/` directory
  and implementations in the corresponding `src/<layer>/` directory.
- Use the `rs_` API namespace and `rs_status_t` for operations that can fail.
- Keep the runtime freestanding: do not add hosted-library, dynamic-allocation,
  or operating-system dependencies.
- Prefer bounded APIs such as `rs_strlcpy`, `rs_strlcat`, `rs_snprintf`, and
  timeout-based register waits over unbounded operations.
- Add deterministic host tests when new code does not require real registers,
  timing, or board hardware.

Required-rule deviations need a reviewed entry in
[`quality/misra/deviations.md`](../quality/misra/deviations.md). Existing
automation is partial enforcement; it is not a claim of complete MISRA
certification.

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
