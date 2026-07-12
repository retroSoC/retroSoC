# MISRA C:2012 Amendment 2 Policy

## Status and Scope

retroSoC adopts **MISRA C:2012 with Amendment 2** as the mandatory embedded-C
development baseline for self-owned SDK and application C/header code.

The scope is self-owned code below `crt/` and `app/`. The exclusions in
[`quality/embedded_c_policy.json`](../quality/embedded_c_policy.json) are
authoritative: they cover managed upstream sources, generated or compatibility
material, and selected external ports. This policy does not claim MISRA
conformance for excluded code, assembly, linker scripts, generated files, or
third-party dependencies.

This is an engineering baseline, not a claim of independently certified or
complete MISRA compliance. The repository currently has partial mechanical
enforcement; full rule coverage requires a qualified static-analysis workflow
and reviewed evidence for the applicable rules.

## Compliance Expectations

- Applicable Mandatory rules must be followed and are not waived.
- Applicable Required rules must be followed unless an approved record exists
  in [`quality/misra/deviations.md`](../quality/misra/deviations.md).
- Applicable Advisory rules require review. A decision not to follow one must
  have a proportionate rationale in the code review or a deviation record.
- New code must preserve the freestanding runtime model and use project public
  interfaces through `<retrosoc/...>` headers.
- Developers must use fixed-width integer types where width matters, check
  null pointers and bounds at API boundaries, make narrowing conversions and
  signedness choices explicit, and review arithmetic for overflow.
- Use `rs_status_t` for fallible operations. Prefer bounded string/format APIs
  and timeout-based register waits. Dynamic allocation is not permitted in
  self-owned embedded C.
- New `tiny` identifiers, legacy include paths, and prohibited library calls
  are not allowed outside the compatibility files explicitly listed by policy.

The standard is referenced by name and category only. Consult the licensed
MISRA publication for the complete rule text and applicability guidance; do
not copy rule text into repository code or documentation.

## Existing Mechanical Enforcement

| Evidence | Current coverage | Limitation |
| --- | --- | --- |
| `make sw-format-check` | Project formatting, line endings, whitespace, and `clang-format-14` compatibility. | Formatting is not MISRA analysis. |
| `make sw-policy-check` | Retired names/includes and selected unsafe-library calls. | Enforces only project-selected rules. |
| RISC-V compiler warnings | Format, prototype, shadowing, pointer/type conversion, and return-value diagnostics. | Compiler warnings do not cover all MISRA rules. |
| `make sw-host-test` | Deterministic runtime, parser, and helper behavior. | Does not prove hardware behavior or static-rule compliance. |
| Regression and warning baselines | Firmware build, simulation, EDA warnings, and implementation regressions. | Does not replace source-level MISRA analysis. |

Run the smallest relevant validation set in addition to a MISRA review:

```sh
make sw-format-check
make sw-policy-check
make sw-host-test
make CONFIG=configs/ci/hazard3-rv32im-ihp130.mk firmware
```

Use the affected profile and simulator for hardware-facing changes. See
[`AGENTS.md`](../AGENTS.md) and [Engineering Workflow](engineering.md) for the
complete validation matrix.

## Deviations

Record each approved Required-rule deviation in
[`quality/misra/deviations.md`](../quality/misra/deviations.md) in the same
change as the affected code. The record must identify the rule, exact source
location, affected scope, safety rationale, mitigation, reviewer approval, and
review/removal date.

Do not use deviations to silently grandfather unrelated legacy code. If a
deviation is no longer needed, remove the record in the change that removes the
exception.
