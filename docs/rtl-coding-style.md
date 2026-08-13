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
Use `_t` for typedefs, `_e` for enum types, `ALL_CAPS` for macros, and the
repository's established parameter naming convention.

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

## Reference

These rules also incorporate the architecture-first RTL guidance in the
[ETH Zürich VLSI RTL lecture](https://vlsi.ethz.ch/w/images/d/de/02_RTL.pdf).
The retroSoC naming and Common register rules above override examples in that
lecture where the project intentionally uses different conventions.
