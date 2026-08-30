# RTL Design and Simulation

This directory contains retroSoC SystemVerilog RTL, CPU/IP integration,
peripheral and technology wrappers, filelists, testbench support, and the Mini
SoC build entry points.

`mini/` is the active SoC integration flow. `managed/` contains locked or
vendored integration inputs, `ip/` contains self-owned IP and experiments, and
`model/` contains committed device simulation models with preserved upstream
notices. `filelist/` selects PDK-specific RTL sources; `tech/` contains
technology wrappers. Respect managed upstream boundaries and use setup helpers
rather than editing generated MPW output.

The optional IHP130 LP/HP profile integrates VexiiRiscv through self-owned
wrappers, a 64-to-32 compatibility plane, HP ACLINT/PLIC, mailbox, UART1, and
SYSCTRL lifecycle signals. The generated CPU Verilog lives only below
`build/<variant>/generated/vexiiriscv/` and is an external lint boundary. See
[LP/HP Architecture](../docs/lp-hp-architecture.md).

RTL changes require an affected firmware build and simulation. Use
`make regress-pr` or `make regress-nightly` for supported regression coverage;
see [Engineering Workflow](../docs/engineering.md) for results and artifacts.

## Self-Owned RTL Naming

Self-owned SystemVerilog follows these signal and register naming rules. New
RTL and local changes to existing RTL must preserve them:

- Declare synthesizable data, state, and interconnect signals as `logic`.
  Reserve explicit net types for signals that require net resolution semantics.
- Use `_i` and `_o` for module ports, `s_` for internal signals, and `u_` for
  module instances.
- Name state owned by the current module `s_<name>_d` for next state and
  `s_<name>_q` for registered current state. Keep the pair adjacent in the
  declaration and connect it through a reusable register component from
  ClusterIP Common.
- Name a register write enable `s_<name>_en`. Do not add `_d` or `_q` to an
  ordinary combinational signal or to a parent-module connection simply
  because its source is registered inside a child module.
- Use `s_req`, `s_write`, `s_req_accept`, and `s_access_error` for an APB4 slave
  transaction. Name its registered response signals `s_apb4_ready_d/q`,
  `s_apb4_rdata_d/q`, and `s_apb4_resp_err_d/q`.
- Name register offsets `APB4_<IP>_<REGISTER>` and field bit positions
  `<IP>_<REGISTER>_<FIELD>`. Do not add redundant `_OFFSET`, `_LSB`, `_MASK`,
  or `_VALUE` suffixes; keep implementation-only masks and constant values as
  typed `localparam` declarations in the owning module.

Changed owned RTL is also checked for module lower snake case, `u_` instance
names, port direction suffixes, `_d/_q` state pairs, `_e/_t` typedef suffixes,
typed UpperCamelCase parameters, and namespaced macros. This staged check does
not apply mechanically to protocol fields, PDK pins, generated bindings, or
managed/third-party sources. Use compatibility wrappers for public renames.

Run `verible-verilog-format --flagfile=.verible-format` on changed RTL. Where
the formatter cannot preserve required macro or port-column alignment, use a
narrow `// verilog_format: off/on` region and align the enclosed declarations
manually.

The complete ownership-aware rules, including semantic signal grammar,
handshake/error vocabulary, module/interface/instance suffixes, parameter and
macro namespaces, FSM examples, compatibility boundaries, and migration
policy are documented in [RTL Coding Style](../docs/rtl-coding-style.md).
The behavior-preserving audit process, rule matrix, formatter-exception
requirements, and required validation are documented in
[RTL Coding Style Compliance](../docs/rtl-coding-style-compliance.md);
[`rtl_style_audit.json`](rtl_style_audit.json) records the reviewed owned
source inventory.
`make rtl-style-check` rejects new positional connections and legacy
constructs in changed self-owned RTL while the existing migration backlog is
handled separately.

The Verilator harness uses a zero-delay SDRAM protocol model because Verilator
does not elaborate the tri-state delays in the Micron model. The Icarus
testbench retains that Micron timing model, so it is the reference for SDRAM
command timing while Verilator provides fast functional coverage.

The Mini SoC on-chip SRAM is a synthesis-time selectable 4/16/32/64/128 KiB
native 32-bit AXI4 target. Product profiles select 32 KiB; ICS55 assembles it
from two 16 KiB `SRAM_4096X32_M8_BW` macros while other mappings retain their
technology-bank geometry. Its read-only
APB capability/performance ABI, technology mapping, verification evidence, and
ECC/MBIST roadmap are documented in
[Configurable Native-AXI4 On-chip SRAM](../docs/ip/onchip-sram.md).

The self-owned ESP-PSRAM64H controller exposes a 32-bit AXI4 data window and a
separate APB4 management plane across four independently isolated 8 MiB chips.
Its frozen architecture, register ABI, timing limits, model, formal target, and
verification evidence are documented in
[ESP-PSRAM64H Controller](../docs/ip/psram.md).

The prototype octal PSRAM controller reserves a separate 128 MiB AXI4 window
and supports boot-selected OPI/xSPI and single-clock HyperBus profiles through
a shared Basilisk-style digital PHY. Its protocol, CDC, delay-cell,
register-ABI, DMA, and signoff boundaries are documented in
[OPI PSRAM and Single-Clock HyperBus Controller](../docs/ip/opipsram.md).

The self-owned SPI-SD host is an APB4-managed, native 32-bit AXI4 SG-DMA
master with a single-clock mode-0 SDR PHY. Its phase, protocol, register,
descriptor, software, and verification boundaries are documented in
[SPI-SD Host Controller](../docs/ip/spisd.md).

The self-owned XPI V2 controller exposes four 64 MiB native-AXI4 windows and
an APB4 management plane. It provides a 16-by-8 command LUT, reset-time NSS0
quad-I/O NOR boot, mapped serial RAM access, indirect PIO/central-DMA commands,
automatic status polling, interrupts, and an SDR single-clock PHY. Its frozen
ABI and commercial delivery boundary are documented in
[XPI V2 Controller](../docs/ip/xpi.md).

The self-owned crypto controller provides management-only APB4 control,
central-DMA streams, AES-128/192/256 ECB/CBC/CTR, SHA-224/256, and raw
RSA-2048 Montgomery exponentiation. Its register ABI, key/zeroize boundary,
commercial survey, and verification roadmap are documented in
[AES/SHA-2/RSA Crypto Controller](../docs/ip/crypto.md).

SystemCtrl uses `sysctrl_if.sv`, `sysctrl_define.svh`, `sysctrl_reg.sv`, and
`sysctrl_core.sv` behind the stable `apb4_sysctrl` integration wrapper. Its
generated register offsets, APB4 timing, control-plane behavior, and
verification contract are documented in
[APB4 System Control](../docs/ip/sysctrl.md).

The Mini SoC APB4 platform block is `apb4_system` in `rtl/mini/top`. It owns
archinfo, RTC, watchdog, PWM, PS/2, RNG, CRC, the read-only legacy user-IP
compatibility window, and fixed EXT-L/EXT-H control windows in product mode.
`apb4_periph` remains the APB4 peripheral container. Topology generation
includes both management-only native SDIO hosts (`sdio0` on GPIO15..20 ALT0
and `sdio1` on dedicated pads), and the `soc_apb4_system_fabric.svh` include is documented in
[Mini SoC Topology](mini/integration/README.md).
