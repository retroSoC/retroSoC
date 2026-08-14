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
`apb4_if_bridge` only adapts `apb4_pure_if` to `apb4_if`, and `gpio_pad_bridge`
only exposes the pad-side subset of `gpio_if`; neither module contains state.

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
and generic-DMA modes 7/8; I2C1 uses IRQ19 and DMA modes 9/10. See
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

The single-channel WS2812 transmitter occupies RIBP address `0x10008000` and
drives GPIO2 alternate function 1. Software must configure GPIO2 for ALT1
before starting a frame. The transmitter interrupt is RIBP group bit 10 and
management-core interrupt 17. The data pin is forced low while idle, during
reset/latch time, after abort, and after underflow.

The RIBP TX FIFO is also a fixed-address target for the generic DMA engine.
DMA is an AXI4 master and receives RIBP backpressure when the FIFO
is full; the transmitter does not own a private DMA request channel. See
[ws2812.md](ip/ws2812.md) for the register and transfer contract.

I2S and DVP use dedicated 32-bit AXI4-Stream data links to DMA while retaining
RIBP for configuration and PIO fallback. Their stream selection, backpressure,
and transfer-boundary rules are defined in [axi4-stream.md](axi4-stream.md).

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

## User IP GPIO ownership

The fixed user-IP integration does not add dedicated user GPIO pads. A user IP
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
