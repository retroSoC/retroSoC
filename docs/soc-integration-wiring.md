# SoC Integration Wiring

`rtl/mini/pin_map/pin_map.json` is the single source for the Mini SoC logical
pad ABI and its ASIC, FPGA, Verilator, and RTL-testbench bindings. It does not
contain board package locations; FPGA package constraints remain in the board
`.xdc` file.

The generator emits temporary SystemVerilog include files below
`build/<variant>/generated/pin_map/`. The ASIC top includes the generated port
and pad bindings, while each platform wrapper includes its own generated
named-port binding. Do not edit generated files.

Use the following commands after editing the map:

```sh
make CONFIG=configs/ci/ihp130.mk check-pin-map
make CONFIG=configs/ci/ihp130.mk pin-map
```

When adding a pad, define its whitelisted pad template, direction, conditional
feature, and every profile binding in the JSON map. Use `null` for an open
binding. The generator rejects duplicate pad names, unknown profile bindings,
unsupported features, and unapproved connection syntax.

SoC wrappers use the existing clusterIP interfaces for protocol boundaries,
except for the self-owned UART0 `uart_if` under `rtl/ip/serial`.
`apb4_system` is the APB4 platform subsystem (`u_apb4_system`); it is not a
protocol bridge. `apb4_if_bridge` only adapts `apb4_pure_if` to `apb4_if`, and
`gpio_pad_bridge` only exposes the pad-side subset of `gpio_if`; neither
adapter contains state.

## Root clock pads

`extclk_i_pad` is the 72 MHz HP safe/bypass source. `ref24clk_i_pad` is the
independent, always-present 24 MHz AON and PLL-reference input. It replaces the
conditional `XI/XO` pad pair. `audclk_i_pad` remains the independent audio
functional clock. Simulation wrappers drive REF24 separately; the current FPGA
wrapper aliases it to the board system clock and therefore does not validate
the independent-clock physical contract.

## UART flow-control alternate functions

UART0 keeps dedicated RX and TX package pads. Optional active-low hardware flow
control uses GPIO0 ALT0 for the CTS input and GPIO1 ALT0 for the RTS output.
The UART owns synchronization and fail-safe CTS behavior; GPIO supplies only
the pad mux and resolved pad input. GPIO0/1 ALT1 remains assigned to the PS/2
clock/data pair, so software cannot use PS/2 and UART0 flow control on the same
pins simultaneously.

`rs_uart_configure()` selects each ALT0 route when the corresponding automatic
flow-control function is enabled. Disabling UART flow control does not reclaim
the GPIO pin. Software must explicitly choose a new GPIO mode before assigning
that physical pad to another function. See [uart.md](ip/uart.md) for the UART
register and timing contract.

## I2C alternate functions

The two I2C controllers reuse GPIO pads rather than dedicated package pins.
I2C0 uses GPIO7 for SCL and GPIO8 for SDA on ALT0. I2C1 uses GPIO3 for SCL and
GPIO4 for SDA on ALT1. Both controller outputs are constant zero; the GPIO
alternate-function output enable pulls a line low and releases it for high.
Board-level pull-ups are therefore required. I2C0 uses management-core IRQ7
and DMA request selectors `I2C0_TX`/`I2C0_RX` on channel 1; I2C1 uses IRQ19
and `I2C1_TX`/`I2C1_RX` on channel 2. See
[i2c.md](ip/i2c.md) for the register and transfer contract.

## PWM alternate functions

The APB PWM controller drives GPIO3 through GPIO6 on ALT0. Both output data
and output enable come from the PWM interface, so a fault-configured high-Z
state reaches the GPIO pad bridge instead of being overridden by a constant
enable. PWM uses management-core IRQ11.

GPIO2 ALT0 feeds the external synchronization input. GPIO9 ALT0 feeds the
asynchronous fault input. GPIO30 and GPIO31 ALT1 feed capture channels 0 and 1.
Software must select the corresponding alternate function and input mode before
relying on these paths. GPIO9 fault shutdown includes an immediate asynchronous
safe-state path plus synchronized filtering/status inside the IP; technology
sign-off must verify external pulse width and pad-disable latency. The complete
programming, safety, and verification contract is in the managed
[PWM V2 datasheet](../rtl/managed/clusterip/pwm/doc/datasheet.md).

## WS2812 output

The single-channel WS2812 transmitter occupies APB4 address `0x10008000` and
drives GPIO2 alternate function 1. Software must configure GPIO2 for ALT1
before starting a frame. The transmitter interrupt is APB4 group bit 10 and
management-core interrupt 17. The data pin is forced low while idle, during
reset/latch time, after abort, and after underflow.

The APB4 TX FIFO is also a fixed-address target for the generic DMA engine.
DMA is a native AXI4 master and receives APB4/FIFO backpressure when the FIFO
is full; it emits a one-beat `FIXED` transaction for this endpoint and the
transmitter does not own a private DMA request channel. See
[ws2812.md](ip/ws2812.md) and [DMA MVP](ip/dma.md) for the register and
transfer contracts.

