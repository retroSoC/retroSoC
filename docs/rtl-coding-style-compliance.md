# RTL Coding Style Compliance

This document defines the executable compliance process for self-owned RTL.
The normative requirements remain in [RTL Coding Style](rtl-coding-style.md);
this document records how those requirements are reviewed, enforced, and
validated without changing functional behavior.

## Scope and Evidence

The owned profile in
[`rtl/rtl_style_manifest.json`](../rtl/rtl_style_manifest.json) is the source
of truth for the reviewed source set. It includes `rtl/ip/**` and
`rtl/mini/top/**`, but excludes managed, generated, PDK, formal, device-model,
and third-party sources.

[`rtl/rtl_style_audit.json`](../rtl/rtl_style_audit.json) records the exact
owned files, policy revision, review method, and reviewed integration
boundaries. The audit record is evidence of review, not a waiver or a warning
baseline. It must be refreshed whenever a source enters or leaves the owned
profile.

A reviewed boundary does not hide a remediable violation. It is limited to a
behavior-preservation block, such as dual-clock storage, inferred memory, a
technology pin boundary, or priority-sensitive sequential logic. The audit
record names its owner, related commit, expiry condition, and removal plan;
the block must be removed by an isolated, equivalence-validated change.

## Rule Matrix

| Rule group | Policy sections | Evidence |
| --- | --- | --- |
| File and primary-unit ownership | 2 | Full-profile checker verifies a primary design unit and its file name; filelist and elaboration checks validate moves. |
| Restricted SystemVerilog subset | 3 | `check_rtl_style.py`, Verible, and simulator compilation reject prohibited timing controls, tasks, positional connections, wildcard connections, implicit nets, `defparam`, `casex`, and legacy procedural blocks. |
| Naming, types, packages, and macros | 4 | Full-profile naming check enforces staged module, port, interface, enum, parameter, macro, and reset spelling rules. Review verifies public protocol and PDK names remain at their compatibility boundaries. |
| Structure and connections | 5 | Checker and Verible validate named connections, generated-block labels, net restrictions, and format hygiene. Review verifies one-driver ownership, explicit unused-output rationale, and declared-before-use ordering. |
| Combinational, sequential, and FSM logic | 6 | Review checks defaults, assignment style, reset/update priority, state naming, Common primitive selection, and illegal-state behavior. Structural register rewrites require cycle or sequential-equivalence evidence. |
| Width, signedness, and invalid values | 7 | Verilator lint and review cover explicit widths, casts, predicates, dynamic indices, and X/Z restrictions. |
| Clock, reset, CDC, and interfaces | 8 | Module-boundary comments, `clock_reset_domains.json`, CDC primitive review, protocol tests, and affected simulator runs supply evidence. |
| Assertions and readiness | 9 | Applicable SVA/formal tests and `rtl-readiness-check-all` supplement functional simulation; readiness metadata is not a substitute for verification. |
| Formatting and comments | 10 | `rtl-format-check` and the full-profile style check enforce ASCII, whitespace, final newline, line length, and paired formatter directives. A formatter-disabled span must be narrow and state why aligned declarations cannot be preserved otherwise. |

## Behavior-Preserving Migration

Style work must not alter storage behavior, reset precedence, CDC behavior,
protocol timing, register ABI, or software-observable behavior. Apply the
following sequence for every change:

1. Rename an owned file, module, or internal identifier only after locating
   every filelist, testbench, formal harness, generator, and documentation
   consumer.
2. Keep protocol fields, PDK pins, and managed IP names at their boundary.
   Adapt them only from owned RTL; never edit managed or PDK source to make a
   local style check pass.
3. Prefer ClusterIP Common `dffr`, `dffer`, `dffrc`, `dfferc`, CDC, FIFO, and
   register components when they exactly preserve the existing reset and
   enable semantics. Do not replace inferred memories, dual-clock storage, or
   priority-sensitive sequential logic without equivalence evidence.
4. Treat a simulation, formal, synthesis, timing, or software-visible
   difference as a blocker. Record it as a separate functional issue rather
   than resolving it as part of a style migration.

## Formatter Exceptions

The root `.verible-format` configuration normally aligns module ports,
parameters, macros, named ports, and assignments. Use
`// verilog_format: off/on` only for the smallest declaration or macro table
that Verible cannot preserve. The `off` line must state the alignment reason;
the paired `on` line must follow immediately after the exceptional region.

## Required Validation

Run these commands after a full owned-profile migration:

```sh
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES rtl-lint
python3 -m pytest -q
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
```

The boot-only netlist target terminates Icarus only after `Hello retroSoC!` is
observed. The regression runner continues with the remaining OpenSTA, warning,
and metrics observations. Review warning and metric deltas from the successful
variant; never hand-edit warning signatures.
