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
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk check-pin-map
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk pin-map
```

When adding a pad, define its whitelisted pad template, direction, conditional
feature, and every profile binding in the JSON map. Use `null` for an open
binding. The generator rejects duplicate pad names, unknown profile bindings,
unsupported features, and unapproved connection syntax.

SoC wrappers use the existing clusterIP interfaces for protocol boundaries.
`apb4_if_bridge` only adapts `apb4_pure_if` to `apb4_if`, and `gpio_pad_bridge`
only exposes the pad-side subset of `gpio_if`; neither module contains state.