I2S and DVP use dedicated 32-bit AXI4-Stream data links to DMA while retaining
APB4 for configuration and PIO fallback. DMA aggregate done/error/half events
use APB4-peripheral group bit 14 and management-core IRQ20. Their stream
selection, backpressure, and transfer-boundary rules are defined in
[axi4-stream.md](axi4-stream.md).

## JPEG codec integration

The Baseline JPEG codec occupies APB4 slot 26 at `0x1001a000`. It owns a
private 64-bit AXI4 master rather than consuming central-DMA channels. The
master is index 6 in the generated data-plane policy and crosses from PCLK to
the HP fabric through `u_jpeg_cdc`; its buffers must be non-cacheable/shared or
covered by the Resource Controller cache-maintenance handoff.

JPEG is resource index 6. Its LP interrupt is APB4-peripheral group bit 22 and
management-core IRQ30; HP ownership routes the raw source to PLIC source 9.
Quiesce blocks new direct/ring jobs, resource reset aborts the codec, and idle
is acknowledged only after both AXI channels drain. The APB4/raster/ring ABI
and performance boundary are defined in [jpeg.md](ip/jpeg.md).

## OPI PSRAM alternate functions

The octal PSRAM controller uses GPIO21-31 ALT0 for CK, CS#, DQ[7:0], and
RWDS/DQS. Its APB4 management window is `0x10010000`; bulk traffic uses the
separate AXI4 window at `0x48000000-0x4fffffff`. The controller interrupt is
allocated by `soc_topology.json`. Central DMA reaches the same AXI4 window as
an ordinary MM-to-MM source or destination; the controller has no private DMA
request channel.

Product integration instantiates QPI and OPI controllers together and places
`memory_pad_mux` between both PHY interfaces and GPIO21-31. AON reset selects
QPI; `MEM_PAD_CTRL` can select and lock the boot-time mode. The inactive side
holds clock/chip-select/output-enable safe and its AXI aperture returns
`SLVERR`. The exported stable memory root is 36 MHz, while completing the
controller-engine migration to that root remains a documented implementation
boundary. The pin group
does not route CK# or a dedicated device reset. Software must select all
eleven ALT0 functions before initialization, and a board must satisfy the
selected device's reset and single-ended-clock requirements. See
[opipsram.md](ip/opipsram.md) for the protocol, delay-cell, and signoff
boundaries.

## Management JTAG

The fixed Hazard3 management core always exposes five ASIC pads:
`jtag_tck_i_pad`, `jtag_tms_i_pad`, `jtag_tdi_i_pad`, `jtag_trst_n_i_pad`, and
`jtag_tdo_o_pad`. The default DTM ID code is `0xDEADBEEF` and can be changed
with the eight-hex-digit `JTAG_IDCODE` Make variable.

The JTAG TCK is an asynchronous clock domain. The canonical clock/reset map
declares a 10 MHz TCK constraint and an asynchronous DMI crossing into the
system clock domain through Hazard3's APB async bridge. FPGA and RTL-testbench
profiles tie the JTAG inputs inactive. The Verilator wrapper exposes
them to the local remote-bitbang server used by the debug acceptance flow.

## MPW user-IP GPIO ownership

This section applies to `MINI_MODE=MPW`. Product EXT-L/EXT-H slots do not add
dedicated user GPIO pads in the current manifest. An MPW user IP
can instead drive any of the 32 rib GPIO pads through `user_gpio_if`. Software
selects an owner per pin with `USER_SELECT` at management-window offset
`0x03C`; clear selects the existing software/alternate GPIO path and set
selects the user IP. `USER_LOCK` at `0x040` is write-one-set and prevents a
selected owner bit from changing until reset. `USER_STATUS` at `0x044` reports
the user-IP pins that are actively connected.

On every accepted ownership change, the pad output enable is forced low for one
full system clock. The GPIO block retains input-mode, pull, open-drain, filter,
and interrupt control in all modes. User IPs provide only output data, output
enable, and synchronized/filtered pad input. Configure the target output data
and enable before writing `USER_SELECT`, then program `USER_LOCK` after the
handoff when the assignment is permanent.

The user core accesses only the data and interrupt window at `0x10000000`, and
only bits permitted by management `USER_ACCESS_MASK`. Configuration remains in
the management-only window at `0x10014000`; the SoC access firewall denies user
transactions to that region. See [gpio.md](ip/gpio.md) for the complete ABI,
PDK capabilities, and lock semantics.

User-IP RTL must declare its GPIO port as `user_gpio_if.user_ip gpio`; the only
signals available through that port are `do_o`, `oe_o`, and `di_i`. The MPW
generator migrates the locked legacy examples in its isolated build output, so
they cannot drive rib GPIO electrical controls. New IP submissions must use
the `user_gpio_if` declaration directly.
