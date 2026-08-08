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

SoC wrappers use the existing clusterIP interfaces for protocol boundaries.
`apb4_if_bridge` only adapts `apb4_pure_if` to `apb4_if`, and `gpio_pad_bridge`
only exposes the pad-side subset of `gpio_if`; neither module contains state.

## WS2812 output

The single-channel WS2812 transmitter occupies RIBP address `0x10008000` and
drives GPIO2 alternate function 1. Software must configure GPIO2 for ALT1
before starting a frame. The transmitter interrupt is RIBP group bit 10 and
management-core interrupt 17. The data pin is forced low while idle, during
reset/latch time, after abort, and after underflow.

The RIBP TX FIFO is also a fixed-address target for the generic DMA engine.
DMA remains a normal RIB master and receives RIBP backpressure when the FIFO
is full; the transmitter does not own a private DMA request channel. See
[ws2812.md](ip/ws2812.md) for the register and transfer contract.

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
selects an owner per pin with the rib GPIO `USER_SEL` register at offset
`0x30`; clear selects the existing software/alternate GPIO path and set selects
the user IP. `USER_LOCK` at `0x34` is write-one-set and prevents a selected
owner bit from changing until reset. `USER_STATUS` at `0x38` reports the user
IP pins that are actively connected.

On every accepted ownership change, the pad output enable is forced low for one
full system clock. The rib GPIO block retains `CS`, `PU`, and `PD` control
in all modes. User IPs provide only output data, output enable, and sampled pad
input. Configure the target output data and enable before writing `USER_SEL`,
then program `USER_LOCK` after the handoff when the assignment is permanent.

User-IP RTL must declare its GPIO port as `user_gpio_if.user_ip gpio`; the only
signals available through that port are `do_o`, `oe_o`, and `di_i`. The MPW
generator migrates the locked legacy examples in its isolated build output, so
they cannot drive rib GPIO electrical controls. New IP submissions must use
the `user_gpio_if` declaration directly.
