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

## Structure

Keep each module in this order: module header, parameters, ports, localparams,
internal declarations, combinational next-state logic, sequential logic,
instances, and assertions. Use `logic` for synthesizable data and state. Use
`wire` only where net resolution is required, such as PDK pads, tri-state
signals, and technology models.

Use `always_ff` for sequential logic and `always_comb` for combinational logic.
Give every combinational block complete defaults and every `case` statement an
explicit `default`. Reuse the ClusterIP Common register cells (`dffr`, `dffer`,
`dffrc`, `dfferc`, and related variants) for local state. Do not add
`initial`-based synthesizable state.

Every module instance in self-owned RTL must use named parameter and port
connections. Empty connections are permitted only for intentionally unused
technology pins or interface fields and must be documented.

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
