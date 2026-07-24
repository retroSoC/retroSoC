# Mini SoC Topology

`soc_topology.json` is the source of truth for internal Mini SoC integration
that is not part of the software address-map ABI or the package pad map.

The topology generator validates native NMI and APB target ownership against
`../address_map/memory_map.json` and emits generated SystemVerilog include
files for `ip_nmi_wrapper.sv`, `ip_apb_wrapper.sv`, `nmi2apb.sv`, and
`retrosoc.sv`. The output retains scalar interface instances and ports, so it
does not depend on interface-array support in FPGA or netlist simulation tools.

The `native_targets` list uses stable response slots. Every active native
memory-map region must appear exactly once. Disabled targets keep their slot
and interface declaration but cannot own an address region.

Each `gpio_alt_functions` entry defines both alternate modes for one GPIO pin.
`inputs` are driven from the selected GPIO input, and `do` and `oe` define the
peripheral output path. Values are restricted to scalar signal references and
one-bit constants so malformed expressions are rejected before RTL generation.

The `apb_targets` list defines the stable APB response slot, timed/pure APB
interface names, and corresponding active APB address-map region. A target that
declares `requires_ip: "MDD"` is generated only for `IP=MDD`; its presence is
checked against the same condition in the canonical memory map.

`irq_vector_width`, `irq_groups`, and `interrupts` define the complete core
interrupt topology. `nmi` and `apb` group entries declare the wrapper output
width and the associated `retrosoc.sv` signal. Every group bit must be present
exactly once, each core-vector bit must have one source, and sources are limited
to scalar signal references or one-bit constants. The generator emits the two
wrapper bindings, the core-vector wiring, and simulation-only assertions. Core
IRQ bits 0 through 16 retain their current compatibility mapping; additions
must use currently unallocated bits and preserve the existing entries. Bits
without an interrupt entry are driven low. Firmware does not expose a generic
external interrupt API until the SoC includes a claim/complete interrupt
controller.

`user_extensions.json` separately defines the supported scalar user-core and
user-IP slots. `generate_user_extensions.py` creates isolated default routing
and one explicit instance per selected slot for `user_core_top.sv` and
`user_ip_top.sv`. Adding an extension therefore requires a reviewed JSON entry
rather than manual edits to the SoC muxes. The module port contract remains the
existing user design template contract.

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
