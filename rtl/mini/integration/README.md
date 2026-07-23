# Mini SoC Topology

`soc_topology.json` is the source of truth for internal Mini SoC integration
that is not part of the software address-map ABI or the package pad map.

The topology generator validates the native NMI target ownership against
`../address_map/memory_map.json` and emits generated SystemVerilog include
files for `ip_nmi_wrapper.sv` and `retrosoc.sv`.

The `native_targets` list uses stable response slots. Every active native
memory-map region must appear exactly once. Disabled targets keep their slot
and interface declaration but cannot own an address region.

Each `gpio_alt_functions` entry defines both alternate modes for one GPIO pin.
`inputs` are driven from the selected GPIO input, and `do` and `oe` define the
peripheral output path. Values are restricted to scalar signal references and
one-bit constants so malformed expressions are rejected before RTL generation.

Use these commands to validate or generate the selected build artifacts:

```sh
make check-soc-topology
make soc-topology
```

Generated files are written under `build/<variant>/generated/soc_topology/` and
must not be committed.
