# retroSoC RTL Coding Style

This document is the source of truth for self-owned RTL coding and formatting.
It applies to `rtl/ip/**` and `rtl/mini/top/**`. Formal, device-model, PDK,
generated, and third-party sources use the profiles declared in
[`rtl/rtl_style_manifest.json`](../rtl/rtl_style_manifest.json).

## Naming

Use `clk_i` and `rst_n_i` for clock and active-low reset ports. Do not rename
the reset to `rst_ni`. Use `_i`, `_o`, and `_io` for input, output, and
bidirectional ports; `s_` for local signals; and `u_` for instances. A state
register has adjacent `s_<name>_d` and `s_<name>_q` signals, with
`s_<name>_en` for a write enable.

New local signals use concise industry-standard abbreviations:

| Long form | RTL form |
| --- | --- |
| command | `cmd` |
| request | `req` |
| response | `resp` |
| address | `addr` |
| enable | `en` |
| error | `err` |
| status | `stat` |
| counter | `cnt` |
| configuration | `cfg` |
| select | `sel` |
| length | `len` |

Do not change an external protocol field only to shorten its name. Use a local
alias at the boundary when a legacy or third-party interface uses a long name.

The checked-in [`scripts/migrate_rtl_names.py`](../scripts/migrate_rtl_names.py)
helper applies this rule mechanically: it shortens only `s_`/`r_` locals and
known automatic variables, never a public port or interface member.

## Source and Module Boundaries

Keep one self-owned SystemVerilog module per source file. The file name and the
primary module name must match, including case. This keeps filelists,
dependency tracking, lint diagnostics, and synthesis reports unambiguous. A
small set of closely related declarations may remain in a shared package or
interface file when that is the established repository pattern; do not use a
multi-module source file as a shortcut for unrelated hierarchy.

SystemVerilog is case-sensitive. Use lower snake case consistently and do not
create identifiers that differ only by capitalization. Every public interface
member and technology-facing pin keeps the spelling required by its protocol
or PDK; local aliases may use the concise naming rules above.

## Types, Widths, and Operators

Declare the width and signedness of constants, parameters, ports, and internal
signals explicitly. The left and right sides of an assignment should have the
same intended width; do not rely on implicit truncation, extension, or signed
conversion. Use sized literals with a visible base, for example `8'h00`,
`16'd42`, or `4'b0011`, and use underscores only to improve readability.

Keep bitwise and logical operators distinct. Use `~`, `&`, `|`, and `^` for
vector or bit-level hardware operations. Use `!`, `&&`, and `||` for Boolean
conditions and predicates. Parenthesize mixed-width arithmetic and mixed
operator expressions when precedence is not immediately obvious.

Use `logic` for ordinary synthesizable signals. Reserve `wire` for signals
whose net semantics are required, such as resolved multi-driver nets,
tri-state buses, PDK pads, or technology models. A synthesizable signal must
have one driver: do not assign the same signal from multiple processes, a
process and a continuous assignment, or multiple continuous assignments.

## Structure

Keep each module in this order: module header, parameters, ports, localparams,
internal declarations, combinational next-state logic, sequential logic,
instances, and assertions. Use `logic` for synthesizable data and state. Use
`wire` only where net resolution is required, such as PDK pads, tri-state
signals, and technology models.

Keep control logic and datapath logic in the same module when they are tightly
coupled and expected to evolve together. Use hierarchy to divide independent
functions, share a reusable implementation, isolate a clock/reset domain, or
give separate teams and tools a clear ownership boundary. Do not introduce a
control-only or datapath-only wrapper solely to move a handful of signals.

Use `always_ff` for sequential logic and `always_comb` for combinational logic.
Give every combinational block complete defaults and every `case` statement an
explicit `default`. Reuse the ClusterIP Common register cells (`dffr`, `dffer`,
`dffrc`, `dfferc`, and related variants) for local state. Do not add
`initial`-based synthesizable state.

