# retroSoC RTL Coding Style

This document is the source of truth for self-owned RTL coding and formatting.
It follows the restricted SystemVerilog guidance used by
[lowRISC](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md)
and the staged lint, assertion, CDC, and delivery methodology described by
[OpenTitan](https://opentitan.org/earlgrey_1.0.0/book/doc/contributing/hw/methodology.html).
Repository-specific rules in this document take precedence where conventions
differ: retroSoC uses `clk_i` and `rst_n_i`, not `rst_ni`.

## 1. Scope and rule levels

The owned profile applies to `rtl/ip/**` and `rtl/mini/top/**`. Formal,
device-model, PDK, generated, managed, and third-party sources use the profiles
declared in [`rtl/rtl_style_manifest.json`](../rtl/rtl_style_manifest.json).

The following terms are normative:

- **MUST** and **MUST NOT** are blocking requirements.
- **SHOULD** and **SHOULD NOT** require review when not followed.
- **MAY** is optional when the interface and tool flow support it.

Style exceptions MUST be narrow, documented beside the code, and represented by
a reviewed waiver when the checker supports one. A waiver records the reason,
owner, affected path, related issue or commit, and an expiry or removal plan.

## 2. File and module boundaries

- Use SystemVerilog-2017 for owned RTL and tests, subject to the prohibited
  constructs in this document.
- `.sv` files are compilation units. `.svh` files are include-only headers.
- A self-owned `.sv` file contains one primary module or one related package;
  the file name and primary module name match in lower snake case.
- Do not combine unrelated modules to avoid filelist or dependency work.
- Do not edit `rtl/managed`, generated MPW output, vendored CPU sources, or
  PDK cell definitions under the owned profile. Update those through their
  locked setup flow.

## 3. Restricted SystemVerilog subset

Synthesizable owned RTL MUST NOT use:

- `#delay`, including `#0`, task declarations, or simulator timing controls;
- implicit nets, `defparam`, positional parameter or port connections, or `.*`;
- hierarchical references to implementation signals;
- `casex`, `full_case`, or `parallel_case` pragmas;
- `initial` blocks for synthesizable state.

Use `unique case` when uniqueness is part of the design contract and always
provide a `default` branch. Use `case`, `case inside`, or `casez` only when the
wildcard behavior is intentional; never use `casex` in owned RTL.

Synthesizable functions MUST be `automatic`, use explicitly typed arguments and
return values, and only consume inputs to produce one result. Tasks are
reserved for verification code.

## 4. Naming, types, and packages

Use `lower_snake_case` for signals, ports, instances, functions, and modules.
Use `clk_i`, `rst_n_i`, `_i`, `_o`, and `_io` for ports; `s_` for local signals;
`u_` for instances; and adjacent `s_<name>_d`/`s_<name>_q` for state. A state
write enable is `s_<name>_en`.

The staged naming contract is checked for changed owned RTL by
`rtl-style-check`. It is intentionally stricter for new code than the
historical baseline:

| Object | Required form | Example |
| --- | --- | --- |
| module | lower snake case | `axi4_interconnect` |
| port | semantic name plus direction suffix | `addr_i`, `resp_err_o`, `data_io` |
| low-active port | polarity before direction | `irq_n_o`; project reset spelling is `rst_n_i` |
| local signal | `s_` plus semantic name | `s_cmd_valid`, `s_timeout_q` |
| instance | `u_` plus role or function | `u_rx_fifo`, `u_cfg_ribp` |
| next/current state | `_d` / `_q` | `s_state_d`, `s_state_q` |
| pipeline state | `_q2` / `_q3` | `s_addr_q2` |
| enum typedef | lower snake case plus `_e` | `uart_state_e` |
| other typedef | lower snake case plus `_t` | `sysctrl_offset_t` |
| parameter | typed UpperCamelCase | `DataWidth`, `TimeoutCycles` |
| global macro | namespaced ALL_CAPS | `RETROSOC_UART__BAUD` |

Protocol and technology names are stable interface vocabulary, not local
abbreviations. Keep standard AXI/APB/RIBP fields such as `valid`, `ready`,
`wdata`, `wstrb`, `rdata`, and `resp` unchanged. Do not mechanically rename
software-visible register macros, PDK pins, generated bindings, or managed IP.
A public rename requires a compatibility wrapper, a filelist update, and an
affected simulation/formal review.

Use the approved local aliases in `rtl/rtl_style_manifest.json` only when they
remain unambiguous (`cmd`, `req`, `resp`, `addr`, `cfg`, `stat`, `cnt`, and
similar). New aliases require a manifest update and review. Instance names
must identify their function rather than their order: use `cfg_ribp` or
`u_sdram_data_ribp_if`, not `if0` or `bus1`.

New FSMs use a typed enum with an `_e` type and descriptive values; opcode,
response, register offset, and field constants remain ALL_CAPS because they
are protocol or software-facing values. Existing `FSM_*`, `SOC_*`, `RIB_*`,
and `RIBP_*` names are compatibility baseline and migrate only in isolated,
reviewed batches.

### 4.1 Identifier grammar and semantic order

For a new internal identifier, construct the name from the meaningful parts in
this order: `<block>_<channel>_<role>_<property>_<state>_<latency>_<polarity>_<direction>`.
Only include parts that add information. For example, use
`s_uart_rx_fifo_full`, `s_sdram_read_pending_q`, or `irq_n_o`; do not create
names such as `signal_a`, `tmp2`, or `data_new_new`.

The following rules are normative:

1. Use lower snake case for RTL identifiers. Do not mix camel case, hyphens,
   or arbitrary capitalization in a single naming family.
2. Use the same name at adjacent hierarchy boundaries when a signal is passed
   through unchanged. Rename only at a semantic conversion boundary.
3. Put polarity before direction: `ready_n_o`, `reset_n_i`, and
   `data_io`. The project exception is the established spelling `rst_n_i`;
   do not introduce `rst_ni`.
4. Name clocks `clk_i` for the default domain and `clk_<domain>_i` for other
   domains, such as `clk_axi_i` or `clk_aud_i`. Name their resets
   `rst_n_i` or `rst_<domain>_n_i`.
5. Use `_d` for next-state combinational storage and `_q` for registered
   current state. Use `_q2` and `_q3` for explicit pipeline stages, not for
   arbitrary copies. Pair declarations adjacently.
6. Use `_en` only for a state/register update enable. Use `_pulse` or `_evt`
   for a one-cycle event, `_sticky_q` for software-cleared sticky state,
   `_pending_q` for an issued-but-not-completed transaction, `_busy_q` for a
   resource that cannot accept work, and `_cnt_q` or `_idx_q` for counters and
   indices.
7. Keep `valid`, `ready`, `accept`, `pending`, `busy`, `pulse`, and `sticky`
   distinct. For a handshake, prefer `s_req_valid`, `s_req_ready`, and
   `s_req_accept` (`valid && ready`) over an ambiguous `s_req` signal.
8. Use full words in public APIs and the approved short aliases only for local
   signals. The whitelist is `cmd`, `req`, `resp`, `addr`, `en`, `err`,
   `stat`, `cnt`, `cfg`, `src`, `dst`, `evt`, `tgt`, `sel`, and `len`.
9. Name errors by the failing contract: `cfg_err`, `access_err`, `resp_err`,
   `timeout_err`, `pll_err`, and `overflow_err` are different conditions and
   MUST NOT be collapsed into a generic `error` signal.

### 4.2 Modules, interfaces, and instances

1. Use lower snake case for modules and keep the source file and primary
   module aligned. Use established functional suffixes: `_wrapper`, `_ctrl`
   or `_controller`, `_reg`, `_core`, `_if`, `_pkg`, `_formal`,
   `_formal_props`, and `_tb`.
2. Name bus adapters with the repository's numeric `2` convention:
   `rib2apb`, `rib2ram`, `ribp2axi4`, `axi42ribp`, and `axi42ram`. New code
   MUST NOT introduce another `_to_` spelling for the same conversion.
3. Use function-qualified interface instances such as `cfg_ribp`,
   `mem_ribp`, `dma_axi`, and `apb_periph`. Do not use `if0`, `bus0`,
   `interface_a`, or names based only on declaration order.
4. Keep standard protocol field names unchanged. AXI, APB, RIB, and RIBP
   fields such as `valid`, `ready`, `wdata`, `wstrb`, `rdata`, `resp`, and
   `resp_err` are interoperability vocabulary, not local style debt.
5. Existing generic public modules such as `rcu` or `bus` are not renamed in
   place. New functionality should use a qualified name such as
   `soc_rcu`, `pll_rcu_controller`, `rib_bus`, or `axi4_bus`; migrate an
   existing public name only through a wrapper and a reviewed filelist change.

### 4.3 Parameters, types, FSMs, and constants

1. Name module parameters with typed UpperCamelCase: `DataWidth`, `AddrWidth`,
   `NumMasters`, `NumTargets`, `FifoDepth`, `TimeoutCycles`, `ExtClkHz`, and
   `ResetValue`. Do not use unqualified `DW`, `AW`, `N`, `NUM`, or `PARAM1`.
2. Use UpperCamelCase for module-private `localparam` values as well. Put
   protocol ABI and register-map constants in a package or reviewed header;
   keep implementation-only masks and timing constants local.
3. Name typedefs with lower snake case and `_t`; name enum typedefs with `_e`.
   New FSMs use a distinct typed enum for each state machine, for example:

   ```systemverilog
   typedef enum logic [2:0] {
     Idle,
     ReadReq,
     ReadResp,
     ErrorResp
   } state_e;
   state_e s_state_d, s_state_q;
   ```

   Use descriptive UpperCamelCase values for states. Use ALL_CAPS for
   opcodes, response codes, register offsets, field positions, and other
   protocol/software-visible constants.
4. Name global macros with a block namespace and a double underscore, such as
   `RETROSOC_RIB__RESP_OK`, `RETROSOC_RIBP_UART__BAUD`, and
   `RETROSOC_GPIO__PIN_COUNT`. Use include guards such as
   `RETROSOC_<FILE>_SVH`. Local macros use a single leading underscore and
   MUST be undefined after use.
5. Do not use a macro for a value that can be expressed as a parameter,
   localparam, package constant, function, or enum. Existing `SOC_*`,
   `RIB_*`, `RIBP_*`, and standard protocol macro names remain compatibility
   exceptions until their consumers are migrated.

### 4.4 Compatibility and migration boundaries

1. Apply the strict naming rules to new or modified self-owned RTL first. The
   existing tree is migrated in module-sized batches with a reviewed baseline;
   a new change MUST NOT increase the legacy naming debt.
2. Do not mechanically rename ClusterIP Common, PDK, generated, managed,
   vendored, or third-party sources. Update those through their upstream or
   locked integration flow.
3. Do not change software-visible register macros, memory-map symbols,
   protocol fields, module filelist entries, or technology pin names as part of
   a local style cleanup. Preserve the old public name with a compatibility
   wrapper or alias until every consumer has moved.
4. A public rename is complete only after the wrapper/filelist migration,
   Verible and Verilator checks, affected simulation and formal proofs, and a
   review of generated artifacts. Keep public renames separate from functional
   changes so equivalence and regression failures are attributable.

Public interfaces, protocol fields, register fields, and technology pins keep
their required names. Local signals MAY use only approved concise aliases:

| Long form | Local form |
| --- | --- |
| command | `cmd` |
| request | `req` |
| response | `resp` |
| address | `addr` |
| enable | `en` |
| error | `err` |
| status | `stat` |
| counter | `cnt` |
| configuration/config | `cfg` |
| source | `src` |
| destination | `dst` |
| event | `evt` |
| target | `tgt` |
| select | `sel` |
| length | `len` |

New abbreviations require review and an update to `rtl/rtl_style_manifest.json`.
Use `_t` for typedefs, `_e` for enum types, `ALL_CAPS` for macros, and typed
UpperCamelCase for new parameters. Global macros use the
`RETROSOC_<BLOCK>__<NAME>` namespace; IP register macros use
`RIBP_<IP>__<REGISTER>`. Prefer a package, enum, localparam, or parameter over
a macro when the value does not cross a preprocessing boundary.

Declare explicit widths and signedness for parameters, ports, constants, and
internal signals. Use sized literals such as `8'h00` and `16'd42`. Do not rely
on implicit truncation, extension, unsized arithmetic, or signed conversion.
Cross-module shared typedefs, enums, and protocol constants belong in a
versioned package; module-private values use `localparam`. Avoid unqualified
`import pkg::*` across IP boundaries.

## 5. Module structure and structural connections

Order a module as: header, parameters, ports, localparams, internal signals,
interface/structural assignments, combinational logic, sequential logic,
instances, and assertions. Declare every signal before executable code.

Use structural HDL for hierarchy and named interconnections. Every owned
instance MUST use named parameter and port connections. Unused inputs MUST be
tied to an explicit value; unused outputs MAY use an empty named connection
only with a comment explaining it. Every synthesizable signal has one driver.

Use `logic` for ordinary synthesizable signals. Reserve `wire` for resolved
multi-driver nets, pads, tri-state buses, or technology models, and document the
net semantics. Do not use on-chip tri-state logic to implement a mux.

Every `generate` if/else branch and for-loop MUST have a lower-snake-case label
so that hierarchy is stable across tools and configurations.

## 6. Combinational logic, registers, and FSMs

Use `always_comb` for procedural combinational logic and `always_ff` for
sequential logic. Use blocking assignments in combinational blocks and
non-blocking assignments in sequential blocks. Prefer continuous assignments
for simple wiring and muxes.

Every combinational block assigns defaults to all outputs and next-state
signals. A sequential block contains reset behavior, explicit enable/update
conditions, and assignments of already-computed next-state values. Do not put
large datapaths or unrelated decode inside a flip-flop process.

Describe each register as an adjacent pair: input/next-state combinational
logic followed by a ClusterIP Common register primitive such as `dffr`,
`dffer`, `dffrc`, or `dfferc`. Enables MUST be visible in the selected primitive
or next-state condition.

Describe FSMs with `typedef enum logic`, `state_d/state_q`, a combinational
decode block, and a clocked state register. Include an explicit illegal-state
recovery branch. Moore outputs depend on state; Mealy outputs document their
input-dependent timing.

## 7. Widths, operators, and invalid values

Do not use a multi-bit vector directly as a Boolean condition. Write an
explicit comparison such as `value != '0`, a reduction operator, or a bit
select. Use bitwise operators (`~`, `&`, `|`, `^`) for data and logical
operators (`!`, `&&`, `||`) for predicates. Parenthesize mixed-width or mixed
signedness expressions and use explicit casts where needed.

`X` is unknown/conflicting simulation information, not ordinary synthesizable
data. Do not assign `X` to hide an uninitialized register, illegal state, or
unhandled case. Use deterministic safe behavior and SVA to detect invalid
usage. `Z` is limited to pads, intentional tri-state interfaces, and technology
models. Guard dynamic array indices when an out-of-range value could be
observed.

## 8. Clock, reset, CDC, and protocol contracts

The default domain uses `clk_i` and `rst_n_i`. Additional domains use a stable
qualified form such as `clk_axi_i` and `rst_axi_n_i`. Every CDC crossing records
source domain, destination domain, reset assumptions, and the approved
synchronizer, handshake, or asynchronous FIFO primitive.

Each bus or streaming interface documents acceptance, backpressure, response
error behavior, reset values, and outstanding-transaction limits. RIB/RIBP and
AXI adapters MUST make burst boundaries, response timing, and access permissions
explicit at the module boundary.

## 9. Assertions, formal, and IP readiness

Self-owned IP SHOULD include SVA for reset release, handshakes, FIFO bounds,
mutual exclusion, legal FSM states, and register access permissions. Formal and
testbench-only constructs use the verification profile and do not weaken the
synthesizable profile.

An IP is `verified` only when it has interface and register documentation,
clock/reset and CDC notes, architecture/FSM diagrams, simulation and formal
results, lint/format results, and an affected synthesis/STA result. A
`tapeout-ready` label additionally requires reviewed warnings, filelists, PDK
mapping, and release artifacts.

### Design maturity and RTL freeze

The machine-readable record in [`rtl/rtl_readiness.json`](../rtl/rtl_readiness.json)
uses four states:

- `prototype`: interfaces and implementation may change; no compatibility claim
  is made.
- `verified`: interfaces, registers, reset behavior, timing intent, and the
  applicable simulation, lint, formal, synthesis, and STA evidence are reviewed.
- `rtl-freeze`: only formatting, comments, or changes proven logically
  equivalent to the recorded baseline are allowed.
- `tapeout-ready`: freeze evidence is complete and PDK mapping, warning/metric
  baselines, SDC, filelists, and release artifacts are reviewed.

A change to an interface, register map, reset, timing contract, or CDC behavior
is not a style-only change. Freeze and release records must include the baseline
revision, configuration digest, evidence paths, and reviewed waivers. Run
`make rtl-readiness-check-all` before promoting a target.

### Synthesis intent audit

The readiness record captures the expected storage primitive, reset precedence,
clock-enable behavior, memory inference/instantiation policy, and pipeline
boundaries. The expectation must be checked against the actual Yosys/library
reports and OpenSTA results; an RTL pattern alone is not evidence that the
intended cell or memory was inferred. Area, cell count, WNS/TNS, and firmware
size remain sourced from `meta/metrics.json` and the existing metrics policy.

## 10. Formatting, comments, and tools

Owned RTL uses ASCII, Unix line endings, a 100-column limit, spaces instead of
tabs, no trailing whitespace, and a final newline in every non-empty file.
Use the root [`.verible-format`](../.verible-format) configuration. A narrow
`verilog_format: off/on` region is allowed only when the formatter cannot keep
required macro or port alignment; manually align it and explain the exception.

Use `//` comments for interface behavior, cycle timing, reset, CDC, ownership,
synthesis intent, or non-obvious constraints. Do not narrate syntax.

Run the following checks locally:

```sh
make rtl-format-check
make rtl-style-check
make rtl-lint
```

`rtl-style-check` checks changed owned RTL. `rtl-style-check-all` checks all
owned RTL and is used by nightly/release flows. Verilator performs semantic
linting for width, signedness, implicit conversion, and driven-signal issues;
Verible performs style linting. Fix findings before waiving them, and review
every waiver in the pull request.

`rtl-readiness-check` validates the maturity and synthesis-intent record;
`rtl-readiness-check-all` is the release/nightly form. It checks metadata and
evidence paths, not RTL behavior, and therefore complements rather than replaces
simulation, formal, synthesis, STA, CDC, warning, and metric checks.

## Reference

These rules also incorporate the architecture-first RTL guidance in the
[ETH Zürich VLSI RTL lecture](https://vlsi.ethz.ch/w/images/d/de/02_RTL.pdf).
The retroSoC naming and Common register rules above override examples in that
lecture where the project intentionally uses different conventions.
