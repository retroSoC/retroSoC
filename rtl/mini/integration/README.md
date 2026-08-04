# Mini SoC Topology

`soc_topology.json` is the source of truth for internal Mini SoC integration
that is not part of the software address-map ABI or the package pad map.

The topology generator validates rib RIB and APB target ownership against
`../address_map/memory_map.json` and emits generated SystemVerilog include
files for `ip_ribp_wrapper.sv`, `ip_apb_wrapper.sv`, `ribp2apb.sv`, and
`retrosoc.sv`. The output retains scalar interface instances and ports, so it
does not depend on interface-array support in FPGA or netlist simulation tools.

The `ribp_targets` list uses stable response slots. Every active RIBP
memory-map region must appear exactly once. Disabled targets keep their slot
and interface declaration but cannot own an address region.

Each `gpio_alt_functions` entry defines both alternate modes for one GPIO pin.
`inputs` are driven from the selected GPIO input, and `do` and `oe` define the
peripheral output path. Values are restricted to scalar signal references and
one-bit constants so malformed expressions are rejected before RTL generation.

The `apb_targets` list defines the stable APB response slot, timed/pure APB
interface names, and corresponding active APB address-map region. The user-IP
target is part of the fixed platform integration and its presence is checked
against the canonical memory map.

`irq_vector_width`, `irq_groups`, and `interrupts` define the complete core
interrupt topology. `rib` and `apb` group entries declare the wrapper output
width and the associated `retrosoc.sv` signal. Every group bit must be present
exactly once, each core-vector bit must have one source, and sources are limited
to scalar signal references or one-bit constants. The generator emits the two
wrapper bindings, the core-vector wiring, and simulation-only assertions. Core
IRQ bits 0 through 16 retain their current compatibility mapping; additions
must use currently unallocated bits and preserve the existing entries. Bits
without an interrupt entry are driven low. Firmware does not expose a generic
external interrupt API until the SoC includes a claim/complete interrupt
controller.

`user_extensions.json` defines the SoC-level user-core and user-IP slots.
The locked mini-ver-mpw `mpw.toml` remains the source of truth for enabled
design IDs, module names, slots, and reset type. `scripts/generate_mpw.py`
verifies that both descriptions agree before RTL generation.
`generate_user_extensions.py` then creates isolated default routing and one
explicit instance per selected slot for `user_core_top.sv` and `user_ip_top.sv`.
User cores use `ribp_if.master ribp`; user IPs use `user_gpio_if.user_ip gpio`
and APB4. This prevents legacy RIB/NMI and electrical pad-control contracts
from entering the SoC muxes.

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