Use blocking assignments (`=`) in `always_comb` and non-blocking assignments
(`<=`) in `always_ff`. Use `always_latch` only when level-sensitive storage is
an intentional architectural requirement; latches are otherwise avoided in
self-owned SoC RTL. Prefer a continuous assignment for a simple Boolean or
multiplexer expression instead of a process with a manually maintained
sensitivity list.

Every combinational process must assign a default to each output and next-state
signal before conditional logic. Every sequential process must describe a
reset value and then update only the present-state registers it owns. An
enable or condition should gate an update, not create an accidental clock or
partial assignment. These rules make inferred storage and clock-enable intent
visible to lint, synthesis, and review.

Every module instance in self-owned RTL must use named parameter and port
connections. Empty connections are permitted only for intentionally unused
technology pins or interface fields and must be documented.

For existing positional instances, use the conservative
[`scripts/migrate_rtl_connections.py`](../scripts/migrate_rtl_connections.py)
helper. It only changes an instance when the declaration and argument counts
are unambiguous. Instances it reports as ambiguous require manual conversion;
the helper never guesses across duplicate or non-ANSI module declarations.

## State Machines and RTL Architecture

Represent finite-state-machine states with a named `typedef enum logic` when
the state encoding is not itself a public protocol. Maintain paired
`state_d`/`state_q` signals, initialize `state_d` from `state_q`, and include a
`default` branch that recovers from an illegal encoding. Moore outputs should
depend on state only; Mealy outputs may additionally depend on current inputs
and must document any timing consequence.

Before implementing a non-trivial block, document a clean architecture,
signal-level block diagram, clock/reset domains, and an FSM transition diagram
where applicable. RTL is a clocked transfer of present state through
combinational logic into next state; make cycle boundaries, handshakes, and
backpressure explicit rather than relying on simulator scheduling behavior.

Keep datapath operations and control decisions conceptually separate even when
they share a module. Control should generate enables and selects, while the
datapath performs arithmetic, comparison, storage, and multiplexing. Avoid
placing large arithmetic datapaths inside deeply nested FSM conditionals unless
the resulting timing and resource intent is deliberate.

Use `begin`/`end` for multi-statement branches, nested branches, and branches
whose body may grow during maintenance. Keep indentation consistent and do
not rely on a single-line branch for safety-critical state updates.

## Comments and Intent

Use `//` comments for short intent statements. Comments should explain the
interface contract, cycle timing, reset assumptions, CDC rationale, ownership
of a signal, or a non-obvious synthesis constraint. Do not narrate syntax or
duplicate the code. Keep comments next to the rule they justify, especially
around `verilog_format: off/on`, intentional empty connections, tri-state
drivers, and lint waivers.

## Formatting

Run:

```sh
make rtl-format-check
make rtl-style-check
```

The root [`.verible-format`](../.verible-format) enables alignment for module
ports, named ports/parameters, declarations, assignments, case items, macros,
and struct members. `.svh` macro definitions and `.sv` module ports are kept in
columns. If Verible cannot preserve a required table, use a narrow region:

```systemverilog
// verilog_format: off
...
// verilog_format: on
```

Manually align every existing exception and add a comment explaining why the
exception is needed. Do not wrap an entire module in `format off`.

## Ownership boundaries

Do not hand-format or rename files below `rtl/managed`, generated MPW output,
or vendored CPU sources. Update those inputs through their locked setup flow.
PDK wrappers in `rtl/tech` preserve cell pin names and net semantics; they are
compiled and elaborated but are not subjected to the self-owned naming rules.
Formal properties and testbench models are checked with a verification profile
that permits bind-time wires and simulator-only constructs.

## Reference

These practices are distilled from the ETH Zürich VLSI RTL lecture,
[`02_RTL.pdf`](https://vlsi.ethz.ch/w/images/d/de/02_RTL.pdf), including its
guidance on one module per file, explicit widths, single-driver signals,
intent-specific `always_*` processes, `_d`/`_q` state naming, enumerated FSMs,
and architecture-first RTL design. The repository-specific rules in this
document take precedence where the lecture uses different conventions, such
as `rst_ni` or `_c`; retroSoC continues to require `rst_n_i` and `clk_i`.
