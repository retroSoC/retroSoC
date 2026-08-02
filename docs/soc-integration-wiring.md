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
