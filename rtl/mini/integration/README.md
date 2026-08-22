# Mini SoC Topology

`soc_topology.json` is the source of truth for internal Mini SoC integration
that is not part of the software address-map ABI or the package pad map.

The topology generator validates APB4 island ownership against
`../address_map/memory_map.json` and emits generated SystemVerilog include
files for `apb4_periph.sv`, `apb4_system.sv`, `axi42apb4_periph.sv`,
`axi42apb4_system.sv`, and `retrosoc.sv`. The two APB4 islands share one
decoder template. `apb4_system` is instantiated as `u_apb4_system`; its AXI4
configuration port is wired by generated `apb4_system_fabric.svh`.
`apb4_periph` remains the self-owned APB4 peripheral container. Generated
fabric links are explicit 32-bit AXI4 interfaces; `mgmt`, `user`, `dma`,
`sdio0`, `sdio1`, and `usb2` are generated native AXI4 links, while `cfg` and
`system` are target-side links.
Interface arrays are confined to the AXI4 bus implementation and flattened by
the existing synthesis/export flow before FPGA or netlist simulation.

The `apb4_periph_targets` list uses stable response slots for the former
RIBP island at `0x1000_0000`. Every active `apb4_periph` memory-map region
must appear exactly once. Disabled targets keep their slot and interface
declaration but cannot own an address region. This list stays separate from
`apb4_system_targets`, which owns the `0x2000_0000` `apb4_system` island.
Slot 15 is the active SDIO0 management window; SDIO1 is appended at slot 18,
the management-only crypto controller at slot 19, and USB2 at slot 20, so the
existing slots 0..17 remain stable.

Each `gpio_alt_functions` entry defines both alternate modes for one GPIO pin.
`inputs` are driven from the selected GPIO input, and `do` and `oe` define the
peripheral output path. Values are restricted to scalar signal references and
one-bit constants so malformed expressions are rejected before RTL generation.

The `apb4_system_targets` list defines the stable APB4 response slot,
timed/pure APB4 interface names, and corresponding active `apb4_system`
address-map region. Slots are contiguous from zero. The user-IP target is
part of the fixed platform integration and its presence is checked against
the canonical memory map.

`irq_vector_width`, `irq_groups`, and `interrupts` define the complete core
interrupt topology. `apb4_periph` and `apb4_system` group entries declare the
wrapper output width and the associated `retrosoc.sv` signal. Every group bit must be present
exactly once, each core-vector bit must have one source, and sources are limited
to scalar signal references or one-bit constants. The generator emits the two
wrapper bindings, the core-vector wiring, and simulation-only assertions.
Existing allocated core IRQ bits retain their compatibility mapping; additions
must use currently unallocated bits and preserve the existing entries. SDIO0
and SDIO1 use APB4 group bits 16 and 17 and core bits 10 and 21. Crypto uses
APB4 group bit 18 and core bit 23. USB2 uses APB4 group bit 19 and core bit 24.
All four remain management-only in the
generated user IRQ mask. Removing a source leaves its
core IRQ bit unallocated and driven low. Firmware does not
expose a generic external interrupt API until the SoC includes a claim/complete
interrupt controller.

`user_extensions.json` defines the active SoC-level user-core and user-IP
design IDs, slots, module names, and reset types. The locked mini-ver-mpw
`mpw.toml` remains the source of truth for available design metadata and source
locations. `scripts/generate_mpw.py` selects and renumbers the configured
designs, then verifies the generated manifest before RTL generation.
`generate_user_extensions.py` then creates isolated default routing and one
explicit instance per selected slot for `user_core_top.sv` and `user_ip_top.sv`.
User cores keep `ribp_if.master ribp` at the extension ABI and are converted to
AXI4 after selection; user IPs use `user_gpio_if.user_ip gpio` and APB4. This
prevents system-fabric and electrical pad-control contracts from entering the
extension muxes.

`clock_reset_domains.json` is the checked inventory of root clock domains,
reset synchronizers, and RCU PLL control crossings. It records the primitive,
source file, and instance name so an RTL refactor cannot silently remove the
declared reset or CDC structure. It complements, but does not replace, a
signoff CDC/RDC analysis tool.

Use these commands to validate or generate the selected build artifacts:

```sh
make check-soc-topology
make soc-topology
make check-user-extensions
make user-extensions
make check-clock-reset-domains
```

Generated files are written under `build/<variant>/generated/soc_topology/` and
`build/<variant>/generated/user_extensions/`; they must not be committed.
