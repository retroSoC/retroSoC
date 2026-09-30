# Behavior-preserving RTL migration

Use this reference only for an explicitly scoped style/naming/structural
migration or review of such a change. The feature skill's existing approved
scope and phase rules still apply; this reference does not authorize a broad
cleanup. Read the [normative style](../../../../docs/rtl-coding-style.md),
[compliance process](../../../../docs/rtl-coding-style-compliance.md), and
[ownership manifest](../../../../rtl/rtl_style_manifest.json).

Before editing, record the original source/configuration and available baseline
evidence. Locate all consumers of renamed files, modules, ports, and identifiers:
filelists, topologies, testbenches, formal harnesses, generators, scripts, and
documentation. Include affected existing Tiny/Mini integrations without
extending unrelated products.

Keep managed IP names, protocol fields, and technology pins at their defined
boundaries. Do not edit a vendor subtree or expand a formatter's ownership just
to pass a check. Apply narrow, justified formatter exceptions only where the
normative policy allows them.

For sequential/structural rewrites, compare reset polarity and priority,
synchronous/asynchronous behavior, enables, latency, backpressure, CDC/RDC,
memory inference, and software-visible ABI. Reuse Common components only when
these semantics match exactly. Inferred RAM, dual-clock storage, and
priority-sensitive logic need cycle or sequential-equivalence evidence before
accepting the replacement; style/lint success is not that evidence.

Update the audit inventory when the reviewed owned source set changes. An audit
record is evidence of review, not a waiver or a warning baseline. Preserve the
owner, lifetime, and removal rationale of legitimate reviewed boundaries.

Run the affected formatting/style/readiness, elaboration/lint, parity, focused
simulation/formal/equivalence, and target-specific regression checks. Adapt the
compliance document's example commands to the selected product via the
[regression reference](regression.md); do not assume its Mini example is Tiny's
acceptance rule.

Treat a functional, storage, reset, CDC, protocol, software-visible, or material
synthesis/timing difference as a blocker. Record a separate functional issue
and route it for evidence-based diagnosis and approval, rather than silently
repairing or accepting it inside the style migration. Report unavailable
equivalence evidence explicitly and do not claim behavior preservation from
formatting or incomplete simulation alone.
